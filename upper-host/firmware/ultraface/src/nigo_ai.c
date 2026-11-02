#include "nigo_ai.h"
#include <string.h>
static void fence(void){
#if defined(__riscv)
 __asm__ volatile("fence iorw,iorw" ::: "memory");
#else
 __asm__ volatile("" ::: "memory");
#endif
}
static uint32_t mmio_read(void *p,unsigned r){uint32_t v=*(volatile uint32_t *)((uintptr_t)p+r);fence();return v;}
static void mmio_write(void *p,unsigned r,uint32_t v){fence();*(volatile uint32_t *)((uintptr_t)p+r)=v;fence();}
void nigo_ai_invalidate_shadow(nigo_ai *a){a->known=0;a->bias_known=0;a->multiplier_known=0;a->config_known=0;}
void nigo_ai_bind(nigo_ai *a,void *p,nigo_ai_read_fn r,nigo_ai_write_fn w){memset(a,0,sizeof(*a));a->context=p;a->read=r;a->write=w;}
void nigo_ai_open(nigo_ai *a,uintptr_t b){nigo_ai_bind(a,(void *)b,mmio_read,mmio_write);}
uint32_t nigo_ai_status(nigo_ai *a){return a->read(a->context,0x84);}
uint32_t nigo_ai_completions(nigo_ai *a){return a->read(a->context,0x88);}
void nigo_ai_ack(nigo_ai *a,int error){a->write(a->context,0x80,2u|(error?4u:0u));if(error)nigo_ai_invalidate_shadow(a);}
static void params(nigo_ai *a,unsigned n,const uint32_t *p){a->write(a->context,0x58,n);for(unsigned i=0;i<8;i++)a->write(a->context,0x5c,p[i]);}
int nigo_ai_try_submit(nigo_ai *a,const nigo_ai_job *j){
 if(!j)return -1;
 int q24=(j->word[0]&(1u<<14))!=0;
 if(q24){unsigned m=j->word[0]&7u;if(!(j->q24_config&1u)||(j->q24_config&~7u)||m==1||m==4)return -1;
  for(unsigned i=0;i<8;i++)if(j->multiplier[i]>0xffffffu)return -1;}
 uint32_t s=nigo_ai_status(a);
 if(s&4u){nigo_ai_invalidate_shadow(a);return -2;}if(!(s&8u))return 1;
 if(q24){uint32_t b[8];memcpy(b,j->bias,sizeof(b));
  if(!a->bias_known||memcmp(a->bias,b,sizeof(b))){params(a,0,b);memcpy(a->bias,b,sizeof(b));a->bias_known=1;}
  if(!a->multiplier_known||memcmp(a->multiplier,j->multiplier,sizeof(a->multiplier))){params(a,16,j->multiplier);memcpy(a->multiplier,j->multiplier,sizeof(a->multiplier));a->multiplier_known=1;}
  if(!a->config_known||a->config!=j->q24_config){a->write(a->context,0x60,j->q24_config);a->config=j->q24_config;a->config_known=1;}}
 for(unsigned i=0;i<22;i++)if(!(a->known&(1u<<i))||a->shadow[i]!=j->word[i]){a->write(a->context,i*4,j->word[i]);a->shadow[i]=j->word[i];a->known|=1u<<i;}
 a->write(a->context,0x80,1);return 0; /* never suppress doorbell */
}
uint64_t nigo_ai_counter(nigo_ai *a,unsigned r){uint32_t hi,lo,next;do{hi=a->read(a->context,r+4);lo=a->read(a->context,r);next=a->read(a->context,r+4);}while(hi!=next);return ((uint64_t)hi<<32)|lo;}
