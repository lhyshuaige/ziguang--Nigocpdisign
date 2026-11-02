#include "ethernet.h"
#include <string.h>
enum { CONTROL=0x004,STATUS=0x008,PENDING=0x00c,MASK=0x010,
 MAC_LO=0x020,MAC_HI=0x024,IP=0x028,NETMASK=0x02c,GATEWAY=0x030,COMMIT=0x03c,
 RX_STATUS=0x100,RX_IP=0x104,RX_PORTS=0x108,RX_LEN=0x10c,RX_ACK=0x114,
 TX_LEN=0x140,TX_IP=0x144,TX_PORTS=0x148,TX_KICK=0x14c,TX_DATA=0x200,RX_DATA=0x300 };
static void fence_io(void) {
#if defined(__riscv)
 __asm__ volatile("fence iorw,iorw" ::: "memory");
#else
 __asm__ volatile("" ::: "memory");
#endif
}
static uint32_t rd(nigo_eth *e,unsigned r){uint32_t v=e->base[r/4];fence_io();return v;}
static void wr(nigo_eth *e,unsigned r,uint32_t v){fence_io();e->base[r/4]=v;fence_io();}
static uint32_t be32(const uint8_t *p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static void put_be32(uint8_t *p,uint32_t v){p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v;}
void nigo_eth_open(nigo_eth *e,uintptr_t base){memset(e,0,sizeof(*e));e->base=(volatile uint32_t *)base;}
int nigo_eth_ready(nigo_eth *e){return (rd(e,STATUS)&0x18)==0x18;}
int nigo_eth_configure(nigo_eth *e,uint64_t mac,uint32_t ip,uint32_t mask,uint32_t gateway,unsigned timeout){
 wr(e,CONTROL,0);wr(e,MAC_LO,(uint32_t)mac);wr(e,MAC_HI,(uint32_t)(mac>>32));
 wr(e,IP,ip);wr(e,NETMASK,mask);wr(e,GATEWAY,gateway);wr(e,COMMIT,1);
 /* Read ordering/fence ensures the commit write reaches AXI before polling. */
 while((rd(e,COMMIT)&1) && timeout)--timeout;
 if(!timeout)return -1;
 wr(e,PENDING,255);wr(e,MASK,255);wr(e,CONTROL,1);return 0;
}
int nigo_eth_service(nigo_eth *e,nigo_mode_fn apply,void *context){
 uint8_t command[16],ack[16];uint32_t value,seq,mode,status,source,ports;
 if(!(rd(e,RX_STATUS)&1))return 0;
 if(rd(e,TX_KICK)!=0)return 0; /* Keep command until ACK storage is available. */
 source=rd(e,RX_IP);ports=rd(e,RX_PORTS);
 if(rd(e,RX_LEN)!=16){wr(e,RX_ACK,1);return -2;}
 for(unsigned i=0;i<4;i++){
  value=rd(e,RX_DATA+4*i);for(unsigned j=0;j<4;j++)command[4*i+j]=(uint8_t)(value>>(8*j));
 }
 if(memcmp(command,"NGC1",4) || be32(command+12)!=0){wr(e,RX_ACK,1);return -2;}
 seq=be32(command+4);mode=be32(command+8);
 if(e->have_sequence && e->last_sequence==seq && e->last_source_ip==source && e->last_source_port==(ports>>16) && e->last_requested_mode==mode)status=e->last_status;
 else {
  status=mode>3?1:apply?apply(mode,context):2;
  if(status==0)e->active_mode=mode;
  e->last_sequence=seq;e->last_status=status;e->last_source_ip=source;e->last_source_port=ports>>16;e->last_requested_mode=mode;e->have_sequence=1;
 }
 memcpy(ack,"NGA1",4);put_be32(ack+4,seq);put_be32(ack+8,status);put_be32(ack+12,e->active_mode);
 for(unsigned i=0;i<4;i++){
  value=0;for(unsigned j=0;j<4;j++)value|=(uint32_t)ack[4*i+j]<<(8*j);wr(e,TX_DATA+4*i,value);
 }
 wr(e,TX_IP,source);wr(e,TX_PORTS,(uint32_t)5001<<16|(ports>>16));wr(e,TX_LEN,16);wr(e,TX_KICK,1);
 wr(e,RX_ACK,1);wr(e,PENDING,1);return 1;
}
