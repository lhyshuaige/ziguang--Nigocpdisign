#include "flash.h"
static void fence(void) { __asm__ volatile("fence iorw,iorw" ::: "memory"); }
static uint32_t rd(void *context,unsigned offset) {
 uint32_t v=*(volatile uint32_t *)((uintptr_t)context+offset);fence();return v;
}
static void wr(void *context,unsigned offset,uint32_t value) {
 fence();*(volatile uint32_t *)((uintptr_t)context+offset)=value;fence();
}
static uint64_t ticks(void *context) {
 (void)context;uint32_t h,l,next;
 do {h=*(volatile uint32_t *)0x1000000cu;l=*(volatile uint32_t *)0x10000008u;
     next=*(volatile uint32_t *)0x1000000cu;}while(h!=next);
 return (uint64_t)h<<32|l;
}
void flash_open_mmio(flash_device *d) {
 d->context=(void *)(uintptr_t)FLASH_CSR;d->read=rd;d->write=wr;d->ticks=ticks;
 d->timeout_ticks=UINT64_C(1000000000);d->ticket=0;
}
