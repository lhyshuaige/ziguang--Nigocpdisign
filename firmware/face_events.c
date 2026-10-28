#include "face_events.h"
#include <string.h>
static float minf(float a,float b){return a<b?a:b;}
static float maxf(float a,float b){return a>b?a:b;}
static float iou(const uf_box *a,const uf_box *b){
 float w=maxf(0,minf(a->x2,b->x2)-maxf(a->x1,b->x1));
 float h=maxf(0,minf(a->y2,b->y2)-maxf(a->y1,b->y1));
 float inter=w*h;return inter/((a->x2-a->x1)*(a->y2-a->y1)+(b->x2-b->x1)*(b->y2-b->y1)-inter+1e-5f);
}
unsigned face_events_update(face_events *s,uf_box *boxes,unsigned count){
 if(count>FACE_MAX)count=FACE_MAX;
 uint16_t used=0;
 for(unsigned i=0;i<count;i++){
  float best=.2f;int at=-1;
  for(unsigned j=0;j<s->count;j++)if(!(used&(1u<<j))){float v=iou(boxes+i,s->previous+j);if(v>best){best=v;at=(int)j;}}
  if(at>=0){boxes[i].track_id=s->previous[at].track_id;used|=(uint16_t)(1u<<at);}
  else{if(++s->next_id==0)++s->next_id;boxes[i].track_id=s->next_id;}
 }
 memcpy(s->previous,boxes,count*sizeof(*boxes));s->count=count;
 unsigned event=0;
 if(count){s->misses=0;if(s->hits<FACE_ENTER_HITS)s->hits++;if(!s->present&&s->hits>=FACE_ENTER_HITS){s->present=1;event=1;}}
 else{s->hits=0;if(s->misses<FACE_LEAVE_MISSES)s->misses++;if(s->present&&s->misses>=FACE_LEAVE_MISSES){s->present=0;event=2;}}
 return event;
}
static void put16(uint8_t *p,unsigned v){p[0]=(uint8_t)(v>>8);p[1]=(uint8_t)v;}
static void put32(uint8_t *p,uint32_t v){p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v;}
static unsigned pixel(float value,unsigned size){float v=value*size+.5f;return v<0?0:v>size?size:(unsigned)v;}
size_t face_result_encode(uint8_t out[224],uint32_t frame,uint32_t stamp,uint32_t seq,uint32_t duration,
 const uf_box *boxes,unsigned count,unsigned event,unsigned error){
 if(count>16)count=16;
 if(error){count=0;event=0;}
 memset(out,0,32);memcpy(out,"NGE1",4);out[4]=1;out[5]=(uint8_t)(error?2:1);put16(out+6,error?error:1);
 put32(out+8,frame);put32(out+12,stamp);put32(out+16,seq);put32(out+20,duration);put16(out+24,320);put16(out+26,240);put16(out+30,event);
 unsigned emitted=0;
 for(unsigned i=0;i<count;i++){
  const uf_box *b=boxes+i;unsigned x1=pixel(b->x1,320),y1=pixel(b->y1,240),x2=pixel(b->x2,320),y2=pixel(b->y2,240);
  if(x1>=x2||y1>=y2)continue;
  uint8_t *p=out+32+emitted*12;put16(p,b->track_id);put16(p+2,pixel(b->score,32767));
  put16(p+4,x1);put16(p+6,y1);put16(p+8,x2);put16(p+10,y2);emitted++;
 }
 put16(out+28,emitted);return 32+emitted*12;
}
