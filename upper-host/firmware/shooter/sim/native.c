#include "game.h"
#include "scenarios.h"
static Game g;
static uint8_t pixels[GAME_W*GAME_H];
void sim_init(uint32_t seed){game_init(&g,seed);}
void sim_step(uint32_t keys){game_step(&g,keys);}
const uint8_t *sim_frame(void){game_render(&g,pixels);return pixels;}
const uint32_t *sim_palette(void){return game_palette;}
void sim_scenario(int i){scenario(&g,i);}
uint32_t sim_value(int field){switch(field){case 0:return (uint32_t)g.state;case 1:return g.score;case 2:return (uint32_t)g.hp;case 3:return (uint32_t)g.boss_phase;case 4:return g.tick;default:return game_state_hash(&g);}}
