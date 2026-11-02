#include "service.h"
#include "benchmark.h"
#include "build_info.h"
#include <string.h>
static uint32_t be(const uint8_t *p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static void put(uint8_t *p,uint32_t v){p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v;}
uint32_t cm_crc32(const void *data,size_t bytes) {
    uint32_t crc=~0u;const uint8_t *p=data;
    while(bytes--){crc^=*p++;for(unsigned i=0;i<8;i++)crc=(crc>>1)^(0xedb88320u&(0u-(crc&1)));}
    return ~crc;
}
size_t cm_request(cm_service *s,const uint8_t *p,size_t bytes,uint8_t *reply) {
    if(bytes!=24 || memcmp(p,"NCQ1",4) || be(p+4)!=1)return 0;
    uint32_t op=be(p+8),seq=be(p+12),id=be(p+16),arg=be(p+20),error=0,offset=0,count=0;
    if(op==2) {
        if(!id || arg>1000000u)error=2;
        else if(id==s->run_id) {if(arg!=s->iterations)error=2;}
        else if(s->state==1)error=1;
        else {
            s->run_id=id;s->iterations=arg;s->state=1;s->log_crc=0;
            cm_log_length=0;cm_log_overflow=0;cm_ticks[0]=cm_ticks[1]=0;
        }
    } else if(op==1 || op==3) {
        if(id && id!=s->run_id)error=3;
        else if(op==3) {
            if(s->state!=2)error=1;
            else if(!id || arg>cm_log_length)error=2;
            else {offset=arg;count=cm_log_length-arg;if(count>176)count=176;}
        }
    } else error=2;
    uint32_t fields[19]={1,op,seq,error,s->run_id,s->state,cm_log_length,offset,count,
        s->iterations,CM_CPU_HZ,CM_TIMER_HZ,(uint32_t)(cm_ticks[0]>>32),(uint32_t)cm_ticks[0],
        (uint32_t)(cm_ticks[1]>>32),(uint32_t)cm_ticks[1],s->log_crc,cm_log_overflow,CM_BUILD_ID};
    memcpy(reply,"NCS1",4);for(unsigned i=0;i<19;i++)put(reply+4+4*i,fields[i]);
    if(count)memcpy(reply+80,cm_log+offset,count);
    return 80+count;
}
