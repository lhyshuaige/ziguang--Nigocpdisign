#include "flash_store.h"
#include <string.h>
static uint32_t be32(const uint8_t *p) {return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static void put32(uint8_t *p,uint32_t v){p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v;}
uint32_t nfs_crc(uint32_t crc,const void *buffer,size_t size) {
 const uint8_t *p=buffer;
 while(size--) {crc^=*p++;for(unsigned b=0;b<8;b++)crc=(crc>>1)^((crc&1u)?UINT32_C(0xedb88320):0);}
 return crc;
}
static unsigned chip(unsigned kind){return kind==NFS_APPLICATION?1u:0u;}
static uint32_t base(unsigned slot){return FLASH_WRITE_FLOOR+slot*NFS_SLOT_SIZE;}
static int valid_kind(unsigned kind){return kind==NFS_APPLICATION||kind==NFS_BITSTREAM_ARCHIVE;}
static int newer(uint32_t a,uint32_t b){return (int32_t)(a-b)>0;}
static int header(flash_device *d,unsigned kind,unsigned slot,nfs_image *im) {
 uint8_t h[NFS_HEADER];if(!valid_kind(kind)||slot>1)return -1;
 int rc=flash_read(d,chip(kind),base(slot),h,sizeof h);if(rc)return rc;
 if(memcmp(h,"NGF1",4)||be32(h+4)!=1||be32(h+8)!=kind||be32(h+252)!=NFS_COMMIT||
    (nfs_crc(UINT32_MAX,h,32)^UINT32_MAX)!=be32(h+32))return -3;
 for(unsigned i=36;i<252;i++)if(h[i]!=255)return -3;
 *im=(nfs_image){slot,kind,be32(h+12),be32(h+16),be32(h+20),be32(h+24),be32(h+28)};
 if(im->size<4 || im->size>NFS_SLOT_SIZE-NFS_HEADER)return -3;
 if(kind==NFS_APPLICATION && (im->size>NFS_APP_LIMIT||im->load!=NFS_LOAD||
    im->entry<NFS_LOAD||im->entry-NFS_LOAD>im->size-4||(im->entry&3u)))return -3;
 if(kind==NFS_BITSTREAM_ARCHIVE && (im->load||im->entry))return -3;
 return 0;
}
static int verify(flash_device *d,const nfs_image *im,void *destination) {
 uint8_t buf[256];uint32_t crc=UINT32_MAX;
 for(uint32_t off=0;off<im->size;) {
  size_t n=im->size-off;if(n>sizeof buf)n=sizeof buf;
  int rc=flash_read(d,chip(im->kind),base(im->slot)+NFS_HEADER+off,buf,n);if(rc)return rc;
  crc=nfs_crc(crc,buf,n);
  if(destination)memcpy((uint8_t *)destination+off,buf,n);
  off+=(uint32_t)n;
 }
 return (crc^UINT32_MAX)==im->crc?0:-4;
}
int nfs_inspect(flash_device *d,unsigned kind,unsigned slot,nfs_image *im) {
 int rc=header(d,kind,slot,im);return rc?rc:verify(d,im,0);
}
int nfs_install(flash_device *d,unsigned kind,const void *payload,size_t size,uint32_t entry,nfs_image *installed) {
 if(!valid_kind(kind)||size<4||size>NFS_SLOT_SIZE-NFS_HEADER)return -1;
 if(kind==NFS_APPLICATION && (size>NFS_APP_LIMIT||entry<NFS_LOAD||entry-NFS_LOAD>size-4||(entry&3u)))return -1;
 if(kind==NFS_BITSTREAM_ARCHIVE && entry)return -1;
 // Standard-SPI profiles checked against manufacturer datasheets:
 // W25Q128JV EF4018/EF7018; XT25BF128F-W Rev1.1 Table5: 0B4018.
 uint32_t id;int probe=flash_command(d,chip(kind),FLASH_ID,0,&id);
 if(probe)return probe;
 if(id!=UINT32_C(0xef4018) && id!=UINT32_C(0xef7018) && id!=UINT32_C(0x0b4018))return -6;
 nfs_image old[2];int a=nfs_inspect(d,kind,0,&old[0]),b=nfs_inspect(d,kind,1,&old[1]);
 // I/O/timeout errors are not evidence that a slot is empty. Never erase on uncertainty.
 if((a&&a!=-3&&a!=-4)||(b&&b!=-3&&b!=-4))return -5;
 unsigned target;uint32_t generation;
 if(!a && !b){unsigned newest=newer(old[1].generation,old[0].generation)?1u:0u;target=1u-newest;generation=old[newest].generation+1;}
 else if(!a){target=1;generation=old[0].generation+1;}
 else if(!b){target=0;generation=old[1].generation+1;}
 else {target=0;generation=1;}
 uint32_t crc=nfs_crc(UINT32_MAX,payload,size)^UINT32_MAX;
 uint8_t h[NFS_HEADER];memset(h,255,sizeof h);memcpy(h,"NGF1",4);
 put32(h+4,1);put32(h+8,kind);put32(h+12,generation);put32(h+16,(uint32_t)size);
 put32(h+20,crc);put32(h+24,kind==NFS_APPLICATION?NFS_LOAD:0);put32(h+28,entry);
 put32(h+32,nfs_crc(UINT32_MAX,h,32)^UINT32_MAX);
 // Erase only the target's used sectors. Header/commit sector is always erased first.
 size_t erase_bytes=(NFS_HEADER+size+4095u)&~(size_t)4095u;
 int rc=flash_erase(d,chip(kind),base(target),erase_bytes);if(rc)return rc;
 rc=flash_program(d,chip(kind),base(target),h,252);if(rc)return rc;
 size_t whole=size&~(size_t)3u;
 rc=flash_program(d,chip(kind),base(target)+NFS_HEADER,payload,whole);if(rc)return rc;
 if(size!=whole) {
  uint8_t tail[4]={255,255,255,255};memcpy(tail,(const uint8_t *)payload+whole,size-whole);
  rc=flash_program(d,chip(kind),base(target)+NFS_HEADER+(uint32_t)whole,tail,4);if(rc)return rc;
 }
 nfs_image next={target,kind,generation,(uint32_t)size,crc,kind==NFS_APPLICATION?NFS_LOAD:0,entry};
 rc=verify(d,&next,0);if(rc)return rc;
 // Commit marker is programmed last, after complete readback. Header CRC is checked too.
 uint8_t check[252];rc=flash_read(d,chip(kind),base(target),check,sizeof check);if(rc)return rc;
 if(memcmp(check,h,sizeof check))return -4;
 uint8_t commit[4];put32(commit,NFS_COMMIT);
 rc=flash_program(d,chip(kind),base(target)+252,commit,4);if(rc)return rc;
 rc=nfs_inspect(d,kind,target,&next);if(rc)return rc;
 if(installed)*installed=next;
 return 0;
}
int nfs_load_application(flash_device *d,void *destination,size_t capacity,uint32_t *entry) {
 *entry=0;nfs_image im[2];int rc[2]={header(d,1,0,&im[0]),header(d,1,1,&im[1])};
 unsigned first=(!rc[1]&&(rc[0]||newer(im[1].generation,im[0].generation)))?1u:0u;
 for(unsigned i=0;i<2;i++) {
  unsigned s=first^i;
  if(!rc[s] && im[s].size<=capacity && !verify(d,&im[s],destination)){*entry=im[s].entry;return 0;}
 }
 return -3;
}
