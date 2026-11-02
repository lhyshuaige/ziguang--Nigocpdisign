#include <stdint.h>
#include <stddef.h>
#include "coremark.h"
#include "ethernet.h"
#include "reference.h"

#define ETH 0x10020000u
#define AI 0x10010000u
#define DMA 0x10011000u
#define RX 0x10021800u
#define TX 0x10021000u
#define HZ 100000000u
#define RFIELDS 13u
#define HEADER 14u
#define FIELDS (HEADER+RFIELDS*2u)
uint32_t saved_sp,saved_ra;
static uint32_t records[2][RFIELDS],phase,completed,state,identity,requested;
static uint32_t audit_errors,network_before,network_after,boot_sample;
static nigo_eth ethernet;
extern unsigned char __bss_start[],_end[];
extern volatile ee_s32 seed1_volatile,seed2_volatile,seed3_volatile,seed4_volatile,seed5_volatile;
extern void replay_invoke(void);
extern void *memcpy(void *,const void *,size_t);
extern void *memset(void *,int,size_t);

static uint32_t rd(uint32_t addr){uint32_t v=*(volatile uint32_t *)(uintptr_t)addr;__asm__ volatile("fence iorw,iorw":::"memory");return v;}
static void wr(uint32_t addr,uint32_t value){__asm__ volatile("fence iorw,iorw":::"memory");*(volatile uint32_t *)(uintptr_t)addr=value;__asm__ volatile("fence iorw,iorw":::"memory");}
static uint32_t now(void){return rd(0x10000008u);} /* Never touches the profiled CLINT alias. */
static uint32_t be(const uint8_t *p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static void put(uint8_t *p,uint32_t v){p[0]=v>>24;p[1]=v>>16;p[2]=v>>8;p[3]=v;}
int memcmp(const void *a,const void *b,size_t n){const unsigned char *x=a,*y=b;while(n--){if(*x!=*y)return *x-*y;++x;++y;}return 0;}
static uint32_t crc32(const uint8_t *p,unsigned n){uint32_t v=~0u;while(n--){v^=*p++;for(unsigned b=0;b<8;b++)v=(v>>1)^(0xedb88320u&(0u-(v&1)));}return ~v;}

/* Only portable_fini is redirected here, after stop_time and all original
 * checking/printing. No timed algorithm or timing instruction is replaced. */
void replay_capture(core_portable *port){
 core_results *r=(core_results *)((unsigned char *)port - offsetof(core_results,port));
 uint32_t *out=records[phase];
 ee_u16 seed=0;seed=crc16(r->seed1,seed);seed=crc16(r->seed2,seed);seed=crc16(r->seed3,seed);seed=crc16(r->size,seed);
 out[0]=r->iterations;out[1]=get_time();out[2]=r->size;out[3]=seed;
 out[4]=r->crclist;out[5]=r->crcmatrix;out[6]=r->crcstate;out[7]=r->crc;
 out[8]=(uint32_t)(int32_t)r->err;out[9]=(uint16_t)r->seed1;out[10]=(uint16_t)r->seed2;
 out[11]=(uint32_t)(uintptr_t)r->memblock[0];out[12]=(uint32_t)(uintptr_t)r;
 completed|=1u<<phase;port->portable_id=0;
 ee_printf("PORT_DONE\n");
}

static void run_one(uint32_t iterations,uint32_t validation){
 phase=validation;
 memcpy((void *)(uintptr_t)REFERENCE_DATA_ADDRESS,reference_data,sizeof reference_data);
 memset(__bss_start,0,(size_t)(_end-__bss_start));
 seed1_volatile=validation?0x3415:0;seed2_volatile=seed1_volatile;seed3_volatile=0x66;
 seed4_volatile=(ee_s32)iterations;seed5_volatile=0;
 replay_invoke();
}
static int idle(void){return !(rd(AI+0x84)&1)&&!(rd(DMA+4)&1)&&!(rd(RX+4)&0xb3)&&!(rd(RX+0x40)&15)&&!(rd(TX+4)&9)&&!rd(ETH+0x14c);}
static int wait_enable(unsigned enabled){uint32_t t=now();do{if((rd(ETH+4)&1)==enabled&&!!(rd(ETH+8)&16)==!!enabled)return 1;}while((uint32_t)(now()-t)<HZ);return 0;}
static void suite(void){
 uint32_t before[5],after[5];audit_errors=0;boot_sample=0;completed=0;
 if(!idle()){audit_errors|=1;state=2;return;}
 uint32_t saved=rd(ETH+4)&1;
 wr(ETH+4,0);if(!wait_enable(0))audit_errors|=2;
 network_before=rd(ETH+4);
 const uint32_t counters[5]={AI+0x88,RX+0x48,RX+0x4c,RX+0x50,RX+0x54};
 for(unsigned i=0;i<5;i++)before[i]=rd(counters[i]);
 if(!audit_errors){run_one(requested,0);run_one(requested,1);}
 network_after=rd(ETH+4);
 for(unsigned i=0;i<5;i++){after[i]=rd(counters[i]);if(before[i]!=after[i])audit_errors|=4;}
 if(!idle()||network_before||network_after) audit_errors|=8;
 wr(ETH+4,saved);if(!wait_enable(saved))audit_errors|=16;
 if(completed!=3)audit_errors|=32;
 state=2;
}
static unsigned reply(uint8_t *out,uint32_t op,uint32_t seq,uint32_t error){
 uint32_t words[FIELDS]={1,op,seq,error,REPLAY_BUILD_ID,state,identity,requested,completed,HZ,
                        audit_errors,network_before,network_after,boot_sample};
 for(unsigned p=0;p<2;p++)for(unsigned i=0;i<RFIELDS;i++)words[HEADER+p*RFIELDS+i]=records[p][i];
 memcpy(out,"NCRP",4);for(unsigned i=0;i<FIELDS;i++)put(out+4+4*i,words[i]);
 put(out+4+4*FIELDS,crc32(out,4+4*FIELDS));return 8+4*FIELDS;
}
void replay_main(void){
 /* Same image in the simulator and on the board. It starts with an automatic
  * 100-iteration pair before touching Ethernet. The frozen harness ends after
  * the first PORT_DONE; the board retains both captures and serves queries. */
 requested=100;state=1;boot_sample=1;run_one(100,0);run_one(100,1);state=2;
 nigo_eth_open(&ethernet,ETH);
 if(nigo_eth_configure(&ethernet,UINT64_C(0x020000000032),0xc0a80132u,0xffffff00u,0xc0a80101u,1000000u)){wr(0x10000000u,0xe1);for(;;){}}
 uint32_t queued=0;
 for(;;){
  if(nigo_eth_ready(&ethernet)&&(rd(ETH+0x100)&1)&&!rd(ETH+0x14c)){
   uint32_t length=rd(ETH+0x10c),peer=rd(ETH+0x104),ports=rd(ETH+0x108);
   uint8_t packet[24],response[168];unsigned n=0;
   if(length==24){
    for(unsigned i=0;i<24;i+=4){uint32_t word=rd(ETH+0x300+i);for(unsigned b=0;b<4;b++)packet[i+b]=word>>(8*b);}
    if(!memcmp(packet,"NCRQ",4)&&be(packet+4)==1){
     uint32_t op=be(packet+8),seq=be(packet+12),id=be(packet+16),count=be(packet+20),error=0;
     if(op==2){
      if(!id||!count||count>11000)error=2;
      else if(id==identity){if(count!=requested)error=2;}
      else if(state==1)error=1;
      else{identity=id;requested=count;state=1;completed=0;queued=now();}
     }else if(op!=1)error=2;
     else if(id&&id!=identity)error=3;
     n=reply(response,op,seq,error);
    }
   }
   wr(ETH+0x114,1);wr(ETH+0xc,1);
   if(n){for(unsigned i=0;i<n;i+=4){uint32_t word=0;for(unsigned b=0;b<4&&i+b<n;b++)word|=(uint32_t)response[i+b]<<(8*b);wr(ETH+0x200+i,word);}
    wr(ETH+0x144,peer);wr(ETH+0x148,5001u<<16|(ports>>16));wr(ETH+0x140,n);wr(ETH+0x14c,1);}
  }
  if(state==1&&(uint32_t)(now()-queued)>HZ*3u/10u&&!rd(ETH+0x14c))suite();
 }
}
