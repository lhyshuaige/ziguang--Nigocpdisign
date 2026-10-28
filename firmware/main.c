#include "nigo_ai.h"
#include "ngu_upload.h"
#include "ultraface_runtime.h"
#include "face_events.h"
#include "model_asset.h"
#include "ethernet_soc.h"
#include <string.h>

#define MODEL0 ((uint8_t *)(uintptr_t)0x93000000u)
#define MODEL1 ((uint8_t *)(uintptr_t)0x93200000u)
#define FRAME ((uint8_t *)(uintptr_t)0x93400000u)
#define ARENA ((uint8_t *)(uintptr_t)0x90000000u)
#define TENSORS ((int8_t *)(uintptr_t)0x92000000u)
#define ETH_BASE ((uintptr_t)0x10020000u)
static nigo_eth_soc ethernet;
static nigo_ai accelerator;
static uf_runtime runtime;
static ngu_upload upload;
static face_events presence;
static unsigned model_valid,model_slot,frame_ready,result_pending,last_error;
static uint8_t *upload_target;
static uint32_t rx_source,frame_source,frame_id,frame_stamp,infer_source,infer_id,infer_stamp;
static uint32_t upload_activity,infer_started,sequence;
static uint8_t result[224];static size_t result_bytes;

static void ordered_io(void){
#if defined(__riscv)
 __asm__ volatile("fence iorw,iorw" ::: "memory");
#else
 __asm__ volatile("" ::: "memory");
#endif
}
static uint32_t rd(uintptr_t base,unsigned off){uint32_t v=*(volatile uint32_t *)(base+off);ordered_io();return v;}
static void wr(uintptr_t base,unsigned off,uint32_t v){ordered_io();*(volatile uint32_t *)(base+off)=v;ordered_io();}
static uint32_t milliseconds(void){
 uint32_t hi,lo,next;do{hi=rd(0x10000000u,0xc);lo=rd(0x10000000u,8);next=rd(0x10000000u,0xc);}while(hi!=next);
 return (uint32_t)((((uint64_t)hi<<32)|lo)/100000u); /* sys100 mtime ticks */
}
static void cache_sync(void *context){
 (void)context;
#if defined(__riscv)
 /* NaxRiscv EnvCallPlugin FLUSH_DATA: drains writes, writes back all dirty
  * cache lines and frees them. Verified in local Rvi.scala/EnvCall/Lsu2 RTL. */
 __asm__ volatile("fence iorw,iorw\n.word 0x0000500f\nfence iorw,iorw" ::: "memory");
#endif
}
static int sink_begin(void *context,unsigned kind,uint32_t bytes,uint32_t id,uint32_t stamp){
 (void)context;(void)id;(void)stamp;
 if(frame_ready||runtime.state||result_pending)return NGU_BUSY;
 if(kind==1){if(bytes!=NIGO_MODEL_BYTES)return NGU_SIZE;upload_target=model_slot?MODEL0:MODEL1;}
 else{if(!model_valid)return NGU_BUSY;upload_target=FRAME;}
 return NGU_OK;
}
static void sink_store(void *context,uint32_t offset,const uint8_t *p,size_t bytes){(void)context;memcpy(upload_target+offset,p,bytes);}
static int sink_commit(void *context,unsigned kind,uint32_t id,uint32_t stamp){
 (void)context;
 if(kind==1){
  if(uf_bind(&runtime,upload_target,NIGO_MODEL_BYTES,&accelerator,ARENA,NIGO_MODEL_ARENA_BYTES,
             0x90000000u,TENSORS,NIGO_MODEL_TENSOR_BYTES,cache_sync,0))return NGU_BAD;
  model_slot=upload_target==MODEL1;model_valid=1;memset(&presence,0,sizeof(presence));
 }else{frame_id=id;frame_stamp=stamp;frame_source=rx_source;frame_ready=1;}
 return NGU_OK;
}
static void sink_abort(void *context){(void)context;upload_target=0;}
static void send_mailbox(uint32_t peer,uint16_t source_port,uint16_t dest_port,const uint8_t *p,size_t bytes){
 for(size_t i=0;i<bytes;i+=4){uint32_t word=0;for(unsigned b=0;b<4&&i+b<bytes;b++)word|=(uint32_t)p[i+b]<<(8*b);wr(ETH_BASE,0x200+(unsigned)i,word);}
 wr(ETH_BASE,0x144,peer);wr(ETH_BASE,0x148,(uint32_t)source_port<<16|dest_port);wr(ETH_BASE,0x140,(uint32_t)bytes);wr(ETH_BASE,0x14c,1);
}
static void service_upload(uint32_t now){
 if(!nigo_eth_ready(&ethernet.network))return;
 if(!(rd(ETH_BASE,0x100)&1u)||rd(ETH_BASE,0x14c))return;
 uint32_t n=rd(ETH_BASE,0x10c),ports=rd(ETH_BASE,0x108);rx_source=rd(ETH_BASE,0x104);
 uint8_t packet[256],ack[24];
 if(n>256||n<4){wr(ETH_BASE,0x114,1);return;}
 for(uint32_t i=0;i<n;i+=4){uint32_t word=rd(ETH_BASE,0x300+i);for(unsigned b=0;b<4&&i+b<n;b++)packet[i+b]=(uint8_t)(word>>(8*b));}
 if(n==16&&!memcmp(packet,"NGC1",4)){nigo_eth_service(&ethernet.network,0,0);return;}
 size_t response=ngu_handle(&upload,rx_source,(uint16_t)(ports>>16),packet,n,ack);
 if(response){send_mailbox(rx_source,5001,(uint16_t)(ports>>16),ack,response);upload_activity=now;}
 wr(ETH_BASE,0x114,1);wr(ETH_BASE,0xc,1);
}
void nigo_application_main(void){
 nigo_ai_open(&accelerator,NIGO_AI_BASE);nigo_eth_soc_open(&ethernet,ETH_BASE);
 ngu_sink sink={sink_begin,sink_store,sink_commit,sink_abort,0};ngu_init(&upload,&sink);
 if(nigo_eth_configure(&ethernet.network,UINT64_C(0x020000000032),0xc0a80132u,0xffffff00u,0xc0a80101u,1000000u))last_error=1;
 for(;;){
  uint32_t now=milliseconds();
  if(upload.active&&((uint32_t)(now-upload_activity)>5000u||!nigo_eth_ready(&ethernet.network)))ngu_cancel(&upload);
  if(result_pending&&nigo_eth_result_send(&ethernet,infer_source,result,result_bytes)==0)result_pending=0;
  service_upload(now);
  if(frame_ready&&!runtime.state&&!result_pending){
   if(uf_start(&runtime,FRAME,frame_id)==0){infer_source=frame_source;infer_id=frame_id;infer_stamp=frame_stamp;infer_started=now;frame_ready=0;last_error=0;}
   else{last_error=1;frame_ready=0;}
  }
  if(runtime.state){
   int status=uf_poll(&runtime);
   if(status==1||status==-1){
    uf_box boxes[FACE_MAX];unsigned count=0,event=0;
    if(status==1){count=uf_decode(&runtime,boxes,FACE_MAX);event=face_events_update(&presence,boxes,count);}
    else last_error=1;
    result_bytes=face_result_encode(result,infer_id,infer_stamp,++sequence,(uint32_t)(milliseconds()-infer_started),boxes,count,event,status==-1);
    result_pending=1;
   }
  }
  wr(0x10000000u,0,(nigo_eth_ready(&ethernet.network)?1u:0u)|(model_valid?2u:0u)|
     (runtime.state?4u:0u)|(frame_ready?8u:0u)|(result_pending?16u:0u)|(last_error?128u:0u));
 }
}
