#include "game.h"
#include "scenarios.h"
#define MMIO(a) (*(volatile uint32_t *)(uintptr_t)(a))
static Game g;
void nigo_application_main(void){
 volatile uint32_t *report=(volatile uint32_t *)(uintptr_t)0x82900000;
 const uint32_t masks[8]={1,2,4,8,5,10,0,12};
 for(int i=0;i<32;i++)report[i]=0;
 game_init(&g,0x1234abcd);game_start(&g);
 for(int i=0;i<8;i++){
  MMIO(0x10000000)=0x80u+(uint32_t)i;
  unsigned wait=0;while((MMIO(0x10000004)&15)!=masks[i])if(++wait>100000){MMIO(0x10000000)=0xef;for(;;){}}
  for(int j=0;j<12;j++)game_step(&g,MMIO(0x10000004)&15);
  report[2+i]=game_state_hash(&g);
 }
 for(int i=0;i<4;i++){
  uint8_t *frame=(uint8_t *)(uintptr_t)(0x82910000u+(uint32_t)i*0x14000u);
  scenario(&g,i);game_render(&g,frame);
  report[16+i*2]=game_state_hash(&g);report[17+i*2]=game_hash(frame,GAME_W*GAME_H);
  MMIO(0x10000000)=0x90u+(uint32_t)i;
 }
 report[1]=4;report[0]=0x4e475347;
 __asm__ volatile("fence iorw,iorw\n.word 0x0000500f\nfence iorw,iorw" ::: "memory");
 MMIO(0x10000000)=0x7e;
 for(;;){}
}
