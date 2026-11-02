#include "scenarios.h"
void scenario(Game *g,int which){
 game_init(g,0x1234abcd);game_start(g);g->tick=420;g->score=1800;g->power=2;g->x=156*256;
 if(which==0){g->spawned=16;
  for(int i=0;i<7;i++){Entity *e=&g->enemies[i];e->life=160;e->hp=2;e->x=(40+i*37)*256;e->y=(65+i%3*29)*256;e->vy=140;e->kind=(int16_t)(i%3);}
  for(int i=0;i<18;i++){Entity *e=&g->bullets[i];e->life=100;e->x=(24+i*17)*256;e->y=(128+i%4*13)*256;e->vy=460;e->kind=1;}
  g->pickup.life=200;g->pickup.x=250*256;g->pickup.y=160*256;
 }else{g->state=BOSS;g->spawned=30;g->boss_x=160*256;g->boss_y=60*256;g->boss_hp=which==1?126:which==2?80:38;g->boss_phase=which;g->boss_tick=80;}
 for(int i=0;i<80;i++)game_step(g,i<20?KEY_LEFT:i<60?KEY_RIGHT:0);
}
