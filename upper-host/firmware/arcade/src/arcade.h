#ifndef NIGO_ARCADE_H
#define NIGO_ARCADE_H
#include "game.h"
enum { ARCADE_MENU, ARCADE_SHOOTER, ARCADE_SNAKE, ARCADE_BREAKOUT, ARCADE_BLOCKS };
typedef struct {
 uint32_t tick,rng,score;int mode,selected,ended,back_hold;
 uint32_t keys,previous,candidate;int debounce[4];
 Game shooter;
 uint16_t snake[504];int snake_len,snake_dir,snake_next,snake_food,snake_clock;
 int paddle,ball_x,ball_y,ball_vx,ball_vy,ball_live,lives,brick_left;
 uint8_t bricks[48],board[180];
 int piece,rotation,px,py,fall_clock,lines,level;
} Arcade;
void arcade_init(Arcade *,uint32_t);
void arcade_step(Arcade *,uint32_t raw_keys);
void arcade_render(const Arcade *,uint8_t *);
void arcade_enter(Arcade *,int mode);
#define ARCADE_RLE_MAX (GAME_W*GAME_H*2)
uint32_t arcade_encode(const uint8_t *,uint8_t *,uint32_t);
uint32_t arcade_crc(const uint8_t *,uint32_t);
void arcade_rect(uint8_t *,int,int,int,int,int);
void arcade_text(uint8_t *,int,int,const char *,int,int);
void arcade_number(uint8_t *,int,int,uint32_t,int,int);
#endif
