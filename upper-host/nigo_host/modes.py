"""Resident Nigo CPU modes; no reset, ROM jump or application overwrite on switch."""
import argparse,hashlib,json,secrets,socket,struct,time
from contextlib import closing
from pathlib import Path
from .client import Endpoint
from .program import ProgramClient,validate_image

NAMES={0:'待机',1:'图像接收',2:'人脸检测',3:'CoreMark',4:'游戏',5:'按键诊断'}
REQUEST=struct.Struct('!4s7I');REPLY=struct.Struct('!4s13I')
FIELDS=['version','op','session','sequence','error','active','target','generation','busy','flags','build_id','capabilities','reserved']
class ModeRejected(RuntimeError):
    def __init__(self,state):
        self.state=state
        super().__init__('模式切换被拒绝：'+{1:'已有切换正在排空任务',2:'请求格式或目标不支持',3:'状态已变化，请重新切换'}.get(state['error'],str(state['error'])))
def decode(data,op,session,sequence):
    if len(data)!=REPLY.size:return None
    magic,*values=REPLY.unpack(data);s=dict(zip(FIELDS,values))
    if magic!=b'NMR1' or (s['version'],s['op'],s['session'],s['sequence'])!=(1,op,session,sequence):return None
    if s['active'] not in NAMES or s['target'] not in NAMES or s['reserved'] or s['busy']&~63 or s['flags']&~1:raise ValueError('统一固件状态格式错误')
    return s

class ModeClient:
    def __init__(self,endpoint,port=5001,timeout=.2):
        self.peer=(endpoint.board,port);self.timeout=timeout;self.session=secrets.randbits(32) or 1;self.sequence=secrets.randbits(32)
        self.socket=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        try:self.socket.bind((endpoint.local,0))
        except Exception:self.socket.close();raise
    def close(self):self.socket.close()
    def call(self,op,target=0,generation=0,retries=4):
        self.sequence=(self.sequence+1)&0xffffffff
        packet=REQUEST.pack(b'NMQ1',1,op,self.session,self.sequence,target,generation,0)
        for _ in range(retries):
            self.socket.sendto(packet,self.peer);deadline=time.monotonic()+self.timeout
            while time.monotonic()<deadline:
                self.socket.settimeout(max(.001,deadline-time.monotonic()))
                try:data,peer=self.socket.recvfrom(2048)
                except socket.timeout:break
                if peer!=self.peer:continue
                s=decode(data,op,self.session,self.sequence)
                if s is None:continue
                if s['error']:raise ModeRejected(s)
                return s
        raise TimeoutError('未收到统一固件状态应答')
    def select(self,target,timeout=120):
        if target not in NAMES:raise ValueError('未知 CPU 模式')
        deadline=time.monotonic()+timeout;s=self.call(1)
        if not(s['capabilities']&(1<<target)):raise ValueError('固件不支持此模式')
        if s['active']==s['target']==target:return s
        if s['active']!=s['target']:raise RuntimeError('板端已有模式切换正在进行，请等待完成后再试')
        expected=(s['generation']+1)&0xffffffff
        try:s=self.call(2,target,s['generation'])
        except TimeoutError:pass # Query completion; never invent a new SET after lost ACK.
        while time.monotonic()<deadline:
            try:s=self.call(1,retries=2)
            except TimeoutError:continue # CoreMark timing deliberately has no network polling.
            if s['generation']==expected and s['active']==s['target']==target:return s
            if s['generation'] not in ((expected-1)&0xffffffff,expected):raise RuntimeError('另一个请求改变了 CPU 模式，未覆盖其状态')
            time.sleep(.03)
        raise TimeoutError('等待模式切换超时；当前任务可能仍在运行或 DMA 未排空，未强制复位')

def activate(endpoint,target,progress=None,install=True,port=5001,firmware=None):
    """Install only after a positive Bootloader query; legacy apps are never overwritten."""
    installed=False
    with closing(ModeClient(endpoint,port)) as client:
        try:client.call(1,retries=3)
        except TimeoutError:
            if not install:raise
            path=Path(firmware) if firmware else Path(__file__).resolve().parents[1]/'assets/firmware/runtime.ngb'
            blob=path.read_bytes();manifest=json.loads(path.with_suffix('.json').read_text())
            validate_image(blob)
            if hashlib.sha256(blob).hexdigest()!=manifest['ngb_sha256'] or len(blob)!=manifest['ngb_bytes']:raise ValueError('统一固件文件与清单不一致')
            with closing(ProgramClient(endpoint.board,port,timeout=.15,retries=3,bind=endpoint.local)) as boot:
                try:boot.control(1)
                except TimeoutError as error:
                    raise RuntimeError('板端未应答统一协议。首次从旧独立程序迁移：按一次 KEY0，再点击模式页；若正在跑分，请等待完成。此后正常切换无需复位。') from error
                boot.retries=30;boot.download(blob,progress)
            deadline=time.monotonic()+5
            while True:
                try:s=client.call(1,retries=2);break
                except TimeoutError:
                    if time.monotonic()>=deadline:raise RuntimeError('固件执行请求已确认，但统一应用尚未应答；未自动重复下载')
            if s['build_id']!=int(manifest['build_id'],16):raise RuntimeError('启动的统一固件构建号不匹配')
            installed=True
        s=client.select(target)
        return dict(s,mode_name=NAMES[s['active']],installed=installed)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--board',default='192.168.1.50');p.add_argument('--bind',default='192.168.1.100')
    p.add_argument('--mode',type=int,choices=range(6),required=True);p.add_argument('--install',action='store_true');a=p.parse_args()
    print(json.dumps(activate(Endpoint(a.board,a.bind),a.mode,install=a.install),ensure_ascii=False,indent=2))
