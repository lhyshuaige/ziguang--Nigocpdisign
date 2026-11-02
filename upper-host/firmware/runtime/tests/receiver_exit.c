#include "mode.h"
#include "ethernet_rx_service.h"
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>
#include <string.h>
static unsigned calls,cancelled,taken,released,status,states,pending,stuck;static jmp_buf end;
int runtime_pending(void){return (int)pending;}
int runtime_application_rx_ready(void){return 0;}
uint32_t runtime_peer(void){return 100;}
int runtime_poll(int safe,uint32_t busy,uint32_t flags){
 (void)flags;calls++;pending=1;
 assert(safe==(!(status&3)&&!states));assert(busy==(safe?0:MODE_BUSY_RX));
 if(stuck&&calls==12)longjmp(end,1);
 if(safe){assert(cancelled==1&&released==1);return 1;}return 0;
}
void nigo_rx_open(nigo_rx *r,uintptr_t base,nigo_rx_cache_fn fn,void *c){(void)base;(void)fn;(void)c;memset(r,0,sizeof(*r));}
void nigo_rx_nax_cache(void *p,unsigned n){(void)p;(void)n;}
void nigo_rx_service_open(nigo_rx_service *s,nigo_rx *r,uintptr_t b,const nigo_rx_job*j,uint32_t p){(void)s;(void)r;(void)b;(void)j;(void)p;}
int nigo_rx_service_poll(nigo_rx_service *s){(void)s;assert(0);return 0;}
void nigo_rx_cancel(nigo_rx*r){(void)r;cancelled++;assert(status&3);}
void nigo_rx_get_progress(nigo_rx*r,nigo_rx_progress*p){(void)r;
 if(!stuck&&cancelled&&calls>3&&!released&&!taken){status=16;states=2;}
 memset(p,0,sizeof(*p));p->status=status;p->states=states;
}
int nigo_rx_take(nigo_rx*r,nigo_rx_frame*f){(void)r;(void)f;assert(!(status&3)&&status&16);taken++;status=32;states=3;return 0;}
int nigo_rx_release(nigo_rx*r){(void)r;assert(status&32);released++;status=states=0;return 0;}
int main(void){
 status=3;states=1;runtime_receiver();assert(calls>4&&cancelled==1&&taken==1&&released==1);
 calls=cancelled=taken=released=pending=0;stuck=1;status=3;states=1;
 if(!setjmp(end)){runtime_receiver();assert(0);}
 assert(cancelled==1&&!taken&&!released);puts("RX_EXIT_PASS waits for DMA drain, releases READY/READ, never forces hung DMA reset");return 0;
}
