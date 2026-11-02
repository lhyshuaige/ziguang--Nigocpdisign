#include "arcade.h"
static Arcade a;static uint8_t frame[GAME_W*GAME_H];
void sim_init(void){arcade_init(&a,0x4e49474f);}
void sim_step(uint32_t keys){arcade_step(&a,keys);}
void sim_enter(int mode){arcade_enter(&a,mode);}
const uint8_t *sim_frame(void){arcade_render(&a,frame);return frame;}
const uint32_t *sim_palette(void){return game_palette;}
uint32_t sim_value(int field){switch(field){case 0:return (uint32_t)a.mode;case 1:return (uint32_t)a.selected;case 2:return a.keys;case 3:return a.score;default:return game_hash((const uint8_t *)&a,sizeof a);}}
