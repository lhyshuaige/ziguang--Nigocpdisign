"""Reliable bounded uploads through the existing 256-byte CPU mailbox.

python upload.py --board 192.168.1.50 --model model.ngm --image face.jpg
Pillow is needed only for image loading/resizing. Inference runs on the FPGA.
"""
import argparse,socket,struct,time,zlib
from pathlib import Path
HEADER=struct.Struct('!4sBBHIIIIII')
ACK=struct.Struct('!4sBBHIIII')
class BusyError(RuntimeError):pass
class Uploader:
    def __init__(self,board,port=5001,timeout=.25,retries=12):
        self.peer=(socket.gethostbyname(board),port);self.timeout=timeout;self.retries=retries
        self.socket=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);self.socket.settimeout(timeout)
        self.sequence=0
    def close(self):self.socket.close()
    def exchange(self,packet,op,session,sequence):
        for _ in range(self.retries):
            self.socket.sendto(packet,self.peer);deadline=time.monotonic()+self.timeout
            while time.monotonic()<deadline:
                self.socket.settimeout(max(.001,deadline-time.monotonic()))
                try:data,peer=self.socket.recvfrom(2048)
                except socket.timeout:break
                if peer!=self.peer or len(data)!=ACK.size:continue
                magic,version,ackop,status,identity,seq,offset,crc=ACK.unpack(data)
                if magic!=b'NGK1' or version!=1 or ackop!=op or identity!=session or seq!=sequence:continue
                if status==2:raise BusyError('board busy; skip this detection frame')
                if status:raise RuntimeError(f'upload rejected: status={status}, next_offset={offset}')
                return offset,crc
        raise TimeoutError('board acknowledgement timed out; upload state is unconfirmed')
    def upload(self,blob,kind,session,timestamp=None):
        if kind==2 and len(blob)!=320*240*3:raise ValueError('frame must be 320x240 RGB888')
        if kind not in (1,2) or not 0<len(blob)<=2*1024*1024:raise ValueError('blob size/kind')
        total=len(blob);crc=zlib.crc32(blob);stamp=int(time.time()*1000)&0xffffffff if timestamp is None else timestamp
        def send(op,offset,body=b''):
            self.sequence=(self.sequence+1)&0xffffffff
            packet=HEADER.pack(b'NGU1',1,op,kind,session,self.sequence,total,offset,crc,stamp)+body
            at,ackcrc=self.exchange(packet,op,session,self.sequence)
            if ackcrc!=crc:raise RuntimeError('ACK belongs to a different blob')
            expected=offset+len(body) if op==2 else total if op==3 else 0
            if at!=expected:raise RuntimeError(f'ACK offset {at}, expected {expected}')
        send(1,0)
        for offset in range(0,total,224):send(2,offset,blob[offset:offset+224])
        send(3,total)
        return session
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--board',required=True);ap.add_argument('--model',type=Path)
    ap.add_argument('--image',type=Path);ap.add_argument('--frame-id',type=int,default=1);a=ap.parse_args()
    client=Uploader(a.board)
    try:
        if a.model:client.upload(a.model.read_bytes(),1,0x4d4f444c);print('model upload committed')
        if a.image:
            from PIL import Image
            rgb=Image.open(a.image).convert('RGB').resize((320,240),Image.Resampling.BILINEAR)
            start=time.monotonic();client.upload(rgb.tobytes(),2,a.frame_id)
            print(f'frame {a.frame_id} committed in {time.monotonic()-start:.3f}s; await UDP result on port 5002')
    finally:client.close()
if __name__=='__main__':main()
