#ifndef NIGO_FLASH_H
#define NIGO_FLASH_H
#include <stdint.h>
#include <stddef.h>
#define FLASH_CSR UINT32_C(0x10001000)
#define FLASH_CAPACITY UINT32_C(0x1000000)
#define FLASH_WRITE_FLOOR UINT32_C(0x800000)
enum { FLASH_ADDR=1,FLASH_READ=2,FLASH_PROGRAM=3,FLASH_ERASE=4,FLASH_ID=5,FLASH_STATUS=6,
       FLASH_PAGE_BEGIN=7,FLASH_PAGE_DATA=8,FLASH_PAGE_ABORT=9 };
typedef struct {
 void *context;
 uint32_t (*read)(void *,unsigned);
 void (*write)(void *,unsigned,uint32_t);
 uint64_t (*ticks)(void *);
 uint64_t timeout_ticks;
 uint8_t ticket;
} flash_device;
void flash_open_mmio(flash_device *);
int flash_command(flash_device *,unsigned chip,unsigned op,uint32_t tx,uint32_t *rx);
int flash_read(flash_device *,unsigned chip,uint32_t offset,void *,size_t);
// Arbitrary byte address/length; splits at 256B pages and verifies every chunk.
// Caller erases sectors first when 0->1 transitions are needed; returns -4 if
// the requested bytes need erase, -5 if post-program readback differs.
int flash_program(flash_device *,unsigned chip,uint32_t offset,const void *,size_t);
int flash_erase(flash_device *,unsigned chip,uint32_t offset,size_t);
#endif
