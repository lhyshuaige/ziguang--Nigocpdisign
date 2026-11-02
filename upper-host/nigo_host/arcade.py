"""Receive board-rendered arcade frames. No game logic or synthetic frames here."""
import collections,secrets,socket,struct,threading,time,zlib

REQUEST=struct.Struct('!4s5I')
REPLY=struct.Struct('!4s15I')
FRAME=struct.Struct('!4s7I')
WIDTH,HEIGHT=320,240
MAX_ENCODED=WIDTH*HEIGHT*2
NAMES=['游戏菜单','飞机大战 + Boss','贪吃蛇','打砖块','落块游戏']
COLORS=[0x070d20,0x0e1934,0x162849,0x254568,0x367ca0,0x73d6ec,0xd8faff,0xef5573,
        0xff955c,0xffd67c,0x6d59c7,0x63efb0,0x29a59e,0xf0b4ff,0x946ff5,0x34465d,
        0x122039,0x203453,0x86a3b9,0xffffff,0x1a5770,0x543c6d,0x8b395d,0xb8cbdf]+[0]*8
PALETTE=[v for color in COLORS for v in [(color>>16)&255,(color>>8)&255,color&255]]+[0]*(768-96)

def decode_rle(data):
    if not data or len(data)>MAX_ENCODED or len(data)%2:raise ValueError('游戏帧 RLE 长度错误')
    out=bytearray()
    for i in range(0,len(data),2):
        count,color=data[i:i+2]
        if not count or color>=32 or len(out)+count>WIDTH*HEIGHT:raise ValueError('游戏帧 RLE 越界')
        out.extend(bytes([color])*count)
    if len(out)!=WIDTH*HEIGHT:raise ValueError('游戏帧像素数不完整')
    return bytes(out)

def decode_status(data,session):
    if len(data)!=REPLY.size:return None
    magic,*v=REPLY.unpack(data)
    if magic!=b'NGGS' or v[0]!=1 or v[3]!=session:return None
    if v[1] not in (1,2,3) or v[5]>4 or v[6]>3 or v[7]>15 or v[10:12]!=[WIDTH,HEIGHT] or v[14]!=0x41524331:raise ValueError('游戏状态格式或固件版本不匹配')
    keys=['version','op','sequence','session','error','mode','selected','keys','score','frame_id','width','height','logic_hz','target_fps','build_id']
    return dict(zip(keys,v))

class FrameAssembler:
    def __init__(self,session):
        self.session=session;self.identity=None;self.buffer=None;self.parts={};self.meta=None;self.done=False;self.dropped=0;self.complete=0
    def push(self,data):
        if len(data)<FRAME.size:return None
        magic,version,session,identity,total,offset,crc,dimensions=FRAME.unpack_from(data)
        if magic!=b'NGGF' or session!=self.session:return None
        payload=data[FRAME.size:]
        if version!=1 or dimensions!=(WIDTH<<16|HEIGHT) or not 2<=total<=MAX_ENCODED or total%2 or offset%224 or offset>=total or len(payload)!=min(224,total-offset):raise ValueError('游戏帧分包边界错误')
        if self.identity!=identity:
            if self.identity is not None:
                delta=(identity-self.identity)&0xffffffff
                if delta>=0x80000000:return None
                if self.parts and not self.done:self.dropped+=1
            self.identity=identity;self.meta=(total,crc);self.buffer=bytearray(total);self.parts={};self.done=False
        if self.done:return None
        if self.meta!=(total,crc):raise ValueError('同一游戏帧元数据冲突')
        if offset in self.parts:
            if self.parts[offset]!=payload:raise ValueError('游戏帧重复分包内容冲突')
            return None
        self.parts[offset]=payload;self.buffer[offset:offset+len(payload)]=payload
        if len(self.parts)!=(total+223)//224:return None
        self.done=True
        if zlib.crc32(self.buffer)!=crc:self.dropped+=1;raise ValueError('游戏帧 CRC 错误')
        pixels=decode_rle(self.buffer);self.complete+=1;return identity,pixels

class ArcadeStream:
    def __init__(self,endpoint,port=5003,control_port=5001,frame_source_port=5003):
        self.endpoint=endpoint;self.port=port;self.control_port=control_port
        self.frame_source_port=frame_source_port
        self.session=secrets.randbits(32) or 1;self.stop_event=threading.Event();self.thread=None
        self.latest=None;self.status=None;self.error=None;self.message='正在连接游戏应用…';self.frame_times=collections.deque(maxlen=120)
        self.assembler=FrameAssembler(self.session);self.invalid_packets=0;self.started=0;self.sequence=0
    def start(self):
        if self.thread:raise RuntimeError('Already started')
        self.thread=threading.Thread(target=self._run,daemon=True);self.thread.start()
    def stop(self):
        self.stop_event.set()
        if self.thread:self.thread.join(timeout=.6)
    def _run(self):
        sock=None
        try:
            board=socket.gethostbyname(self.endpoint.board);sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,1024*1024);sock.bind((self.endpoint.local,self.port));sock.settimeout(.1)
            target=(board,self.control_port);next_hello=0;last_seen=time.monotonic();self.started=last_seen
            while not self.stop_event.is_set():
                now=time.monotonic()
                if now>=next_hello:
                    self.sequence=(self.sequence+1)&0xffffffff;sock.sendto(REQUEST.pack(b'NGGQ',1,1,self.sequence,self.session,0),target);next_hello=now+.8
                if now-last_seen>5:raise TimeoutError('游戏应用没有应答；请检查连接，再点击“进入游戏模式”重新连接')
                try:data,peer=sock.recvfrom(2048)
                except socket.timeout:continue
                if peer[0]!=board or peer[1] not in (self.control_port,self.frame_source_port):continue
                try:
                    state=decode_status(data,self.session) if peer[1]==self.control_port else None
                    if state:
                        if state['error']:raise RuntimeError('游戏应用拒绝连接，错误码 %d（2 表示另一接收端仍占用）'%state['error'])
                        self.status=state;last_seen=now;self.message='已连接 · '+NAMES[state['mode']];continue
                    frame=self.assembler.push(data) if peer[1]==self.frame_source_port else None
                    if frame:self.latest=(frame[0],frame[1],time.monotonic());self.frame_times.append(self.latest[2]);last_seen=now
                except ValueError:self.invalid_packets+=1
        except Exception as error:self.error=str(error);self.message=self.error
        finally:
            if sock:
                try:sock.sendto(REQUEST.pack(b'NGGQ',1,2,self.sequence+1&0xffffffff,self.session,0),(self.endpoint.board,self.control_port))
                except OSError:pass
                sock.close()
    def stats(self):
        times=list(self.frame_times);now=time.monotonic();fps=(len(times)-1)/(times[-1]-times[0]) if len(times)>1 and now-times[-1]<2 else 0
        return dict(received=self.assembler.complete,dropped=self.assembler.dropped,invalid=self.invalid_packets,fps=fps,age=now-times[-1] if times else None)
