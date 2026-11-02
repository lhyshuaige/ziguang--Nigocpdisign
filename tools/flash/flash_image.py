"""Offline NGF1 pack/inspect. Does not connect to or erase hardware.
Bitstream archive != an FPGA configuration-programmer image.
"""
import argparse,json,struct,zlib
from pathlib import Path
HEADER=256;SLOT_SIZE=0x400000;LOAD=0x82000000;COMMIT=0xc04d17ed
def pack(payload,kind,generation=1,entry=LOAD):
    if kind not in (1,2) or len(payload)<4 or len(payload)>SLOT_SIZE-HEADER:raise ValueError('invalid size/kind')
    if kind==1 and (len(payload)>0x200000 or entry<LOAD or entry>LOAD+len(payload)-4 or entry%4):raise ValueError('application placement')
    if kind==2:entry=0
    first=struct.pack('>8I',0x4e474631,1,kind,generation&0xffffffff,len(payload),zlib.crc32(payload),LOAD if kind==1 else 0,entry)
    h=first+struct.pack('>I',zlib.crc32(first))+b'\xff'*(252-36)+struct.pack('>I',COMMIT)
    return h+payload+b'\xff'*((-len(payload))%4)
def inspect(blob):
    if len(blob)<HEADER:raise ValueError('short image')
    magic,version,kind,generation,size,crc,load,entry,hcrc=struct.unpack_from('>9I',blob)
    if magic!=0x4e474631 or version!=1 or kind not in (1,2) or size<4 or size>SLOT_SIZE-HEADER:raise ValueError('header')
    if struct.unpack_from('>I',blob,252)[0]!=COMMIT or blob[36:252]!=b'\xff'*216 or zlib.crc32(blob[:32])!=hcrc:raise ValueError('uncommitted/header CRC')
    if kind==1 and (size>0x200000 or load!=LOAD or entry<LOAD or entry>LOAD+size-4 or entry%4):raise ValueError('application placement')
    if kind==2 and (load or entry):raise ValueError('archive is not executable')
    if len(blob)<HEADER+size or zlib.crc32(blob[HEADER:HEADER+size])!=crc:raise ValueError('payload CRC')
    return dict(kind=kind,generation=generation,size=size,crc=hex(crc),load=hex(load),entry=hex(entry))
def main():
    a=argparse.ArgumentParser(description=__doc__);a.add_argument('input',type=Path);a.add_argument('--output',type=Path)
    a.add_argument('--kind',choices=['application','bitstream'],default='application');a.add_argument('--generation',type=int,default=1)
    a.add_argument('--entry',type=lambda x:int(x,0),default=LOAD);a.add_argument('--ngb',action='store_true',help='validate and strip existing NGB1 container')
    args=a.parse_args();blob=args.input.read_bytes()
    if args.output:
        if args.ngb:
            if len(blob)<32:raise ValueError('short NGB1')
            magic,version,load,entry,size,crc,flags,reserved=struct.unpack_from('>8I',blob)
            if (magic,version,load,flags,reserved)!=(0x4e474231,1,LOAD,0,0) or len(blob)!=32+size or zlib.crc32(blob[32:])!=crc:raise ValueError('invalid NGB1')
            args.entry=entry;blob=blob[32:]
        blob=pack(blob,1 if args.kind=='application' else 2,args.generation,args.entry)
        args.output.write_bytes(blob)
    print(json.dumps(inspect(blob),indent=2))
if __name__=='__main__':main()
