#include "ethernet_rx_service.h"
#include <string.h>
static uint32_t rd(nigo_rx *dev,unsigned reg) { return dev->read(dev->io_context,reg); }
static void wr(nigo_rx *dev,unsigned reg,uint32_t v) { dev->write(dev->io_context,reg,v); }
static void acknowledge(nigo_rx *dev) { wr(dev,0x114,1);wr(dev,0x00c,1); }
static uint32_t be(const uint8_t *p) { return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3]; }
static void put(uint8_t *p,uint32_t v) { p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v; }
void nigo_rx_service_open(nigo_rx_service *s,nigo_rx *rx,uintptr_t mailbox,const nigo_rx_job *layout,uint32_t peer) {
    memset(s,0,sizeof(*s));s->rx=rx;s->job=*layout;s->allowed_peer=peer;nigo_rx_open(&s->mailbox,mailbox,0,0);
}
int nigo_rx_service_poll(nigo_rx_service *s) {
    nigo_rx_progress p;uint32_t ip,ports,seq,op,value,wh;int error=0,duplicate=0;
    nigo_rx *mb=&s->mailbox;
    if(!(rd(mb,0x100)&1u) || rd(mb,0x14c)!=0)return 0;
    ip=rd(mb,0x104);ports=rd(mb,0x108);
    if(rd(mb,0x10c)!=32 || ip!=s->allowed_peer) { acknowledge(mb);return -1; }
    for(unsigned i=0;i<8;i++) { value=rd(mb,0x300+4*i);for(unsigned j=0;j<4;j++)s->request[4*i+j]=(uint8_t)(value>>(8*j)); }
    if(memcmp(s->request,"NGR1",4) || be(s->request+24) || be(s->request+28)) { acknowledge(mb);return -1; }
    seq=be(s->request+4);op=be(s->request+8);
    if(s->have_request && s->last_ip==ip && s->last_ports==ports && s->last_seq==seq) {
        if(memcmp(s->last_request,s->request,32)) { acknowledge(mb);return -1; }
        duplicate=1;
    } else if(s->have_request && s->last_ip==ip && s->last_ports==ports && (int32_t)(seq-s->last_seq)<=0) {
        acknowledge(mb);return -1; /* stale control replay has no side effect */
    }
    if(!duplicate) {
        if(op==1) {
            nigo_rx_get_progress(s->rx,&p);
            /* This simple upload demo accepts one frame at a time; the lower
             * driver/hardware still support two owned buffers for applications. */
            if((p.status&3u) || p.states || s->have_frame)error=NIGO_RX_BUSY;
            else {
                s->job.id=be(s->request+12);wh=be(s->request+16);
                s->job.width=(uint16_t)(wh>>16);s->job.height=(uint16_t)wh;
                value=be(s->request+20);
                if(value>1)error=NIGO_RX_INVALID;
                else { s->job.rgb565=(uint8_t)value;s->job.peer_ip=ip;error=nigo_rx_arm(s->rx,&s->job); }
            }
        } else if(op==2) { /* progress query, no side effect */ }
        else if(be(s->request+12)!=s->job.id)error=NIGO_RX_INVALID;
        else if(op==3) { error=nigo_rx_take(s->rx,&s->acquired);if(!error)s->have_frame=1; }
        else if(op==4) { error=nigo_rx_release(s->rx);if(!error)s->have_frame=0; }
        else if(op==5) { nigo_rx_cancel(s->rx); }
        else error=NIGO_RX_INVALID;
        nigo_rx_get_progress(s->rx,&p);
        memcpy(s->ack,"NGS1",4);put(s->ack+4,seq);put(s->ack+8,op);put(s->ack+12,(uint32_t)error);
        put(s->ack+16,p.status);put(s->ack+20,p.events);put(s->ack+24,p.offset);put(s->ack+28,p.frames_ok);
        put(s->ack+32,p.frames_bad);put(s->ack+36,p.packets_ok);put(s->ack+40,p.packets_bad);
        put(s->ack+44,s->have_frame?s->acquired.id:s->job.id);put(s->ack+48,s->have_frame?s->acquired.base:0);
        put(s->ack+52,s->have_frame?s->acquired.stride:0);
        put(s->ack+56,s->have_frame?((uint32_t)s->acquired.width<<16|s->acquired.height):0);
        put(s->ack+60,s->have_frame?s->acquired.rgb565:0);
        memcpy(s->last_request,s->request,32);s->last_seq=seq;s->last_ip=ip;s->last_ports=ports;s->have_request=1;
    }
    /* No TX while the link is down: the mailbox would return a bus error.
     * Keep the reply cached so the identical request can be retried after link-up. */
    if((rd(mb,8)&0x18u)!=0x18u) { acknowledge(mb);return 1; }
    for(unsigned i=0;i<16;i++) { value=0;for(unsigned j=0;j<4;j++)value|=(uint32_t)s->ack[4*i+j]<<(8*j);wr(mb,0x200+4*i,value); }
    wr(mb,0x144,ip);wr(mb,0x148,5001u<<16|(ports>>16));wr(mb,0x140,64);wr(mb,0x14c,1);acknowledge(mb);
    return 1;
}
