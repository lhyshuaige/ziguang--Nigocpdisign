#include "ethernet_rx_service.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct { uint32_t reg[256];unsigned writes,arms,takes,releases,pre,post,sequence,pre_order,arm_order; } model;
static uint32_t read_reg(void *context,unsigned addr) { model *m=context;return m->reg[addr/4]; }
static void write_reg(void *context,unsigned addr,uint32_t value) {
    model *m=context;m->writes++;m->sequence++;
    if(addr==0x10) { m->reg[addr/4]&=~value;return; }
    if(addr==8) {
        if(value==1) { assert(m->pre);m->arms++;m->arm_order=m->sequence;m->reg[1]=65;m->reg[0x40/4]=1; }
        if(value==2) { m->reg[1]&=~3u;if(m->reg[0x40/4]==1)m->reg[0x40/4]=0; }
        if(value==4) { m->takes++;m->reg[1]=(m->reg[1]&~16u)|32u;m->reg[0x40/4]=3;m->reg[0x74/4]=2; }
        if(value==8) { m->releases++;m->reg[1]&=~32u;m->reg[0x40/4]=0;m->reg[0x74/4]=0; }
    } else m->reg[addr/4]=value;
}
static void cache_sync(void *context,unsigned phase) {
    model *m=context;m->sequence++;
    if(phase==NIGO_RX_PREPARE) { m->pre++;m->pre_order=m->sequence;assert(!(m->reg[1]&3u)); }
    else { m->post++;assert(m->reg[1]&32u); }
}
static void setup(nigo_rx *dev,model *m) {
    memset(m,0,sizeof(*m));m->reg[0]=0x52584431;m->reg[1]=64;
    nigo_rx_open(dev,NIGO_RX_CSR_BASE,cache_sync,m);dev->read=read_reg;dev->write=write_reg;dev->io_context=m;
}
static void ready(model *m,uint32_t id) {
    m->reg[1]=80;m->reg[0x40/4]=2;m->reg[0x10/4]=1;m->reg[0x44/4]=320*240*2;
    m->reg[0x60/4]=0x94000000;m->reg[0x64/4]=1280;m->reg[0x68/4]=id;
    m->reg[0x6c/4]=240u<<16|320u;m->reg[0x70/4]=1;
}
static void put(uint8_t *p,uint32_t v) { p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v; }
static uint32_t be(const uint8_t *p) { return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3]; }
static void request(model *mb,uint32_t seq,uint32_t op,uint32_t id) {
    uint8_t p[32]={0};memcpy(p,"NGR1",4);put(p+4,seq);put(p+8,op);put(p+12,id);put(p+16,320u<<16|240u);put(p+20,1);
    for(unsigned i=0;i<8;i++) { uint32_t v=0;for(unsigned j=0;j<4;j++)v|=(uint32_t)p[4*i+j]<<(8*j);mb->reg[0x300/4+i]=v; }
    mb->reg[0x100/4]=1;mb->reg[0x104/4]=0xc0a80164;mb->reg[0x108/4]=55555u<<16|5001;mb->reg[0x10c/4]=32;mb->reg[0x14c/4]=0;
}
static void reply(model *mb,uint8_t *out) { for(unsigned i=0;i<16;i++)for(unsigned j=0;j<4;j++)out[4*i+j]=(uint8_t)(mb->reg[0x200/4+i]>>(8*j)); }
int main(void) {
    nigo_rx dev;nigo_rx_frame frame;model hw,mb;nigo_rx_service service;uint8_t ack[64];unsigned before;
    nigo_rx_job job={{0x94000000u,0x94100000u},0x100000u,0,13,0xc0a80164u,320,240,1};
    setup(&dev,&hw);dev.cache=0;assert(nigo_rx_arm(&dev,&job)==NIGO_RX_CACHE_REQUIRED);dev.cache=cache_sync;
    job.base[0]++;assert(nigo_rx_arm(&dev,&job)==NIGO_RX_INVALID);job.base[0]--;
    job.capacity=0xffffffffu;assert(nigo_rx_arm(&dev,&job)==NIGO_RX_INVALID);job.capacity=0x100000;
    assert(!hw.writes && !hw.pre);assert(nigo_rx_arm(&dev,&job)==0);assert(hw.pre==1 && hw.arms==1 && hw.pre_order<hw.arm_order);
    before=hw.writes;assert(nigo_rx_arm(&dev,&job)==NIGO_RX_BUSY && hw.writes==before);
    ready(&hw,13);assert(!nigo_rx_take(&dev,&frame));assert(frame.id==13 && frame.base==job.base[0] && frame.width==320 && frame.height==240 && frame.rgb565==1 && hw.post==1);
    assert(nigo_rx_take(&dev,&frame)==NIGO_RX_BUSY);assert(!nigo_rx_release(&dev));assert(nigo_rx_release(&dev)==NIGO_RX_BUSY);
    hw.reg[1]=0;assert(nigo_rx_arm(&dev,&job)==NIGO_RX_LINK_DOWN);
    hw.reg[1]=64;hw.reg[0x40/4]=2;job.base[1]+=0x100000;assert(nigo_rx_arm(&dev,&job)==NIGO_RX_BUSY);job.base[1]-=0x100000;
    assert(!nigo_rx_arm(&dev,&job));nigo_rx_cancel(&dev);assert(!(hw.reg[1]&3u));
    setup(&dev,&hw);memset(&mb,0,sizeof(mb));mb.reg[2]=0x18;
    nigo_rx_service_open(&service,&dev,0x10020000,&job,0xc0a80164);
    service.mailbox.read=read_reg;service.mailbox.write=write_reg;service.mailbox.io_context=&mb;
    request(&mb,1,1,50);assert(nigo_rx_service_poll(&service)==1);reply(&mb,ack);
    assert(!memcmp(ack,"NGS1",4) && !be(ack+12) && be(ack+44)==50 && hw.arms==1);
    request(&mb,1,1,50);assert(nigo_rx_service_poll(&service)==1 && hw.arms==1 && hw.pre==1);
    request(&mb,2,1,51);assert(nigo_rx_service_poll(&service)==1);reply(&mb,ack);
    assert((int32_t)be(ack+12)==NIGO_RX_BUSY && service.job.id==50);
    ready(&hw,50);request(&mb,3,3,50);assert(nigo_rx_service_poll(&service)==1);reply(&mb,ack);
    assert(be(ack+48)==0x94000000 && be(ack+52)==1280 && be(ack+56)==(320u<<16|240u) && hw.takes==1 && hw.post==1);
    request(&mb,3,3,50);assert(nigo_rx_service_poll(&service)==1 && hw.takes==1);
    FILE *file=fopen("service_ack.bin","wb");assert(file);assert(fwrite(ack,1,64,file)==64);fclose(file);
    request(&mb,4,4,50);assert(nigo_rx_service_poll(&service)==1 && hw.releases==1);
    request(&mb,4,4,50);assert(nigo_rx_service_poll(&service)==1 && hw.releases==1);
    request(&mb,2,1,51);assert(nigo_rx_service_poll(&service)==-1 && hw.arms==1);
    puts("RX_DRIVER_SERVICE_PASS cache_order, ownership, control retry/replay, no CPU image copy");return 0;
}
