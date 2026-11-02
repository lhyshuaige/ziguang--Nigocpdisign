"""CoreMark board RPC, retained-log retrieval, and strict result validation."""
import argparse
import json
import re
import secrets
import socket
import struct
import time
import zlib
from pathlib import Path
from .client import Endpoint

REQUEST=struct.Struct('!4s5I')
REPLY=struct.Struct('!4s19I')
KEYS=['version','op','sequence','error','run_id','state','log_length','offset','chunk',
      'iterations_requested','cpu_hz','timer_hz','perf_hi','perf_lo','validation_hi',
      'validation_lo','log_crc','flags','build_id']


def decode_reply(data,op,sequence):
    if len(data)<REPLY.size:return None
    fields=REPLY.unpack_from(data)
    state=dict(zip(KEYS,fields[1:]))
    if fields[0]!=b'NCS1' or (state['version'],state['op'],state['sequence'])!=(1,op,sequence):return None
    if state['state']>2 or state['chunk']>176 or len(data)!=80+state['chunk']:
        raise ValueError('CoreMark reply length/state mismatch')
    if state['log_length']>=8192 or state['offset']+state['chunk']>state['log_length']:
        raise ValueError('CoreMark log range mismatch')
    state['performance_ticks']=(state.pop('perf_hi')<<32)|state.pop('perf_lo')
    state['validation_ticks']=(state.pop('validation_hi')<<32)|state.pop('validation_lo')
    state['data']=data[80:]
    return state


def parse_result(state,raw_log):
    if state['state']!=2 or state['flags'] or len(raw_log)!=state['log_length']:
        raise ValueError('CoreMark result is incomplete or the board log overflowed')
    if zlib.crc32(raw_log)!=state['log_crc']:
        raise ValueError('CoreMark log CRC mismatch')
    text=raw_log.decode('ascii')
    if text.count('=== PERFORMANCE ===')!=1 or text.count('=== VALIDATION ===')!=1:
        raise ValueError('Both performance and validation runs are required')
    perf,validation=text.split('=== VALIDATION ===')
    reports=[]
    for name,part,ticks,expected in [
        ('performance',perf,state['performance_ticks'],[0xe9f5,0xe714,0x1fd7,0x8e3a]),
        ('validation',validation,state['validation_ticks'],[0x18f2,0xe3c1,0x0747,0x8d84])]:
        def value(label,pattern=r'(\d+)'):
            found=re.findall(re.escape(label)+r'\s*:\s*'+pattern,part)
            if len(found)!=1:raise ValueError('Missing/duplicate '+name+' '+label)
            return found[0]
        iterations=int(value('Iterations'))
        crc=[int(value(label,r'0x([0-9a-fA-F]+)'),16) for label in ['seedcrc','[0]crclist','[0]crcmatrix','[0]crcstate']]
        seconds=ticks/state['timer_hz'] if state['timer_hz'] else 0
        # The experimental audit emits an explicit all-zero error bitmask.
        # Exempt only that exact successful field; real errors/nonzero masks still fail.
        has_error=any('ERROR' in line for line in part.splitlines() if line!='AUDIT_ERRORS=00000000')
        valid=(not has_error and part.count('Correct operation validated.')==1 and
               crc==expected and seconds>=10 and iterations>0 and int(value('CoreMark Size'))==666)
        # The original CoreMark text uses microseconds; retain full raw timer ticks.
        if state['timer_hz']!=100000000 or state['cpu_hz']!=100000000:
            raise ValueError('Unexpected board clock metadata')
        if int(value('Total ticks'))!=ticks//100:
            raise ValueError('CoreMark timer metadata and raw log disagree')
        reports.append(dict(name=name,valid=valid,iterations=iterations,seconds=seconds,
                            raw_timer_ticks=ticks,crc=[f'{c:04x}' for c in crc],
                            iterations_per_second=iterations/seconds if seconds else 0))
    valid=all(r['valid'] for r in reports)
    return dict(valid=valid,coremark=reports[0]['iterations_per_second'] if valid else None,
                coremark_per_mhz=reports[0]['iterations_per_second']/(state['cpu_hz']/1e6) if valid else None,
                cpu_mhz=state['cpu_hz']/1e6,timer_hz=state['timer_hz'],run_id=state['run_id'],
                build_id=f"{state['build_id']:08x}",runs=reports,raw_log=text,
                note='实板运行；非 EEMBC 认证成绩' if valid else '校验或运行时长不满足要求，不作为有效分数')


class CoreMarkClient:
    def __init__(self,endpoint,port=5001,timeout=.25):
        self.peer=(endpoint.board,port);self.timeout=timeout;self.sequence=secrets.randbits(32)
        self.socket=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        try:self.socket.bind((endpoint.local,0))
        except Exception:self.socket.close();raise

    def close(self):self.socket.close()

    def call(self,op,run_id=0,arg=0,retries=6):
        self.sequence=(self.sequence+1)&0xffffffff
        packet=REQUEST.pack(b'NCQ1',1,op,self.sequence,run_id,arg)
        for _ in range(retries):
            self.socket.sendto(packet,self.peer);deadline=time.monotonic()+self.timeout
            while time.monotonic()<deadline:
                self.socket.settimeout(max(.001,deadline-time.monotonic()))
                try:data,source=self.socket.recvfrom(2048)
                except socket.timeout:break
                if source!=self.peer:continue
                reply=decode_reply(data,op,self.sequence)
                if reply is None:continue
                if reply['error']:raise RuntimeError('CoreMark command rejected: '+str(reply['error']))
                if run_id and reply['run_id']!=run_id:raise RuntimeError('CoreMark run ID mismatch')
                return reply
        raise TimeoutError('CoreMark 应用未应答；计时期间暂不处理网络请求')

    def collect(self,state,progress=None):
        chunks=[];offset=0
        while offset<state['log_length']:
            part=self.call(3,state['run_id'],offset)
            if (part['offset']!=offset or not part['data'] or
                any(part[k]!=state[k] for k in ['log_length','log_crc','build_id','performance_ticks','validation_ticks'])):
                raise ValueError('CoreMark result changed while reading')
            chunks.append(part['data']);offset+=len(part['data'])
            if progress:progress(offset,state['log_length'])
        return parse_result(state,b''.join(chunks))

    def run(self,iterations=0,progress=None,timeout=300):
        if not 0<=iterations<=1000000:raise ValueError('iterations must be 0..1000000 (0=automatic)')
        self.call(1)  # Establish that the right application is running.
        run_id=secrets.randbits(32) or 1
        started=time.monotonic()
        try:self.call(2,run_id,iterations)
        except TimeoutError:pass  # START may have arrived; never start a new identity.
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            try:
                state=self.call(1,run_id,retries=2)
                if state['state']==2:
                    result=self.collect(state,progress)
                    result['host_elapsed_seconds']=time.monotonic()-started
                    return result
            except TimeoutError:pass
            time.sleep(.3)
        raise TimeoutError('CoreMark 超过等待期限；请查询并取回已完成结果，不要立即重复启动')

    def latest(self,progress=None):
        state=self.call(1)
        if state['state']!=2:raise RuntimeError('板卡尚无已完成的 CoreMark 结果')
        return self.collect(state,progress)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board',default='192.168.1.50');parser.add_argument('--bind',default='192.168.1.100')
    parser.add_argument('--iterations',type=int,default=0);parser.add_argument('--latest',action='store_true')
    parser.add_argument('--query',action='store_true');parser.add_argument('--output',type=Path)
    args=parser.parse_args();client=CoreMarkClient(Endpoint(args.board,args.bind))
    try:
        result=client.call(1) if args.query else client.latest() if args.latest else client.run(args.iterations)
        result.pop('data',None)
        if args.output:
            args.output.parent.mkdir(parents=True,exist_ok=True)
            args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
            if 'raw_log' in result:args.output.with_suffix('.txt').write_text(result['raw_log'],encoding='utf-8')
        print(json.dumps(result,ensure_ascii=False,indent=2))
    finally:client.close()


if __name__=='__main__':main()
