#include "face_rpc.h"
#include <string.h>
static uint32_t get32(const uint8_t *p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static void put32(uint8_t *p,uint32_t v){p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v;}
size_t face_rpc_handle(const uint8_t *q,size_t n,uint32_t source,const uint32_t status[FACE_STATUS_WORDS],
 const uint8_t *result,size_t result_bytes,uint32_t owner,uint32_t frame,uint8_t out[256]){
 if(n!=20||memcmp(q,"NFC1",4))return 0;
 uint32_t version=get32(q+4),op=get32(q+8),seq=get32(q+12),requested=get32(q+16),error=0;
 size_t length=20;
 if(version!=1||op<1||op>2||(op==1&&requested))error=1;
 else if(op==1){for(unsigned i=0;i<FACE_STATUS_WORDS;i++)put32(out+20+4*i,status[i]);length+=FACE_STATUS_WORDS*4;}
 else if(!result||result_bytes<32||result_bytes>224)error=2;
 else if(source!=owner)error=3;
 else if(requested!=frame)error=4;
 else{memcpy(out+20,result,result_bytes);length+=result_bytes;}
 memcpy(out,"NFS1",4);put32(out+4,1);put32(out+8,op);put32(out+12,seq);put32(out+16,error);
 return length;
}
