#include "mode.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void put(uint8_t *p,uint32_t v){p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v;}
static uint32_t get(const uint8_t *p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
int main(void){
 mode_state s={0};uint8_t p[32]={0},reply[56];memcpy(p,"NMQ1",4);put(p+4,1);put(p+8,2);put(p+12,19);put(p+16,1);put(p+20,MODE_AI);
 assert(mode_request(&s,p,32,100,200,reply)==56);assert(!get(reply+20)&&s.active==0&&s.target==MODE_AI);
 assert(!mode_commit(&s,0,1));assert(!mode_commit(&s,1,0));assert(mode_commit(&s,1,1));assert(s.generation==1);
 assert(mode_request(&s,p,32,100,200,reply)==56&&!get(reply+20));assert(!mode_commit(&s,1,1));
 put(p+20,MODE_GAME);mode_request(&s,p,32,100,200,reply);assert(get(reply+20)==2); /* changed duplicate */
 put(p+16,2);mode_request(&s,p,32,100,200,reply);assert(get(reply+20)==3); /* stale generation */
 put(p+24,1);mode_request(&s,p,32,100,200,reply);assert(!get(reply+20));
 put(p+16,3);mode_request(&s,p,32,101,201,reply);assert(get(reply+20)==1);assert(s.target==MODE_GAME);
 s.busy=MODE_BUSY_AI;put(p+8,1);mode_request(&s,p,32,101,201,reply);assert(get(reply+36)==MODE_BUSY_AI&&s.target==MODE_GAME);
 assert(!mode_commit(&s,0,1));assert(mode_commit(&s,1,1));assert(s.active==MODE_GAME&&s.generation==2);
 put(p+8,2);put(p+20,MODE_COUNT);put(p+24,2);mode_request(&s,p,32,101,201,reply);assert(get(reply+20)==2);
 assert(!mode_request(&s,p,31,100,200,reply));
 for(unsigned round=0;round<1000;round++){put(p+16,round+10);put(p+20,round%MODE_COUNT);put(p+24,s.generation);mode_request(&s,p,32,100,200,reply);assert(!get(reply+20));mode_commit(&s,1,1);assert(s.active==round%MODE_COUNT);}
 puts("MODE_STATE_PASS deferred DMA/TX drain, lost-ACK duplicate, stale generation, conflicting request, all six modes x1000");return 0;
}
