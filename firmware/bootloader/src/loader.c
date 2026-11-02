#include "loader.h"
#include <string.h>

static uint32_t be32(const uint8_t *p) {
    return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];
}
static void put32(uint8_t *p,uint32_t v) {
    p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v;
}
static int begin(void *context,unsigned kind,uint32_t bytes,uint32_t id,uint32_t stamp) {
    ngb_loader *l=context;(void)kind;(void)bytes;(void)id;(void)stamp;
    if(l->execute_pending)return NGU_BUSY;
    l->ready=0; /* A newly accepted download invalidates the previous commit. */
    return NGU_OK;
}
static void store(void *context,uint32_t offset,const uint8_t *p,size_t size) {
    ngb_loader *l=context;memcpy(l->stage+offset,p,size);
}
static void abort_upload(void *context) {
    ngb_loader *l=context;l->ready=0;l->execute_pending=0;
}
static int commit(void *context,unsigned kind,uint32_t id,uint32_t stamp) {
    ngb_loader *l=context;const uint8_t *h=l->stage;(void)kind;(void)stamp;
    uint32_t bytes=be32(h+16),entry=be32(h+12),crc=be32(h+20);
    if(memcmp(h,"NGB1",4)||be32(h+4)!=1||be32(h+8)!=NGB_LOAD||
       be32(h+24)||be32(h+28)||bytes<4||bytes>NGB_LIMIT||
       l->upload.total!=NGB_HEADER+bytes||entry<NGB_LOAD||
       entry-NGB_LOAD>bytes-4||(entry&3u))return NGU_BAD;
    if((ngu_crc32(UINT32_C(0xffffffff),h+NGB_HEADER,bytes)^UINT32_C(0xffffffff))!=crc)return NGU_CRC;
    memcpy(l->destination,h+NGB_HEADER,bytes);
    /* Drain the Nax write-back D-cache before publishing READY or allowing fetch. */
    if(l->publish)l->publish(l->publish_context);
    l->entry=entry;l->payload_bytes=bytes;l->payload_crc=crc;
    l->image_source=l->incoming_source;l->image_port=l->incoming_port;l->image_session=id;
    l->ready=1;
    return NGU_OK;
}
void ngb_init(ngb_loader *l,uint8_t *stage,uint8_t *destination,
              void (*publish)(void *),void *context) {
    memset(l,0,sizeof(*l));l->stage=stage;l->destination=destination;
    l->publish=publish;l->publish_context=context;
    ngu_sink sink={begin,store,commit,abort_upload,l};ngu_init(&l->upload,&sink);
}
size_t ngb_upload(ngb_loader *l,uint32_t source,uint16_t port,const uint8_t *p,size_t size,uint8_t ack[NGU_ACK]) {
    l->incoming_source=source;l->incoming_port=port;
    return ngu_handle(&l->upload,source,port,p,size,ack);
}
void ngb_cancel(ngb_loader *l) {
    ngu_cancel(&l->upload);l->ready=0;l->execute_pending=0;
}
size_t ngb_control(ngb_loader *l,uint32_t source,uint16_t port,const uint8_t *p,
                   size_t size,uint8_t reply[NGB_REPLY],uint32_t now) {
    if(size!=NGB_CONTROL||memcmp(p,"NGBX",4))return 0;
    uint32_t op=be32(p+8),session=be32(p+12),seq=be32(p+16),status=NGU_OK;
    if(be32(p+4)!=1||be32(p+20)||(op!=NGB_QUERY&&op!=NGB_EXECUTE))status=NGU_BAD;
    else if(op==NGB_EXECUTE) {
        if(!l->ready||l->upload.active)status=NGU_BUSY;
        else if(source!=l->image_source||port!=l->image_port||session!=l->image_session)status=NGU_OWNER;
        else if(l->execute_pending&&seq!=l->execute_sequence)status=NGU_BUSY;
        else if(!l->execute_pending) {
            l->execute_pending=1;l->execute_sequence=seq;l->execute_deadline=now+NGB_EXECUTE_GRACE_MS;
        }
    }
    memcpy(reply,"NGBR",4);put32(reply+4,1);put32(reply+8,op);put32(reply+12,status);
    put32(reply+16,session);put32(reply+20,seq);
    put32(reply+24,l->ready?l->entry:0);put32(reply+28,l->ready?l->payload_crc:0);
    return NGB_REPLY;
}
int ngb_jump_due(const ngb_loader *l,uint32_t now) {
    return l->ready&&l->execute_pending&&(int32_t)(now-l->execute_deadline)>=0;
}
