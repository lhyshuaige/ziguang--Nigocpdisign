/* ROM program uploader: NGU1 framing, program kind 3 only. Application kinds 1/2 remain in the original implementation. */
#include "ngu_upload.h"
#include <string.h>
static uint32_t rd(const uint8_t *p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static void wr(uint8_t *p,uint32_t v){p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v;}
uint32_t ngu_crc32(uint32_t crc,const void *data,size_t n){const uint8_t *p=data;while(n--){crc^=*p++;for(unsigned b=0;b<8;b++)crc=(crc>>1)^(0xedb88320u&(0u-(crc&1u)));}return crc;}
void ngu_init(ngu_upload *u,const ngu_sink *s){memset(u,0,sizeof(*u));u->sink=*s;}
void ngu_cancel(ngu_upload *u){if(u->active&&u->sink.abort)u->sink.abort(u->sink.context);u->active=0;u->last_valid=0;}
size_t ngu_handle(ngu_upload *u,uint32_t source,uint16_t port,const uint8_t *p,size_t n,uint8_t ack[NGU_ACK]){
 if(n<NGU_HEADER||n>256||memcmp(p,"NGU1",4)||p[4]!=1)return 0;
 unsigned op=p[5],kind=(unsigned)p[6]<<8|p[7],status=NGU_OK;
 uint32_t session=rd(p+8),sequence=rd(p+12),total=rd(p+16),offset=rd(p+20),crc=rd(p+24),stamp=rd(p+28);
 uint32_t packet_crc=ngu_crc32(0xffffffffu,p,n)^0xffffffffu;
 if(u->last_valid&&source==u->last_source&&port==u->last_port&&session==u->last_session&&sequence==u->last_sequence){
  if(packet_crc==u->last_crc){memcpy(ack,u->last_ack,NGU_ACK);return NGU_ACK;}
  status=NGU_BAD;
 }else if(op==NGU_BEGIN){
  if(n!=NGU_HEADER||offset||kind!=3||total<36||total>NGU_MODEL_MAX+32)status=NGU_SIZE;
  else if(u->active)status=NGU_BUSY;
  else{
   status=(unsigned)u->sink.begin(u->sink.context,kind,total,session,stamp);
   if(status==NGU_OK){u->active=1;u->kind=kind;u->source=source;u->port=port;u->session=session;u->total=total;
    u->offset=0;u->expected_crc=crc;u->running_crc=0xffffffffu;u->timestamp=stamp;}
  }
 }else if(!u->active||source!=u->source||port!=u->port||session!=u->session)status=NGU_OWNER;
 else if(kind!=u->kind||total!=u->total||crc!=u->expected_crc||stamp!=u->timestamp)status=NGU_BAD;
 else if(op==NGU_DATA){
  size_t bytes=n-NGU_HEADER;
  if(!bytes||bytes>NGU_CHUNK||bytes>u->total-u->offset)status=NGU_SIZE;
  else if(offset!=u->offset)status=NGU_ORDER;
  else{u->sink.store(u->sink.context,offset,p+NGU_HEADER,bytes);u->running_crc=ngu_crc32(u->running_crc,p+NGU_HEADER,bytes);u->offset+=(uint32_t)bytes;}
 }else if(op==NGU_COMMIT){
  if(n!=NGU_HEADER||offset!=u->total||u->offset!=u->total)status=NGU_ORDER;
  else if((u->running_crc^0xffffffffu)!=u->expected_crc){status=NGU_CRC;ngu_cancel(u);}
  else{status=(unsigned)u->sink.commit(u->sink.context,u->kind,u->session,u->timestamp);
   if(status!=NGU_OK&&u->sink.abort)u->sink.abort(u->sink.context);
   u->active=0;}
 }else if(op==NGU_ABORT){if(n!=NGU_HEADER)status=NGU_BAD;else ngu_cancel(u);}
 else status=NGU_BAD;
 memcpy(ack,"NGK1",4);ack[4]=1;ack[5]=(uint8_t)op;ack[6]=(uint8_t)(status>>8);ack[7]=(uint8_t)status;
 wr(ack+8,session);wr(ack+12,sequence);wr(ack+16,u->offset);wr(ack+20,u->expected_crc);
 /* Cache only successful operations: BUSY must be re-evaluated on a retry. */
 if(status==NGU_OK){u->last_valid=1;u->last_source=source;u->last_port=port;u->last_session=session;u->last_sequence=sequence;
  u->last_crc=packet_crc;memcpy(u->last_ack,ack,NGU_ACK);}
 return NGU_ACK;
}
