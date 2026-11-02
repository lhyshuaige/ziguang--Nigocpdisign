#include "benchmark.h"
#include "service.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#ifdef main
#undef main
#endif
static void put(unsigned char *p,unsigned v){p[0]=v>>24;p[1]=v>>16;p[2]=v>>8;p[3]=v;}
static unsigned be(const unsigned char *p){return (unsigned)p[0]<<24|(unsigned)p[1]<<16|(unsigned)p[2]<<8|p[3];}
int main(void) {
    cm_service s={0};unsigned char p[24]={0},r[256];
    memcpy(p,"NCQ1",4);put(p+4,1);put(p+8,2);put(p+12,7);put(p+16,42);
    assert(cm_request(&s,p,23,r)==0);
    assert(cm_request(&s,p,24,r)==80 && !be(r+16) && s.state==1);
    assert(cm_request(&s,p,24,r)==80 && !be(r+16) && s.run_id==42);
    put(p+16,43);cm_request(&s,p,24,r);assert(be(r+16)==1 && s.run_id==42);
    put(p+16,42);put(p+20,1);cm_request(&s,p,24,r);assert(be(r+16)==2);
    cm_run(1); /* Functional native check; intentionally too short for a score. */
    assert(!cm_log_overflow);
    assert(strstr(cm_log,"seedcrc          : 0xe9f5"));
    assert(strstr(cm_log,"seedcrc          : 0x18f2"));
    assert(strstr(cm_log,"[0]crclist       : 0xe714"));
    assert(strstr(cm_log,"[0]crclist       : 0xe3c1"));
    assert(strstr(cm_log,"[0]crcmatrix     : 0x1fd7"));
    assert(strstr(cm_log,"[0]crcmatrix     : 0x0747"));
    assert(strstr(cm_log,"[0]crcstate      : 0x8e3a"));
    assert(strstr(cm_log,"[0]crcstate      : 0x8d84"));
    assert(strstr(cm_log,"ERROR! Must execute for at least 10 secs"));
    assert(!strstr(cm_log,"ERROR! list") && !strstr(cm_log,"ERROR! matrix") && !strstr(cm_log,"ERROR! state"));
    s.state=2;s.log_crc=cm_crc32(cm_log,cm_log_length);
    assert(cm_crc32("123456789",9)==0xcbf43926u);
    put(p+20,0);cm_request(&s,p,24,r);assert(s.state==2); /* Duplicate START never re-runs. */
    put(p+8,3);size_t n=cm_request(&s,p,24,r);
    assert(n==256 && be(r+36)==176 && !memcmp(r+80,cm_log,176));
    put(p+20,cm_log_length+1);cm_request(&s,p,24,r);assert(be(r+16)==2);
    put(p+8,1);put(p+16,999);cm_request(&s,p,24,r);assert(be(r+16)==3);
    puts(cm_log);puts("NATIVE_FUNCTIONAL_AND_RPC_PASS (not a board score)");return 0;
}
