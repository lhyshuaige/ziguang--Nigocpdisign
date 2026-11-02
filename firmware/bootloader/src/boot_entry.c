#include "flash_store.h"
extern void nigo_network_main(void);
extern void ngb_jump(uint32_t) __attribute__((noreturn));
// The existing top releases the CPU only after DDR calibration.
void nigo_application_main(void) {
 flash_device device;flash_open_mmio(&device);
 // Hold KEY1 through reset to enter the existing network recovery loader.
 if(!(*(volatile uint32_t *)0x10000004u&1u)) {
  uint32_t entry=0;
  if(!nfs_load_application(&device,(void *)(uintptr_t)NFS_LOAD,NFS_APP_LIMIT,&entry)) {
   // ngb_jump performs Nax D-cache flush, ordering fence and FENCE.I.
   ngb_jump(entry);
  }
 }
 nigo_network_main();
 for(;;){}
}
