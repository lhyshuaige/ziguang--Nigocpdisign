#include "ethernet_soc.h"
static void ordered_io(void) {
#if defined(__riscv)
    __asm__ volatile("fence iorw,iorw" ::: "memory");
#else
    __asm__ volatile("" ::: "memory");
#endif
}
static uint32_t reg_read(volatile uint32_t *base, unsigned offset) {
    uint32_t value=base[offset/4]; ordered_io(); return value;
}
static void reg_write(volatile uint32_t *base, unsigned offset, uint32_t value) {
    ordered_io(); base[offset/4]=value; ordered_io();
}
void nigo_eth_soc_open(nigo_eth_soc *soc, uintptr_t base) {
    nigo_eth_open(&soc->network,base);
    soc->image=(volatile uint32_t *)(base+NIGO_ETHERNET_IMAGE_JOB_OFFSET);
}
int nigo_eth_image_submit(nigo_eth_soc *soc, const nigo_eth_image *image) {
    if(!image || !image->width || !image->height || image->rgb565>1 ||
       (image->ddr_base&31u) || (image->stride_bytes&31u))return -2;
    uint64_t row=(uint64_t)image->width*4;
    uint64_t stride=image->stride_bytes?image->stride_bytes:(row+31)&~UINT64_C(31);
    uint64_t end=(uint64_t)image->ddr_base+(image->height-1)*stride+row;
    uint64_t bytes=(uint64_t)image->width*image->height*(image->rgb565?2u:1u);
    if(stride<row || image->ddr_base<UINT32_C(0x80000000) ||
       end>UINT64_C(0xc0000000) || bytes>UINT32_MAX)return -2;
    if(reg_read(soc->image,0x004)&1)return -1;
    if(!nigo_eth_ready(&soc->network))return -3;
    reg_write(soc->image,0x010,3);
    reg_write(soc->image,0x020,image->ddr_base);
    reg_write(soc->image,0x024,image->stride_bytes);
    reg_write(soc->image,0x028,(uint32_t)image->height<<16|image->width);
    reg_write(soc->image,0x02c,image->rgb565);
    reg_write(soc->image,0x030,image->frame_id);
    reg_write(soc->image,0x034,(uint32_t)bytes);
    reg_write(soc->image,0x038,image->timestamp);
    reg_write(soc->image,0x03c,image->peer_ip);
    reg_write(soc->image,0x00c,3);
    reg_write(soc->image,0x008,1);
    return 0;
}
int nigo_eth_image_poll(nigo_eth_soc *soc) {
    uint32_t status=reg_read(soc->image,0x004);
    if(status&1)return 0;
    if(status&4)return -1;
    return status&2?1:0;
}
void nigo_eth_image_abort(nigo_eth_soc *soc) {reg_write(soc->image,0x008,2);}
void nigo_eth_image_ack(nigo_eth_soc *soc) {reg_write(soc->image,0x010,3);}
int nigo_eth_result_send(nigo_eth_soc *soc,uint32_t peer_ip,const void *payload,size_t bytes) {
    if(!payload || bytes==0 || bytes>256)return -2;
    volatile uint32_t *base=soc->network.base;
    if(reg_read(base,0x14c))return -1;
    if(!nigo_eth_ready(&soc->network))return -3;
    const uint8_t *data=(const uint8_t *)payload;
    for(size_t i=0;i<bytes;i+=4) {
        uint32_t word=0;
        for(unsigned lane=0;lane<4 && i+lane<bytes;lane++)word|=(uint32_t)data[i+lane]<<(lane*8);
        reg_write(base,0x200+(unsigned)i,word);
    }
    reg_write(base,0x144,peer_ip);
    reg_write(base,0x148,(uint32_t)5002<<16|5002);
    reg_write(base,0x140,(uint32_t)bytes);
    reg_write(base,0x14c,1);
    return 0;
}
