"""NGE1: CPU detection results, 32-byte big-endian header + up to 16 boxes.

Flags 1=measured detection, 2=CPU tracked estimate. Event bits: 1=face entered,
2=face left. A face event is not a full-body person detector or identity claim.
"""
import struct
RESULT=struct.Struct('!4sBBHIIIIHHHH')
BOX=struct.Struct('!HHHHHH')
def decode_result(data):
 if len(data)<RESULT.size:raise ValueError('short result')
 magic,version,kind,flags,fid,stamp,seq,duration,w,h,count,event=RESULT.unpack_from(data)
 if magic!=b'NGE1' or version!=1 or kind not in (1,2) or event&~3:raise ValueError('unsupported result')
 if kind==1 and flags not in (1,2):raise ValueError('unsupported result flags')
 if kind==2 and (not flags or count or event):raise ValueError('invalid error result')
 if (w,h)!=(320,240) or count>16 or len(data)!=RESULT.size+count*BOX.size:raise ValueError('result size')
 boxes=[]
 for i in range(count):
  track,score,x1,y1,x2,y2=BOX.unpack_from(data,RESULT.size+i*BOX.size)
  if score>32767 or not 0<=x1<x2<=w or not 0<=y1<y2<=h:raise ValueError('box range')
  boxes.append(dict(track_id=track,score=score/32767,x1=x1,y1=y1,x2=x2,y2=y2))
 return dict(frame_id=fid,timestamp=stamp,sequence=seq,duration_ms=duration,width=w,height=h,
             tracked=kind==1 and flags==2,event=event,boxes=boxes,error=flags if kind==2 else 0)
