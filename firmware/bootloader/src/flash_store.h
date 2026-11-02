#ifndef NIGO_FLASH_STORE_H
#define NIGO_FLASH_STORE_H
#include "flash.h"
#define NFS_HEADER 256u
#define NFS_SLOT_SIZE UINT32_C(0x400000)
#define NFS_APP_LIMIT UINT32_C(0x200000)
#define NFS_LOAD UINT32_C(0x82000000)
#define NFS_COMMIT UINT32_C(0xc04d17ed)
enum { NFS_APPLICATION=1,NFS_BITSTREAM_ARCHIVE=2 };
typedef struct {unsigned slot,kind;uint32_t generation,size,crc,load,entry;} nfs_image;
uint32_t nfs_crc(uint32_t,const void *,size_t);
int nfs_inspect(flash_device *,unsigned kind,unsigned slot,nfs_image *);
// Always updates the inactive slot. Payload must remain stable until return.
int nfs_install(flash_device *,unsigned kind,const void *,size_t,uint32_t entry,nfs_image *);
// Revalidates CRC while loading; never returns an executable entry on failure.
int nfs_load_application(flash_device *,void *,size_t,uint32_t *entry);
#endif
