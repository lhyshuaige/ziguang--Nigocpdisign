#include "nigo_ai.h"
#include "ngu_upload.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint8_t storage[NGU_FRAME_BYTES];
static unsigned begins,stores,published,aborts,sink_busy;
static int begin(void *p,unsigned k,uint32_t n,uint32_t id,uint32_t t){(void)p;(void)k;(void)n;(void)id;(void)t;if(sink_busy)return NGU_BUSY;begins++;return 0;}
static void store(void *p,uint32_t off,const uint8_t *d,size_t n){(void)p;stores++;memcpy(storage+off,d,n);}
static int commit(void *p,unsigned k,uint32_t id,uint32_t t){(void)p;(void)k;(void)id;(void)t;published++;return 0;}
static void abort_blob(void *p){(void)p;aborts++;}
static void put(uint8_t *p,uint32_t v){p[0]=v>>24;p[1]=v>>16;p[2]=v>>8;p[3]=v;}
static void packet(uint8_t *p,unsigned op,uint32_t seq,uint32_t off){
 memset(p,0,256);memcpy(p,"NGU1",4);p[4]=1;p[5]=op;p[7]=1;
 put(p+8,77);put(p+12,seq);put(p+16,9);put(p+20,off);put(p+24,0xcbf43926);put(p+28,100);
}
static unsigned status(const uint8_t *p){return (unsigned)p[6]<<8|p[7];}
static void test_upload(void){
 ngu_upload u;ngu_sink sink={begin,store,commit,abort_blob,0};ngu_init(&u,&sink);
 uint8_t p[256],ack[24],saved[24];assert((ngu_crc32(0xffffffff,"123456789",9)^0xffffffff)==0xcbf43926);
 packet(p,1,1,0);sink_busy=1;assert(ngu_handle(&u,1,5001,p,32,ack)==24&&status(ack)==NGU_BUSY);
 sink_busy=0;ngu_handle(&u,1,5001,p,32,ack);assert(!status(ack)&&begins==1);
 ngu_handle(&u,1,5001,p,32,ack);assert(!status(ack)&&begins==1); /* lost BEGIN ACK */
 packet(p,2,2,0);memcpy(p+32,"1234",4);ngu_handle(&u,1,5001,p,36,ack);
 assert(!status(ack)&&stores==1&&published==0);memcpy(saved,ack,24);
 ngu_handle(&u,1,5001,p,36,ack);assert(!memcmp(saved,ack,24)&&stores==1); /* lost DATA ACK */
 p[32]='x';ngu_handle(&u,1,5001,p,36,ack);assert(status(ack)==NGU_BAD&&stores==1);
 packet(p,2,3,8);p[32]='9';ngu_handle(&u,1,5001,p,33,ack);assert(status(ack)==NGU_ORDER);
 packet(p,2,3,4);memcpy(p+32,"56789",5);ngu_handle(&u,2,5001,p,37,ack);assert(status(ack)==NGU_OWNER);
 ngu_handle(&u,1,5001,p,37,ack);assert(!status(ack)&&stores==2&&published==0);
 packet(p,3,4,9);ngu_handle(&u,1,5001,p,32,ack);assert(!status(ack)&&published==1&&!memcmp(storage,"123456789",9));
 ngu_handle(&u,1,5001,p,32,ack);assert(!status(ack)&&published==1); /* lost COMMIT ACK */
 packet(p,1,5,0);ngu_handle(&u,1,5001,p,32,ack);
 packet(p,2,6,0);memcpy(p+32,"123456780",9);ngu_handle(&u,1,5001,p,41,ack);
 packet(p,3,7,9);ngu_handle(&u,1,5001,p,32,ack);assert(status(ack)==NGU_CRC&&published==1&&aborts==1);
 packet(p,1,8,0);ngu_handle(&u,1,5001,p,32,ack);ngu_cancel(&u);assert(aborts==2&&!u.active);
 puts("NGU_RETRY_DUPLICATE_ORDER_OWNERSHIP_CRC_ATOMIC_COMMIT_PASS");
}
typedef struct {uint32_t status,words[22],bias[8],mult[8],index,config,doorbells,writes;} device;
static uint32_t read_reg(void *p,unsigned off){device *d=p;return off==0x84?d->status:0;}
static void write_reg(void *p,unsigned off,uint32_t v){device *d=p;d->writes++;
 if(off<88)d->words[off/4]=v;
 else if(off==0x58)d->index=v;
 else if(off==0x5c){if(d->index&16)d->mult[d->index&7]=v;else d->bias[d->index&7]=v;d->index++;}
 else if(off==0x60)d->config=v;
 else if(off==0x80){if(v&1)d->doorbells++;if(v&4)d->status&=~4u;}
}
static void test_driver(void){
 device d={0};d.status=8;nigo_ai a;nigo_ai_bind(&a,&d,read_reg,write_reg);
 nigo_ai_job j={0};j.word[0]=3|(1u<<14);j.q24_config=3;
 for(unsigned i=0;i<8;i++){j.bias[i]=-(int)i;j.multiplier[i]=0x800000+i;}
 assert(!nigo_ai_try_submit(&a,&j));assert(d.doorbells==1&&d.config==3&&d.bias[7]==(uint32_t)-7&&d.mult[7]==0x800007);
 uint32_t writes=d.writes;assert(!nigo_ai_try_submit(&a,&j));assert(d.writes==writes+1&&d.doorbells==2);
 d.status=0;writes=d.writes;assert(nigo_ai_try_submit(&a,&j)==1&&d.writes==writes);
 d.status=12;assert(nigo_ai_try_submit(&a,&j)==-2&&d.writes==writes);nigo_ai_ack(&a,1);
 writes=d.writes;assert(!nigo_ai_try_submit(&a,&j)&&d.writes-writes==42); /* 19 sideband +22 staging +doorbell */
 j.multiplier[0]=0x1000000;writes=d.writes;assert(nigo_ai_try_submit(&a,&j)==-1&&d.writes==writes);
 puts("CPU_AI_Q24_STAGING_CACHE_QUEUE_BACKPRESSURE_ERROR_RECOVERY_PASS");
}
int main(void){test_upload();test_driver();return 0;}
