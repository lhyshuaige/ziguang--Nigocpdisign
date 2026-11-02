"""Upload and run an RV32 binary linked at 0x82000000 through the ROM loader."""
import argparse
import secrets
import socket
import struct
import time
import zlib
from pathlib import Path

IMAGE=struct.Struct('!4s7I')
UPLOAD=struct.Struct('!4sBBH6I')
ACK=struct.Struct('!4sBBH4I')
CONTROL=struct.Struct('!4s5I')
REPLY=struct.Struct('!4s7I')
LOAD=0x82000000
LIMIT=2*1024*1024

def pack_image(binary,entry=LOAD):
    if binary.startswith(b'\x7fELF'):
        raise ValueError('Use objcopy -O binary; ELF is not a raw executable image')
    if not 4<=len(binary)<=LIMIT or entry&3 or not LOAD<=entry<=LOAD+len(binary)-4:
        raise ValueError('Program must fit 2 MiB at 0x82000000 with an aligned entry inside the image')
    return IMAGE.pack(b'NGB1',1,LOAD,entry,len(binary),zlib.crc32(binary),0,0)+binary

def validate_image(blob):
    if len(blob)<IMAGE.size:
        raise ValueError('Truncated NGB image')
    magic,version,load,entry,size,crc,flags,reserved=IMAGE.unpack_from(blob)
    if (magic,version,load,flags,reserved)!=(b'NGB1',1,LOAD,0,0) or blob!=pack_image(blob[IMAGE.size:],entry):
        raise ValueError('Invalid NGB header, payload size or CRC')
    return entry,crc

class ProgramClient:
    def __init__(self,board,port=5001,timeout=.1,retries=30,bind=None):
        self.peer=(socket.gethostbyname(board),port)
        self.socket=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        try:
            if bind is not None:self.socket.bind((bind,0))
        except Exception:
            self.socket.close();raise
        self.timeout=timeout;self.retries=retries;self.sequence=secrets.randbits(32)
        self.session=secrets.randbits(32) or 1
    def close(self):
        self.socket.close()
    def _sequence(self):
        self.sequence=(self.sequence+1)&0xffffffff
        return self.sequence
    def _exchange(self,packet,decode):
        for _ in range(self.retries):
            self.socket.sendto(packet,self.peer);deadline=time.monotonic()+self.timeout
            while time.monotonic()<deadline:
                self.socket.settimeout(max(.001,deadline-time.monotonic()))
                try:data,peer=self.socket.recvfrom(2048)
                except socket.timeout:break
                if peer!=self.peer:continue
                result=decode(data)
                if result is not None:return result
        raise TimeoutError('No matching bootloader ACK; execution state is unconfirmed. Reset before retrying if execution was requested.')
    def upload(self,blob,progress=None):
        entry,payload_crc=validate_image(blob)
        total=len(blob);crc=zlib.crc32(blob)
        def send(op,offset,body=b''):
            seq=self._sequence()
            packet=UPLOAD.pack(b'NGU1',1,op,3,self.session,seq,total,offset,crc,0)+body
            expected=offset+len(body) if op==2 else total if op==3 else 0
            def decode(data):
                if len(data)!=ACK.size:return None
                magic,version,ackop,status,session,sequence,at,checksum=ACK.unpack(data)
                if (magic,version,ackop,session,sequence)!=(b'NGK1',1,op,self.session,seq):return None
                if status:raise RuntimeError(f'Program download rejected: status={status}, offset={at}')
                if at!=expected or checksum!=crc:raise RuntimeError('Bootloader ACK offset/CRC mismatch')
                return True
            self._exchange(packet,decode)
        send(1,0)
        if progress:progress(0,total)
        for offset in range(0,total,224):
            send(2,offset,blob[offset:offset+224])
            if progress:progress(min(offset+224,total),total)
        send(3,total)
        return entry,payload_crc
    def control(self,op,entry=None,crc=None):
        seq=self._sequence()
        packet=CONTROL.pack(b'NGBX',1,op,self.session,seq,0)
        def decode(data):
            if len(data)!=REPLY.size:return None
            magic,version,ackop,status,session,sequence,at,checksum=REPLY.unpack(data)
            if (magic,version,ackop,session,sequence)!=(b'NGBR',1,op,self.session,seq):return None
            if status:raise RuntimeError(f'Boot control rejected: status={status}')
            if entry is not None and (at,checksum)!=(entry,crc):raise RuntimeError('Boot control image mismatch')
            return dict(entry=at,crc=checksum)
        return self._exchange(packet,decode)
    def download(self,blob,progress=None):
        entry,crc=self.upload(blob,progress)
        self.control(2,entry,crc)
        return entry

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board',help='Board IPv4/name; omitted when only packaging')
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--bin',type=Path,help='Raw RV32 image linked at 0x82000000')
    group.add_argument('--program',type=Path,help='Packaged .ngb image')
    parser.add_argument('--entry',type=lambda s:int(s,0),default=LOAD)
    parser.add_argument('--output',type=Path,help='Write packaged .ngb image')
    parser.add_argument('--port',type=int,default=5001)
    args=parser.parse_args()
    blob=pack_image(args.bin.read_bytes(),args.entry) if args.bin else args.program.read_bytes()
    entry,_=validate_image(blob)
    if args.output:args.output.write_bytes(blob);print(f'Packaged {len(blob)} bytes: {args.output}')
    if not args.board:
        if not args.output:parser.error('Specify --board or --output')
        return
    client=ProgramClient(args.board,args.port)
    try:
        client.download(blob)
        print(f'Program committed; execute acknowledged at 0x{entry:08x}. Application starts after the 300 ms retry window.')
    finally:client.close()

if __name__=='__main__':main()
