#include "mode.h"
#include <string.h>
static uint32_t be(const uint8_t *p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static void put(uint8_t *p,uint32_t v){p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v;}
size_t mode_request(mode_state *s,const uint8_t *p,size_t n,uint32_t peer,uint16_t port,uint8_t *out){
 if(n!=32||memcmp(p,"NMQ1",4))return 0;
 uint32_t op=be(p+8),session=be(p+12),seq=be(p+16),target=be(p+20),generation=be(p+24),error=0;
 if(be(p+4)!=1||!session||be(p+28)||op<1||op>2)error=2;
 else if(op==2){
  if(s->have_last&&s->peer==peer&&s->port==port&&s->session==session&&s->sequence==seq){
   if(target!=s->last_target||generation!=s->last_generation)error=2;
  }else if(target>=MODE_COUNT)error=2;
  else if(generation!=s->generation)error=3; /* stale requests never switch back */
  else if(s->active!=s->target)error=1; /* an accepted transition owns its drain */
  else {
   s->peer=peer;s->port=port;s->session=session;s->sequence=seq;
   s->last_target=target;s->last_generation=generation;s->have_last=1;s->target=target;
  }
 }
 uint32_t v[13]={1,op,session,seq,error,s->active,s->target,s->generation,s->busy,s->flags,s->build,(1u<<MODE_COUNT)-1,0};
 memcpy(out,"NMR1",4);for(unsigned i=0;i<13;i++)put(out+4+4*i,v[i]);return 56;
}
int mode_commit(mode_state *s,int safe,int tx_idle){
 if(s->active==s->target||!safe||!tx_idle)return 0;
 s->active=s->target;s->generation++;s->busy=0;s->flags=0;return 1;
}
