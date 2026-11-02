#include "flash.h"
static int range(uint32_t offset,size_t size) {
 return offset<FLASH_CAPACITY && size<=FLASH_CAPACITY-offset;
}
int flash_command(flash_device *d,unsigned chip,unsigned op,uint32_t tx,uint32_t *rx) {
 if(chip>1 || op<1 || op>9)return -1;
 uint64_t start=d->ticks(d->context);
 while(d->read(d->context,4)&1u)
  if(d->ticks(d->context)-start>=d->timeout_ticks)return -2;
 // Resynchronise with hardware after a software restart, including ticket wrap.
 d->ticket=(uint8_t)((d->read(d->context,4)>>24)+1u);
 d->write(d->context,8,tx);
 d->write(d->context,0,(uint32_t)d->ticket | op<<8 | chip<<16);
 for(;;) {
  uint32_t s=d->read(d->context,4);
  if((s>>24)==d->ticket && (s&3u)==2u) {
   if(s&4u)return -(int)(16u+((s>>4)&15u));
   if(rx)*rx=d->read(d->context,12);
   return 0;
  }
  if(d->ticks(d->context)-start>=d->timeout_ticks)return -2;
 }
}
int flash_read(flash_device *d,unsigned chip,uint32_t offset,void *buffer,size_t size) {
 uint8_t *p=buffer;if(chip>1 || !range(offset,size))return -1;
 if(!size)return 0;
 uint32_t aligned=offset&~3u;
 int rc=flash_command(d,chip,FLASH_ADDR,aligned,0);if(rc)return rc;
 while(size) {
  uint32_t word;rc=flash_command(d,chip,FLASH_READ,0,&word);if(rc)return rc;
  for(unsigned i=offset&3u;i<4 && size;i++,offset++,size--)*p++=(uint8_t)(word>>(8*i));
 }
 return 0;
}
int flash_program(flash_device *d,unsigned chip,uint32_t offset,const void *buffer,size_t size) {
 const uint8_t *p=buffer;
 if(chip>1 || offset<FLASH_WRITE_FLOOR || !range(offset,size))return -1;
 uint8_t page[256],verify[256]; // CPU RAM only; no RTL page RAM.
 while(size) {
  size_t n=256u-(offset&255u);if(n>size)n=size;
  for(size_t i=0;i<n;i++)page[i]=p[i];
  int rc=flash_read(d,chip,offset,verify,n);if(rc)return rc;
  // NOR program cannot set a 0 bit back to 1. Do not silently destroy data;
  // sector erase remains an explicit caller operation (A/B store already does it).
  for(size_t i=0;i<n;i++)if((verify[i]&page[i])!=page[i])return -4;
  rc=flash_command(d,chip,FLASH_ADDR,offset,0);if(rc)return rc;
  rc=flash_command(d,chip,FLASH_PAGE_BEGIN,(uint32_t)n,0);if(rc)return rc;
  for(size_t at=0;at<n;at+=4) {
   uint32_t word=UINT32_MAX;
   for(unsigned b=0;b<4 && at+b<n;b++)word=(word&~(UINT32_C(255)<<(8*b)))|((uint32_t)page[at+b]<<(8*b));
   rc=flash_command(d,chip,FLASH_PAGE_DATA,word,0);
   if(rc){(void)flash_command(d,chip,FLASH_PAGE_ABORT,0,0);return rc;}
  }
  rc=flash_read(d,chip,offset,verify,n);if(rc)return rc;
  for(size_t i=0;i<n;i++)if(verify[i]!=page[i])return -5;
  offset+=(uint32_t)n;p+=n;size-=n;
 }
 return 0;
}
int flash_erase(flash_device *d,unsigned chip,uint32_t offset,size_t size) {
 if(chip>1 || offset<FLASH_WRITE_FLOOR || !range(offset,size) || (offset&4095u) || (size&4095u))return -1;
 for(size_t n=0;n<size;n+=4096) {
  int rc=flash_command(d,chip,FLASH_ADDR,offset+(uint32_t)n,0);if(rc)return rc;
  rc=flash_command(d,chip,FLASH_ERASE,0,0);if(rc)return rc;
 }
 return 0;
}
