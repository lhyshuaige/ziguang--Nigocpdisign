#include <assert.h>
#include <stdio.h>
#include <stdint.h>
static uint32_t fake_mmio_read(uintptr_t a){(void)a;return 0;}
static void fake_mmio_write(uintptr_t a,uint32_t v){(void)a;(void)v;}
#define nigo_ai_open fake_ai_open
#define nigo_eth_result_send fake_result_send
#define nigo_eth_ready fake_eth_ready
#define uf_poll fake_uf_poll
#include "native_face.inc"
#undef nigo_ai_open
#undef nigo_eth_result_send
#undef nigo_eth_ready
#undef uf_poll
static unsigned calls,hardware_busy,poll_calls,sends;
static uint32_t fake_ai_read(void*p,unsigned off){(void)p;(void)off;if(hardware_busy){hardware_busy--;return 1;}return 0;}
static void fake_ai_write(void*p,unsigned off,uint32_t value){(void)p;(void)off;(void)value;}
void fake_ai_open(nigo_ai *a,uintptr_t base){(void)base;nigo_ai_bind(a,0,fake_ai_read,fake_ai_write);}
int fake_eth_ready(nigo_eth *e){(void)e;return 1;}
int fake_result_send(nigo_eth_soc*s,uint32_t peer,const void*p,size_t n){(void)s;(void)peer;(void)p;(void)n;sends++;return sends<2?-1:0;}
int fake_uf_poll(uf_runtime*r){if(++poll_calls<3)return 0;r->state=0;return -1;}
int runtime_pending(void){return 1;}
int runtime_application_rx_ready(void){return 0;}
int runtime_poll(int safe,uint32_t busy,uint32_t flags){
 calls++;assert(flags==1);assert(model_valid&&model_slot==1&&runtime.model==(void*)0x93200000u);
 if(runtime.state)assert(!safe&&(busy&MODE_BUSY_AI));
 if(upload.active)assert(!safe&&(busy&MODE_BUSY_UPLOAD));
 if(result_pending)assert(!safe&&(busy&MODE_BUSY_RESULT));
 assert(calls<20);return safe;
}
int main(void){
 model_valid=1;model_slot=1;runtime.model=(void*)0x93200000u;
 runtime_face();assert(calls==1); /* first initialized entry */
 calls=0;upload.active=1;upload_target=MODEL0;runtime_face();assert(calls>=2&&!upload.active&&!upload_target);
 calls=0;hardware_busy=3;runtime_face();assert(calls>=4); /* even software idle waits for hardware */
 calls=0;runtime.state=1;runtime.ai=&accelerator;runtime_face();assert(poll_calls==3&&sends==2&&!result_pending);
 assert(model_valid&&model_slot==1&&runtime.model==(void*)0x93200000u);
 puts("AI_EXIT_PASS retains model across entry, cancels partial upload, waits for accelerator and result TX");return 0;
}
