#include "arcade.h"
#include "protocol.h"
#include "ethernet.h"
#define ETH 0x10020000u
#define IO(a) (*(volatile uint32_t *)(uintptr_t)(a))
static Arcade arcade;static ArcadeStream stream;static nigo_eth ethernet;
static void fence_io(void){__asm__ volatile("fence iorw,iorw" ::: "memory");}
static uint32_t rd(uint32_t a){uint32_t v=IO(a);fence_io();return v;}
static void wr(uint32_t a,uint32_t v){fence_io();IO(a)=v;fence_io();}
static uint64_t ticks(void){uint32_t hi,lo,next;do{hi=rd(0x1000000c);lo=rd(0x10000008);next=rd(0x1000000c);}while(hi!=next);return ((uint64_t)hi<<32)|lo;}
static void send(const uint8_t *p,size_t n,uint32_t peer,uint16_t port,uint16_t source){
 for(size_t i=0;i<n;i+=4){uint32_t word=0;for(unsigned b=0;b<4&&i+b<n;b++)word|=(uint32_t)p[i+b]<<(b*8);wr(ETH+0x200+(uint32_t)i,word);}
 wr(ETH+0x144,peer);wr(ETH+0x148,(uint32_t)source<<16|port);wr(ETH+0x140,(uint32_t)n);wr(ETH+0x14c,1);
}
void nigo_application_main(void){
 uint8_t *pixels=(uint8_t *)(uintptr_t)0x83000000;stream.encoded=(uint8_t *)(uintptr_t)0x83100000;
 arcade_init(&arcade,0x4e49474f);nigo_eth_open(&ethernet,ETH);
 if(nigo_eth_configure(&ethernet,UINT64_C(0x020000000032),0xc0a80132,0xffffff00,0xc0a80101,1000000)){wr(0x10000000,0xe1);for(;;){}}
 uint64_t next_tick=ticks(),next_frame=next_tick;
 for(;;){
  uint64_t now=ticks();uint32_t ms=(uint32_t)(now/100000u);int ready=nigo_eth_ready(&ethernet);
  if(now>=next_tick){arcade_step(&arcade,rd(0x10000004));next_tick+=100000000u/60;if(now>next_tick&&now-next_tick>100000000u/10)next_tick=now+100000000u/60;wr(0x10000000,0x10u|(uint32_t)arcade.mode);}
  if(!ready||((uint32_t)(ms-stream.last_seen)>3000)){stream.peer=0;stream.offset=stream.total;}
  if(ready&&!rd(ETH+0x14c)){
   if(rd(ETH+0x100)&1){
    uint32_t n=rd(ETH+0x10c),peer=rd(ETH+0x104),port=rd(ETH+0x108)>>16;uint8_t request[24],reply[64];size_t bytes=0;
    if(n==24){for(unsigned i=0;i<24;i+=4){uint32_t w=rd(ETH+0x300+i);for(unsigned b=0;b<4;b++)request[i+b]=(uint8_t)(w>>(b*8));}
     bytes=arcade_request(&stream,request,n,peer,(uint16_t)port,ms,(uint32_t)arcade.mode,(uint32_t)arcade.selected,arcade.keys,arcade.score,reply);
    }
    wr(ETH+0x114,1);wr(ETH+0xc,1);if(bytes)send(reply,bytes,peer,(uint16_t)port,5001);
   }else if(stream.offset<stream.total&&stream.peer){uint8_t packet[256];size_t n=arcade_packet(&stream,packet);if(n)send(packet,n,stream.peer,(uint16_t)stream.port,5003);}
  }
  if(stream.peer&&stream.offset==stream.total&&now>=next_frame){
   arcade_render(&arcade,pixels);stream.total=arcade_encode(pixels,stream.encoded,ARCADE_RLE_MAX);stream.crc=arcade_crc(stream.encoded,stream.total);stream.frame++;stream.offset=0;
   next_frame=now+100000000u/30;
  }
 }
}
