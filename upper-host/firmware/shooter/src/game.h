#ifndef NIGO_SHOOTER_GAME_H
#define NIGO_SHOOTER_GAME_H
#include <stdint.h>
#define GAME_W 320
#define GAME_H 240
#define GAME_BULLETS 96
#define GAME_ENEMIES 12
#define GAME_PARTICLES 40
#define KEY_UP 1u
#define KEY_DOWN 2u
#define KEY_LEFT 4u
#define KEY_RIGHT 8u
enum { TITLE, WAVES, BOSS, VICTORY, GAME_OVER };
typedef struct { int32_t x,y,vx,vy; int16_t life,kind,hp; } Entity;
typedef struct {
 uint32_t tick,rng,score,kills,shots,hits,phase_seen;
 int32_t x,y;
 int32_t state,hp,power,invulnerable,cooldown,spawned,wave_tick;
 int32_t boss_x,boss_y,boss_hp,boss_phase,boss_tick,shake,restart_hold;
 Entity bullets[GAME_BULLETS],enemies[GAME_ENEMIES],particles[GAME_PARTICLES],pickup;
} Game;
void game_init(Game *,uint32_t seed);
void game_start(Game *);
void game_step(Game *,uint32_t keys);
void game_render(const Game *,uint8_t *pixels);
uint32_t game_hash(const uint8_t *,uint32_t);
uint32_t game_state_hash(const Game *);
extern const uint32_t game_palette[32];
#endif
