"""NGV1 RGB565/Gray8 upload through the optional isolated RX demo firmware.

Default: one body packet at a time, waiting for hardware consumption progress.
A lost/reordered/duplicate body invalidates the entire frame; never retransmit
an individual body packet into an active frame. Only control RPCs are retried.
No JPEG/PNG is sent to hardware: optional Pillow conversion runs on the PC.
"""
import argparse,json,socket,struct,time,secrets
from pathlib import Path
HEADER=struct.Struct('!4sBBHIIIHHHHI')
REQUEST=struct.Struct('!4s7I')
ACK=struct.Struct('!4s15I')
def packets(body,width,height,rgb565,frame_id,chunk=1400):
    if not(1<=width<=640 and 1<=height<=480 and rgb565 in (0,1)):
        raise ValueError('supported: 1..640 x 1..480, format Gray8 or RGB565')
    if len(body)!=width*height*(1+rgb565) or not(1<=chunk<=1400) or (rgb565 and chunk%2):
        raise ValueError('body size/chunk alignment')
    for offset in range(0,len(body),chunk):
        part=body[offset:offset+chunk];last=int(offset+len(part)==len(body))
        yield HEADER.pack(b'NGV1',1,1,(rgb565<<8)|last,frame_id,offset,len(body),
                          width,height,len(part),0,0)+part
def unpack_ack(data,seq,op):
    if len(data)!=64:return None
    fields=ACK.unpack(data)
    if fields[0]!=b'NGS1' or fields[1:3]!=(seq,op):return None
    keys=['error','status','events','offset','frames_ok','frames_bad','packets_ok','packets_bad','frame_id','base','stride','size','format']
    out=dict(zip(keys,fields[3:]));out['error']=struct.unpack('!i',struct.pack('!I',out['error']))[0]
    return out
class ReceiverError(RuntimeError):
    def __init__(self,state):self.state=state;super().__init__('receiver command rejected: '+json.dumps(state))
class Control:
    def __init__(self,sock,peer,timeout=.3):self.sock=sock;self.peer=peer;self.seq=0;self.timeout=timeout
    def call(self,op,frame_id=0,width=0,height=0,rgb565=0):
        self.seq=(self.seq+1)&0xffffffff
        data=REQUEST.pack(b'NGR1',self.seq,op,frame_id,(width<<16)|height,rgb565,0,0)
        for _ in range(6):
            self.sock.sendto(data,(self.peer,5001));end=time.monotonic()+self.timeout
            while time.monotonic()<end:
                self.sock.settimeout(max(.001,end-time.monotonic()))
                try:reply,source=self.sock.recvfrom(2048)
                except socket.timeout:break
                if source!=(self.peer,5001):continue
                result=unpack_ack(reply,self.seq,op)
                if result is not None:
                    if result['error']:raise ReceiverError(result)
                    return result
        raise TimeoutError('No NGR1 response; the NEW receiver firmware/candidate must be loaded')
    def wait(self,predicate,timeout=2):
        end=time.monotonic()+timeout
        while time.monotonic()<end:
            state=self.call(2)
            if state['events']&14:raise RuntimeError('frame failed: '+json.dumps(state))
            if predicate(state):return state
            time.sleep(.001)
        raise TimeoutError('receiver progress timeout')
def upload(control,body,width,height,rgb565,chunk=1400,retries=1,hold=False):
    for attempt in range(retries+1):
        frame_id=secrets.randbits(32) or 1;armed=False
        try:
            control.call(1,frame_id,width,height,rgb565)
            armed=True
            control.wait(lambda p:bool(p['status']&1))
            offset=0;started=time.perf_counter()
            for packet in packets(body,width,height,rgb565,frame_id,chunk):
                control.sock.sendto(packet,(control.peer,5000));offset+=len(packet)-32
                control.wait(lambda p:p['offset']>=offset)
            # Progress != durable DDR completion. TAKE only a published frame.
            state=control.wait(lambda p:bool(p['status']&16) and not(p['status']&3))
            frame=control.call(3,frame_id)
            if frame['frame_id']!=frame_id or frame['size']!=((width<<16)|height) or frame['format']!=rgb565:
                raise RuntimeError('published descriptor mismatch')
            frame['seconds']=max(time.perf_counter()-started,1e-9);frame['payload_bytes']=len(body);frame['attempt']=attempt+1
            frame['application_MB_per_s']=len(body)/frame['seconds']/1e6
            if not hold:control.call(4,frame_id)
            return frame
        except (RuntimeError,TimeoutError) as error:
            # An explicitly rejected ARM owns no new frame. Never cancel some
            # other job just because the receiver reported BUSY.
            if not armed and isinstance(error,ReceiverError):raise
            state=control.call(2)
            if state['frame_id']!=frame_id:raise
            if state['status']&32:control.call(4,frame_id)
            elif state['status']&16:
                frame=control.call(3,frame_id)
                if frame['frame_id']!=frame_id:raise RuntimeError('cleanup descriptor mismatch')
                control.call(4,frame_id)
            # Cancel is drained, not a DMA reset. No new ARM until idle.
            control.call(5,frame_id);end=time.monotonic()+3
            while time.monotonic()<end:
                if not(control.call(2)['status']&3):break
                time.sleep(.01)
            else:raise RuntimeError('DDR did not drain; keep buffers reserved, do not force software reset')
            if attempt==retries:raise
def load_body(args):
    if args.raw:
        body=Path(args.raw).read_bytes()
    elif args.image:
        from PIL import Image
        image=Image.open(args.image).convert('RGB').resize((args.width,args.height),Image.Resampling.NEAREST)
        if args.rgb565:
            body=b''.join(struct.pack('<H',((r>>3)<<11)|((g>>2)<<5)|(b>>3)) for r,g,b in image.getdata())
        else:body=image.convert('L').tobytes()
    else:
        if args.rgb565:
            body=b''.join(struct.pack('<H',((x*31//args.width)<<11)|((y*63//args.height)<<5)|((x+y)%32))
                          for y in range(args.height) for x in range(args.width))
        else:body=bytes((x*3+y*5)&255 for y in range(args.height) for x in range(args.width))
    if len(body)!=args.width*args.height*(1+args.rgb565):raise ValueError('raw input byte count does not match dimensions/format')
    return body
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--peer',default='192.168.1.50');ap.add_argument('--bind',default='192.168.1.100')
    ap.add_argument('--width',type=int,default=320);ap.add_argument('--height',type=int,default=240);ap.add_argument('--gray',action='store_true')
    g=ap.add_mutually_exclusive_group();g.add_argument('--raw');g.add_argument('--image')
    ap.add_argument('--chunk',type=int,default=1400);ap.add_argument('--retries',type=int,default=1)
    ap.add_argument('--hold',action='store_true',help='leave CPU-owned READ buffer for another consumer; release it through CPU before another upload')
    ap.add_argument('--emit',type=Path,help='offline packet vector file; do not send network traffic')
    args=ap.parse_args();args.rgb565=0 if args.gray else 1;body=load_body(args)
    # Validate before ARM; malformed host input must never occupy a DMA slot.
    vectors=list(packets(body,args.width,args.height,args.rgb565,1,args.chunk))
    if args.emit:
        args.emit.parent.mkdir(parents=True,exist_ok=True)
        args.emit.write_bytes(b''.join(struct.pack('<I',len(p))+p for p in vectors))
        print(json.dumps(dict(packets=len(vectors),body_bytes=len(body),output=str(args.emit))));return
    peer=socket.gethostbyname(args.peer)
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
        sock.bind((args.bind,0));print(json.dumps(upload(Control(sock,peer),body,args.width,args.height,args.rgb565,args.chunk,args.retries,args.hold),indent=2))
if __name__=='__main__':main()
