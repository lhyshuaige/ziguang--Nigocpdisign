#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
static uint32_t fake_read(uint32_t);
static void fake_write(uint32_t,uint32_t);
#include "native_main.inc"
static unsigned full,tx_busy,acks,sends;
static uint8_t packet[32];
static uint32_t fake_read(uint32_t a){
 unsigned off=a-ETH;
 if(off==8)return 0x18;
 if(off==0x100)return full;
 if(off==0x104)return 0xc0a80164;
 if(off==0x108)return 40000u<<16;
 if(off==0x10c)return 32;
 if(off==0x14c)return tx_busy;
 if(off>=0x300&&off<0x320){unsigned i=off-0x300;return (uint32_t)packet[i]|(uint32_t)packet[i+1]<<8|(uint32_t)packet[i+2]<<16|(uint32_t)packet[i+3]<<24;}
 return 0;
}
static void fake_write(uint32_t a,uint32_t v){
 if(a==ETH+0x114&&v){full=0;acks++;}
 if(a==ETH+0x14c&&v){tx_busy=1;sends++;}
}
void nigo_eth_open(nigo_eth *e,uintptr_t a){(void)e;(void)a;}
int nigo_eth_configure(nigo_eth *e,uint64_t m,uint32_t i,uint32_t k,uint32_t g,unsigned t){(void)e;(void)m;(void)i;(void)k;(void)g;(void)t;return 0;}
void runtime_game(void){} void runtime_face(void){}
void runtime_coremark(void){} void runtime_receiver(void){}
static void request(unsigned op,unsigned target,unsigned seq){
 memset(packet,0,sizeof packet);memcpy(packet,"NMQ1",4);
 packet[7]=1;packet[11]=(uint8_t)op;packet[15]=19;
 packet[19]=(uint8_t)seq;packet[23]=(uint8_t)target;packet[27]=(uint8_t)modes.generation;full=1;
}
int main(void){
 /* A management request arrives AFTER the outer application poll. The
  * consumer must leave it for the next poll rather than ACK/drop it. */
 assert(!runtime_poll(1,0,0));request(2,MODE_GAME,1);
 assert(!runtime_application_rx_ready());assert(full&&acks==0);
 assert(!runtime_application_rx_ready());assert(!runtime_poll(1,0,0));
 assert(acks==1&&sends==1&&modes.target==MODE_GAME&&modes.active==MODE_IDLE);
 assert(!mode_commit(&modes,1,!tx_busy));tx_busy=0;
 assert(runtime_poll(1,0,0));assert(mode_commit(&modes,1,1));
 /* TX backpressure must never let an application steal a pending query. */
 request(1,0,2);tx_busy=1;
 assert(!runtime_poll(1,0,0));assert(!runtime_application_rx_ready());assert(full&&acks==1);
 tx_busy=0;assert(!runtime_poll(1,0,0));assert(acks==2&&sends==2);
 /* Ordinary application traffic remains available until its own consumer
  * takes it, except while a mode transition is draining. */
 tx_busy=0;full=1;memcpy(packet,"NGGQ",4);
 assert(!runtime_poll(1,0,0));assert(runtime_application_rx_ready());assert(full&&acks==2);
 modes.target=MODE_RX;assert(!runtime_poll(0,MODE_BUSY_RX,0));
 assert(!full&&acks==3&&!runtime_application_rx_ready());
 assert(!mode_commit(&modes,0,1));assert(runtime_poll(1,0,0));
 assert(mode_commit(&modes,1,1)&&modes.active==MODE_RX);
 puts("Late-arrival protocol routing and TX/drain barriers PASS");return 0;
}
