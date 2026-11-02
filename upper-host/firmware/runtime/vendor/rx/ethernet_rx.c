#include "ethernet_rx.h"
#include <string.h>
enum { ID=0,STATUS=4,CMD=8,IRQ_MASK=12,EVENTS=16,BASE0=32,BASE1=36,CAPACITY=40,
       STRIDE=44,SIZE=48,FORMAT=52,FRAME_ID=56,PEER=60,STATES=64,OFFSET=68,
       FRAMES_OK=72,FRAMES_BAD=76,PACKETS_OK=80,PACKETS_BAD=84,
       SNAP_BASE=96,SNAP_STRIDE=100,SNAP_ID=104,SNAP_SIZE=108,SNAP_FORMAT=112,SNAP_VALID=116 };
static void barrier(void) {
#if defined(__riscv)
    __asm__ volatile("fence iorw,iorw" ::: "memory");
#else
    __asm__ volatile("" ::: "memory");
#endif
}
static uint32_t mmio_read(void *context,unsigned reg) {
    nigo_rx *dev=context;uint32_t value=*(volatile uint32_t *)(dev->base+reg);barrier();return value;
}
static void mmio_write(void *context,unsigned reg,uint32_t value) {
    nigo_rx *dev=context;barrier();*(volatile uint32_t *)(dev->base+reg)=value;barrier();
}
static uint32_t rd(nigo_rx *dev,unsigned reg) { return dev->read(dev->io_context,reg); }
static void wr(nigo_rx *dev,unsigned reg,uint32_t value) { dev->write(dev->io_context,reg,value); }
void nigo_rx_open(nigo_rx *dev,uintptr_t base,nigo_rx_cache_fn cache,void *context) {
    memset(dev,0,sizeof(*dev));dev->base=base;dev->io_context=dev;dev->read=mmio_read;dev->write=mmio_write;
    dev->cache=cache;dev->cache_context=context;
}
static int validate(const nigo_rx_job *job) {
    uint64_t row=(uint64_t)job->width*4u,stride=job->stride?job->stride:(row+31u)&~UINT64_C(31);
    uint64_t end0=(uint64_t)job->base[0]+job->capacity,end1=(uint64_t)job->base[1]+job->capacity;
    if(!job->width || !job->height || job->width>640 || job->height>480 || job->rgb565>1 ||
       (job->base[0]&31) || (job->base[1]&31) || (stride&31) || stride<row || !job->capacity ||
       (uint64_t)(job->height-1u)*stride+row>job->capacity ||
       job->base[0]<0x80000000u || job->base[1]<0x80000000u || end0>UINT64_C(0xc0000000) || end1>UINT64_C(0xc0000000) ||
       !(end0<=job->base[1] || end1<=job->base[0]))return NIGO_RX_INVALID;
    return 0;
}
int nigo_rx_arm(nigo_rx *dev,const nigo_rx_job *job) {
    uint32_t status,states;int error;
    if(!dev || !job || !dev->read || !dev->write)return NIGO_RX_INVALID;
    if(!dev->cache)return NIGO_RX_CACHE_REQUIRED;
    if((error=validate(job)))return error;
    if(rd(dev,ID)!=0x52584431u)return NIGO_RX_HARDWARE;
    status=rd(dev,STATUS);states=rd(dev,STATES);
    if(status&3u)return NIGO_RX_BUSY;
    if(!(status&64u))return NIGO_RX_LINK_DOWN;
    if((states&3u)!=0 && (states&12u)!=0)return NIGO_RX_BUSY;
    if(states && (rd(dev,BASE0)!=job->base[0] || rd(dev,BASE1)!=job->base[1] || rd(dev,CAPACITY)!=job->capacity))return NIGO_RX_BUSY;
    /* Clean dirty aliases before hardware can write either reserved slot. */
    dev->cache(dev->cache_context,NIGO_RX_PREPARE);barrier();
    wr(dev,BASE0,job->base[0]);wr(dev,BASE1,job->base[1]);wr(dev,CAPACITY,job->capacity);wr(dev,STRIDE,job->stride);
    wr(dev,SIZE,(uint32_t)job->height<<16|job->width);wr(dev,FORMAT,job->rgb565);wr(dev,FRAME_ID,job->id);wr(dev,PEER,job->peer_ip);
    wr(dev,EVENTS,7);wr(dev,IRQ_MASK,15);wr(dev,CMD,1);return 0;
}
void nigo_rx_get_progress(nigo_rx *dev,nigo_rx_progress *out) {
    /* Events/counters can change between reads; completion must be based on
     * READY+snapshot and the requested frame ID, not this diagnostic tuple. */
    out->status=rd(dev,STATUS);out->events=rd(dev,EVENTS);out->offset=rd(dev,OFFSET);
    out->frames_ok=rd(dev,FRAMES_OK);out->frames_bad=rd(dev,FRAMES_BAD);
    out->packets_ok=rd(dev,PACKETS_OK);out->packets_bad=rd(dev,PACKETS_BAD);out->states=rd(dev,STATES);
}
int nigo_rx_take(nigo_rx *dev,nigo_rx_frame *out) {
    uint32_t value,status;
    if(!dev || !out)return NIGO_RX_INVALID;
    if(!dev->cache)return NIGO_RX_CACHE_REQUIRED;
    status=rd(dev,STATUS);if(!(status&16u) || (status&32u))return NIGO_RX_BUSY;
    wr(dev,CMD,4);value=rd(dev,SNAP_VALID);if(!(value&2u))return NIGO_RX_HARDWARE;
    out->slot=(uint8_t)(value&1u);out->base=rd(dev,SNAP_BASE);out->stride=rd(dev,SNAP_STRIDE);out->id=rd(dev,SNAP_ID);
    value=rd(dev,SNAP_SIZE);out->width=(uint16_t)value;out->height=(uint16_t)(value>>16);out->rgb565=(uint8_t)rd(dev,SNAP_FORMAT);
    dev->cache(dev->cache_context,NIGO_RX_ACQUIRE);barrier();return 0;
}
int nigo_rx_release(nigo_rx *dev) {
    if(!(rd(dev,STATUS)&32u))return NIGO_RX_BUSY;
    barrier();wr(dev,CMD,8);return 0;
}
void nigo_rx_cancel(nigo_rx *dev) { wr(dev,CMD,2); }
#if defined(__riscv)
void nigo_rx_nax_cache(void *unused,unsigned phase) {
    (void)unused;(void)phase;
    __asm__ volatile("fence iorw,iorw\n.word 0x0000500f\nfence iorw,iorw" ::: "memory");
}
#endif
