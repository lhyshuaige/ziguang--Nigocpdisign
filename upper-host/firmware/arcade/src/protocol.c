#include "protocol.h"
#include <string.h>
static uint32_t get(const uint8_t *p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static void put(uint8_t *p,uint32_t v){p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v;}
size_t arcade_request(ArcadeStream *s,const uint8_t *p,size_t n,uint32_t peer,uint16_t port,uint32_t now,
                     uint32_t mode,uint32_t selected,uint32_t keys,uint32_t score,uint8_t reply[64]){
 if(n!=24||memcmp(p,"NGGQ",4))return 0;
 uint32_t op=get(p+8),session=get(p+16),error=0;
 if(get(p+4)!=1||get(p+20)||!session||op<1||op>3)error=1;
 else if(op==1){
  if(s->peer&&(s->peer!=peer||s->port!=port||s->session!=session)&&(uint32_t)(now-s->last_seen)<3000)error=2;
  else{if(s->peer!=peer||s->port!=port||s->session!=session){s->offset=s->total;s->frame=0;}s->peer=peer;s->port=port;s->session=session;s->last_seen=now;}
 }else if(op==2){if(s->peer!=peer||s->port!=port||s->session!=session)error=3;else{s->peer=0;s->offset=s->total;}}
 memcpy(reply,"NGGS",4);uint32_t values[15]={1,op,get(p+12),session,error,mode,selected,keys,score,s->frame,320,240,60,30,0x41524331};
 for(unsigned i=0;i<15;i++)put(reply+4+i*4,values[i]);return 64;
}
size_t arcade_packet(ArcadeStream *s,uint8_t packet[256]){
 if(!s->peer||s->offset>=s->total)return 0;uint32_t n=s->total-s->offset;if(n>224)n=224;
 memcpy(packet,"NGGF",4);uint32_t fields[7]={1,s->session,s->frame,s->total,s->offset,s->crc,(320u<<16)|240u};
 for(unsigned i=0;i<7;i++)put(packet+4+i*4,fields[i]);memcpy(packet+32,s->encoded+s->offset,n);s->offset+=n;return n+32;
}
