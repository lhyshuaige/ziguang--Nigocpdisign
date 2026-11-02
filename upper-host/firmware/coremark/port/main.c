#include "benchmark.h"
#include "service.h"
#include "ethernet.h"
#define ETH 0x10020000u
static cm_service service;
static nigo_eth ethernet;
static uint32_t rd(unsigned off) {
    uint32_t v=*(volatile uint32_t *)(uintptr_t)(ETH+off);
    __asm__ volatile("fence iorw,iorw" ::: "memory");return v;
}
static void wr(unsigned off,uint32_t v) {
    __asm__ volatile("fence iorw,iorw" ::: "memory");
    *(volatile uint32_t *)(uintptr_t)(ETH+off)=v;
    __asm__ volatile("fence iorw,iorw" ::: "memory");
}
void nigo_application_main(void) {
    nigo_eth_open(&ethernet,ETH);
    if(nigo_eth_configure(&ethernet,UINT64_C(0x020000000032),0xc0a80132u,0xffffff00u,0xc0a80101u,1000000u)) {
        *(volatile uint32_t *)(uintptr_t)0x10000000u=0xe1;for(;;){}
    }
    uint64_t queued_at=0;
    for(;;) {
        if(nigo_eth_ready(&ethernet) && (rd(0x100)&1) && !rd(0x14c)) {
            uint32_t bytes=rd(0x10c),peer=rd(0x104),ports=rd(0x108);
            uint8_t request[24],reply[256];size_t response=0;
            uint32_t previous_id=service.run_id;
            if(bytes==24) {
                for(unsigned i=0;i<24;i+=4){uint32_t word=rd(0x300+i);for(unsigned b=0;b<4;b++)request[i+b]=(uint8_t)(word>>(8*b));}
                response=cm_request(&service,request,bytes,reply);
            }
            if(service.run_id!=previous_id)queued_at=cm_read_ticks();
            if(response) {
                for(size_t i=0;i<response;i+=4){uint32_t word=0;for(unsigned b=0;b<4 && i+b<response;b++)word|=(uint32_t)reply[i+b]<<(8*b);wr(0x200+(unsigned)i,word);}
                wr(0x144,peer);wr(0x148,(uint32_t)5001<<16|(ports>>16));wr(0x140,(uint32_t)response);wr(0x14c,1);
            }
            wr(0x114,1);wr(0x00c,1);
        }
        /* ACK retries are served for 300 ms; then benchmark without network polling. */
        if(service.state==1 && cm_read_ticks()-queued_at>CM_TIMER_HZ*3u/10u && !rd(0x14c)) {
            cm_run(service.iterations);
            service.log_crc=cm_crc32(cm_log,cm_log_length);service.state=2;
        }
        *(volatile uint32_t *)(uintptr_t)0x10000000u=service.state==2?8u:1u;
    }
}
