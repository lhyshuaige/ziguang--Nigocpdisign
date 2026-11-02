#include "game.h"
#include "scenarios.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static Game g,other;
static uint8_t guarded[GAME_W*GAME_H+32];
static void fresh(void){game_init(&g,123);game_start(&g);g.cooldown=100;}
static void projectile(Entity *e,int x,int y,int kind){memset(e,0,sizeof(*e));e->life=20;e->x=x;e->y=y;e->kind=(int16_t)kind;}
int main(void){
 game_init(&g,123);assert(g.state==TITLE);game_step(&g,KEY_UP);assert(g.state==WAVES);
 fresh();int x=g.x,y=g.y;game_step(&g,KEY_UP);assert(g.y<y&&g.x==x);
 game_step(&g,KEY_DOWN);assert(g.y==y);game_step(&g,KEY_LEFT);assert(g.x<x);game_step(&g,KEY_RIGHT);assert(g.x==x);
 game_step(&g,KEY_LEFT|KEY_RIGHT);assert(g.x==x);
 g.invulnerable=10000;for(int i=0;i<300;i++)game_step(&g,KEY_LEFT|KEY_UP);assert(g.x==12*256&&g.y==48*256);
 for(int i=0;i<300;i++)game_step(&g,KEY_RIGHT|KEY_DOWN);assert(g.x==308*256&&g.y==225*256);
 fresh();g.cooldown=0;game_step(&g,0);assert(g.shots==1);for(int i=0;i<8;i++)game_step(&g,0);assert(g.shots==1);game_step(&g,0);assert(g.shots==2);
 fresh();g.wave_tick=10;Entity *e=&g.enemies[0];e->life=100;e->hp=1;e->x=50*256;e->y=70*256;
 projectile(&g.bullets[0],e->x,e->y,0);game_step(&g,0);assert(g.kills==1&&g.score==100&&!e->life);
 fresh();projectile(&g.bullets[0],g.x,g.y,1);projectile(&g.bullets[1],g.x,g.y,1);game_step(&g,0);assert(g.hp==2&&g.hits==1&&g.invulnerable);
 projectile(&g.bullets[2],g.x,g.y,1);game_step(&g,0);assert(g.hp==2);
 fresh();g.hp=1;projectile(&g.bullets[0],g.x,g.y,1);game_step(&g,0);assert(g.state==GAME_OVER);
 for(int i=0;i<60;i++)game_step(&g,15);assert(g.state==WAVES&&g.hp==3&&g.score==0);
 fresh();g.pickup.x=g.x;g.pickup.y=g.y;g.pickup.life=100;game_step(&g,0);assert(g.power==2&&!g.pickup.life);
 g.cooldown=0;game_step(&g,0);assert(g.shots==3);
 fresh();g.invulnerable=10000;for(int i=0;i<1800;i++)game_step(&g,0);assert(g.state==BOSS&&g.spawned==30);
 g.boss_hp=85;game_step(&g,0);assert(g.boss_phase==1);projectile(&g.bullets[0],g.boss_x,g.boss_y,0);game_step(&g,0);assert(g.boss_hp==84);
 game_step(&g,0);assert(g.boss_phase==2);g.boss_hp=42;game_step(&g,0);assert(g.boss_phase==3&&g.phase_seen==7);
 g.boss_hp=1;projectile(&g.bullets[0],g.boss_x,g.boss_y,0);game_step(&g,0);assert(g.state==VICTORY&&g.boss_hp==0);
 for(int i=0;i<GAME_BULLETS;i++)assert(!g.bullets[i].life);
 fresh();for(int i=0;i<GAME_BULLETS;i++)projectile(&g.bullets[i],10*256,100*256,1);g.cooldown=0;game_step(&g,0);assert(g.shots==0);
 for(int i=0;i<300;i++)game_step(&g,0);for(int i=0;i<GAME_BULLETS;i++)assert(g.bullets[i].life>=0);
 for(int s=0;s<4;s++){scenario(&g,s);scenario(&other,s);assert(game_state_hash(&g)==game_state_hash(&other));
  memset(guarded,0xa5,sizeof guarded);game_render(&g,guarded+16);for(int i=0;i<16;i++)assert(guarded[i]==0xa5&&guarded[GAME_W*GAME_H+16+i]==0xa5);
  for(int i=0;i<GAME_W*GAME_H;i++)assert(guarded[16+i]<32);
 }
 fresh();uint32_t r=971;
 for(int i=0;i<30000;i++){r=r*1664525u+1013904223u;if(g.state==GAME_OVER||g.state==VICTORY)game_start(&g);game_step(&g,(r>>24)&15);
  assert(g.hp>=0&&g.hp<=3&&g.x>=12*256&&g.x<=308*256&&g.y>=48*256&&g.y<=225*256);
  for(int j=0;j<GAME_BULLETS;j++)assert(g.bullets[j].life>=0&&g.bullets[j].life<=220);
 }
 puts("PASS: four keys, diagonals, limits, autofire, kills, invulnerability, death/restart, pickup, waves, three boss phases, victory, pool saturation, render guards, deterministic scenes, 30000-step soak");
 return 0;
}
