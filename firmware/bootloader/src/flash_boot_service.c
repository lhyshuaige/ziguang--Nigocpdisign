#include "flash_boot_service.h"
#include "flash_store.h"
#include <string.h>
static uint32_t get32(const uint8_t *p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static void put32(uint8_t *p,uint32_t v){p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v;}
static uint8_t cached_reply[NGB_REPLY];
static uint32_t last_peer,last_session,last_sequence;static uint16_t last_port;static int cached;
size_t flash_install_request(ngb_loader *l,uint32_t peer,uint16_t port,const uint8_t *p,size_t size,uint8_t *reply) {
 if(size!=NGB_CONTROL || memcmp(p,"NGBX",4) || get32(p+8)!=3)return 0;
 uint32_t session=get32(p+12),sequence=get32(p+16),status=0;
 // Retries of the same save request never cause a second erase/program pass.
 if(cached&&peer==last_peer&&port==last_port&&session==last_session&&sequence==last_sequence) {
  memcpy(reply,cached_reply,NGB_REPLY);return NGB_REPLY;
 }
 if(get32(p+4)!=1 || get32(p+20))status=1;
 else if(!l->ready||l->upload.active||l->execute_pending)status=2;
 else if(peer!=l->image_source || port!=l->image_port || session!=l->image_session)status=3;
 else {
  flash_device device;flash_open_mmio(&device);
  if(nfs_install(&device,NFS_APPLICATION,l->destination,l->payload_bytes,l->entry,0))status=8;
 }
 memcpy(reply,"NGBR",4);put32(reply+4,1);put32(reply+8,3);put32(reply+12,status);
 put32(reply+16,session);put32(reply+20,sequence);put32(reply+24,l->ready?l->entry:0);put32(reply+28,l->ready?l->payload_crc:0);
 memcpy(cached_reply,reply,NGB_REPLY);cached=1;
 last_peer=peer;last_port=port;last_session=session;last_sequence=sequence;
 return NGB_REPLY;
}
