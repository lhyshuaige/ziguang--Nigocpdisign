#include "mode.h"
#include "ethernet.h"
#include "build_info.h"
#define ETH 0x10020000u
static mode_state modes;
static uint32_t rd(uint32_t a){uint32_t v=*(volatile uint32_t *)(uintptr_t)a;__asm__ volatile("fence iorw,iorw":::"memory");return v;}
static void wr(uint32_t a,uint32_t v){__asm__ volatile("fence iorw,iorw":::"memory");*(volatile uint32_t *)(uintptr_t)a=v;__asm__ volatile("fence iorw,iorw":::"memory");}
int runtime_pending(void){return modes.active!=modes.target;}
int runtime_application_rx_ready(void){return (rd(ETH+0x100)&1)&&rd(ETH+0x300)!=0x31514d4eu;}
uint32_t runtime_peer(void){return modes.peer?modes.peer:0xc0a80164u;}
void runtime_mode_changed(uint32_t mode){(void)mode;} /* stable simulation symbol */
int runtime_poll(int safe,uint32_t busy,uint32_t flags){
 modes.busy=busy|(rd(ETH+0x14c)?MODE_BUSY_TX:0);modes.flags=flags;
 if((rd(ETH+8)&0x18)==0x18&&(rd(ETH+0x100)&1)&&!rd(ETH+0x14c)&&rd(ETH+0x300)==0x31514d4eu){
  uint8_t p[32],reply[56];size_t n=0;uint32_t peer=rd(ETH+0x104),port=rd(ETH+0x108)>>16;
  if(rd(ETH+0x10c)==32){
   for(unsigned i=0;i<32;i+=4){uint32_t w=rd(ETH+0x300+i);for(unsigned b=0;b<4;b++)p[i+b]=(uint8_t)(w>>(8*b));}
   n=mode_request(&modes,p,32,peer,(uint16_t)port,reply);
  }
  wr(ETH+0x114,1);wr(ETH+0xc,1);
  if(n){for(unsigned i=0;i<n;i+=4){uint32_t w=0;for(unsigned b=0;b<4;b++)w|=(uint32_t)reply[i+b]<<(8*b);wr(ETH+0x200+i,w);}
   wr(ETH+0x144,peer);wr(ETH+0x148,5001u<<16|port);wr(ETH+0x140,(uint32_t)n);wr(ETH+0x14c,1);}
 }
 if(runtime_pending()&&(rd(ETH+0x100)&1)&&rd(ETH+0x300)!=0x31514d4eu){wr(ETH+0x114,1);wr(ETH+0xc,1);}
 /* Accepting a request alone is not completion. The dispatcher changes the
  * reported active mode only after the application returns with DMA drained. */
 return runtime_pending()&&safe&&!rd(ETH+0x14c);
}
void nigo_application_main(void){
 nigo_eth eth;nigo_eth_open(&eth,ETH);modes.build=RUNTIME_BUILD_ID;
 if(nigo_eth_configure(&eth,UINT64_C(0x020000000032),0xc0a80132u,0xffffff00u,0xc0a80101u,1000000u)){
  wr(0x10000000,0xe1);for(;;){} }
 for(;;){
  switch(modes.active){
   case MODE_RX:runtime_receiver();break;
   case MODE_AI:runtime_face();break;
   case MODE_COREMARK:runtime_coremark();break;
   case MODE_GAME:runtime_game();break;
   default:
    while(!runtime_poll(1,0,0)){
     wr(0x10000000,modes.active==MODE_KEYS?(rd(0x10000004)&15):0x20);
     if(runtime_application_rx_ready()){wr(ETH+0x114,1);wr(ETH+0xc,1);}
    }
  }
  if(mode_commit(&modes,1,!rd(ETH+0x14c)))runtime_mode_changed(modes.active);
 }
}
