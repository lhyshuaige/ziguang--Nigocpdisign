#include "loader.h"
#include "flash_boot_service.h"
#include "ethernet.h"
#include <string.h>

#define ETH UINT32_C(0x10020000)
static ngb_loader loader;
static nigo_eth ethernet;
static void io_fence(void) { __asm__ volatile("fence iorw,iorw" ::: "memory"); }
static uint32_t rd(uintptr_t base,unsigned off) {
    uint32_t v=*(volatile uint32_t *)(base+off);io_fence();return v;
}
static void wr(uintptr_t base,unsigned off,uint32_t value) {
    io_fence();*(volatile uint32_t *)(base+off)=value;io_fence();
}
static uint32_t milliseconds(void) {
    uint32_t hi,lo,next;
    do { hi=rd(0x10000000u,12);lo=rd(0x10000000u,8);next=rd(0x10000000u,12); } while(hi!=next);
    return (uint32_t)((((uint64_t)hi<<32)|lo)/100000u);
}
static void publish(void *context) {
    (void)context;
    /* Nax EnvCallPlugin FLUSH_DATA, followed by the standard ordering fence. */
    __asm__ volatile("fence iorw,iorw\n.word 0x0000500f\nfence iorw,iorw" ::: "memory");
}
extern void ngb_jump(uint32_t entry) __attribute__((noreturn));
static void send_reply(uint32_t peer,uint16_t port,const uint8_t *p,size_t bytes) {
    for(size_t i=0;i<bytes;i+=4) {
        uint32_t word=0;for(unsigned b=0;b<4&&i+b<bytes;b++)word|=(uint32_t)p[i+b]<<(8*b);
        wr(ETH,0x200+(unsigned)i,word);
    }
    wr(ETH,0x144,peer);wr(ETH,0x148,(uint32_t)5001<<16|port);
    wr(ETH,0x140,(uint32_t)bytes);wr(ETH,0x14c,1);
}
void nigo_network_main(void) {
    nigo_eth_open(&ethernet,ETH);
    ngb_init(&loader,(uint8_t *)(uintptr_t)NGB_STAGE,(uint8_t *)(uintptr_t)NGB_LOAD,publish,0);
    if(nigo_eth_configure(&ethernet,UINT64_C(0x020000000032),0xc0a80132u,0xffffff00u,0xc0a80101u,1000000u)) {
        wr(0x10000000u,0,0xe1);for(;;){}
    }
    uint32_t activity=milliseconds();
    for(;;) {
        uint32_t now=milliseconds();int ready=nigo_eth_ready(&ethernet);
        if(loader.upload.active&&(now-activity>5000u||!ready))ngb_cancel(&loader);
        if(!ready&&loader.execute_pending)ngb_cancel(&loader);
        if(ready&&(rd(ETH,0x100)&1u)&&!rd(ETH,0x14c)) {
            uint32_t length=rd(ETH,0x10c),peer=rd(ETH,0x104),ports=rd(ETH,0x108);
            uint8_t packet[256],reply[NGB_REPLY];size_t response=0;
            if(length<=256) {
                for(uint32_t i=0;i<length;i+=4) {
                    uint32_t word=rd(ETH,0x300+i);
                    for(unsigned b=0;b<4&&i+b<length;b++)packet[i+b]=(uint8_t)(word>>(8*b));
                }
                if(length>=4&&!memcmp(packet,"NGU1",4))response=ngb_upload(&loader,peer,(uint16_t)(ports>>16),packet,length,reply);
                else {
                    response=flash_install_request(&loader,peer,(uint16_t)(ports>>16),packet,length,reply);
                    if(!response)response=ngb_control(&loader,peer,(uint16_t)(ports>>16),packet,length,reply,now);
                }
                if(response)send_reply(peer,(uint16_t)(ports>>16),reply,response);
                activity=now;
            }
            wr(ETH,0x114,1);wr(ETH,0xc,1);
        }
        /* Keep servicing duplicate execute requests for 300 ms. TX must drain. */
        if(ready&&ngb_jump_due(&loader,now)&&!rd(ETH,0x14c)&&!(rd(ETH,0x100)&1u))ngb_jump(loader.entry);
        wr(0x10000000u,0,(ready?1u:0u)|0x20u|(loader.ready?2u:0u)|(loader.upload.active?4u:0u));
    }
}
