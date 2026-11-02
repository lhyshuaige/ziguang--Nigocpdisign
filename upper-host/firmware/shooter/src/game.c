#include "game.h"
static int abs_i(int x){return x<0?-x:x;}
static int clamp(int v,int lo,int hi){return v<lo?lo:v>hi?hi:v;}
static uint32_t random_u(Game *g){uint32_t x=g->rng;x^=x<<13;x^=x>>17;x^=x<<5;return g->rng=x;}
static void clear(void *p,uint32_t n){uint8_t *b=p;while(n--)*b++=0;}
static void burst(Game *g,int x,int y,int color){
 for(int j=0;j<9;j++)for(int i=0;i<GAME_PARTICLES;i++)if(!g->particles[i].life){
  Entity *e=&g->particles[i];e->x=x;e->y=y;e->vx=(int)(random_u(g)%601)-300;e->vy=(int)(random_u(g)%601)-300;
  e->life=18+(int)(random_u(g)%16);e->kind=(int16_t)color;break;
 }
}
static void shot(Game *g,int x,int y,int vx,int vy,int kind){
 for(int i=0;i<GAME_BULLETS;i++)if(!g->bullets[i].life){
  Entity *e=&g->bullets[i];e->x=x;e->y=y;e->vx=vx;e->vy=vy;e->kind=(int16_t)kind;e->life=220;
  if(!kind)g->shots++;return;
 }
}
static int overlap(int x,int y,int xx,int yy,int rx,int ry){return abs_i(x-xx)<rx*256&&abs_i(y-yy)<ry*256;}
void game_init(Game *g,uint32_t seed){clear(g,sizeof(*g));g->rng=seed?seed:1;g->state=TITLE;g->x=160*256;g->y=204*256;g->hp=3;g->power=1;}
void game_start(Game *g){uint32_t seed=g->rng;game_init(g,seed);g->state=WAVES;}
static void hurt(Game *g){if(g->invulnerable)return;g->hp--;g->hits++;g->invulnerable=90;g->shake=10;burst(g,g->x,g->y,7);if(!g->hp)g->state=GAME_OVER;}
void game_step(Game *g,uint32_t keys){
 keys&=15;g->tick++;
 if(g->state==TITLE){if(keys)game_start(g);return;}
 if(keys==15){if(++g->restart_hold==60){game_start(g);return;}}else g->restart_hold=0;
 if(g->shake)g->shake--;
 for(int i=0;i<GAME_PARTICLES;i++){Entity *e=&g->particles[i];if(e->life){e->life--;e->x+=e->vx;e->y+=e->vy;}}
 if(g->state==VICTORY||g->state==GAME_OVER)return;
 if(g->invulnerable)g->invulnerable--;
 int dx=((keys&KEY_RIGHT)!=0)-((keys&KEY_LEFT)!=0),dy=((keys&KEY_DOWN)!=0)-((keys&KEY_UP)!=0);
 int speed=(dx&&dy)?430:608;g->x=clamp(g->x+dx*speed,12*256,308*256);g->y=clamp(g->y+dy*speed,48*256,225*256);
 if(g->cooldown)g->cooldown--;else{shot(g,g->x,g->y-10*256,0,-1550,0);if(g->power>=2){shot(g,g->x-6*256,g->y-5*256,-110,-1480,0);shot(g,g->x+6*256,g->y-5*256,110,-1480,0);}g->cooldown=8;}
 if(g->state==WAVES){
  g->wave_tick++;
  if(g->spawned<30&&g->wave_tick%38==1){for(int i=0;i<GAME_ENEMIES;i++)if(!g->enemies[i].life){
   Entity *e=&g->enemies[i];e->x=(28+(int)(random_u(g)%264))*256;e->y=30*256;e->vx=(g->spawned&1)?100:-100;e->vy=125+g->spawned*2;
   e->life=420;e->hp=(g->spawned%5==4)?3:1;e->kind=(int16_t)(g->spawned%3);g->spawned++;break;
  }}
  int active=0;
  for(int i=0;i<GAME_ENEMIES;i++){Entity *e=&g->enemies[i];if(!e->life)continue;active++;e->life--;e->x+=e->vx;e->y+=e->vy;
   if(e->x<15*256||e->x>305*256)e->vx=-e->vx;
   if(e->y>245*256)e->life=0;
   else if((g->tick+(uint32_t)i*17)%100==0){int vx=clamp((g->x-e->x)/80,-360,360);shot(g,e->x,e->y+8*256,vx,500,1);}
   if(overlap(g->x,g->y,e->x,e->y,12,12)){hurt(g);e->life=0;}
  }
  if(g->spawned==30&&!active){g->state=BOSS;g->boss_hp=126;g->boss_x=160*256;g->boss_y=60*256;g->boss_tick=0;g->boss_phase=1;g->phase_seen|=1;}
 }
 if(g->state==BOSS){
  g->boss_tick++;g->boss_phase=g->boss_hp>84?1:g->boss_hp>42?2:3;g->phase_seen|=1u<<(g->boss_phase-1);
  int t=g->boss_tick%360;g->boss_x=(60+(t<180?t:360-t)*200/180)*256;
  int interval=g->boss_phase==1?44:g->boss_phase==2?32:24;
  if(g->boss_tick%interval==0){int n=g->boss_phase+1;
   for(int j=-n;j<=n;j++)shot(g,g->boss_x,g->boss_y+18*256,j*145,430+(n-abs_i(j))*65,1);
   if(g->boss_phase>=2)shot(g,g->boss_x,g->boss_y+16*256,clamp((g->x-g->boss_x)/70,-520,520),730,2);
  }
  if(overlap(g->x,g->y,g->boss_x,g->boss_y,35,20))hurt(g);
 }
 for(int i=0;i<GAME_BULLETS;i++){Entity *e=&g->bullets[i];if(!e->life)continue;e->life--;e->x+=e->vx;e->y+=e->vy;
  if(e->x<0||e->x>=320*256||e->y<24*256||e->y>=240*256){e->life=0;continue;}
  if(e->kind){if(overlap(e->x,e->y,g->x,g->y,5,7)){e->life=0;hurt(g);}continue;}
  if(g->state==BOSS&&overlap(e->x,e->y,g->boss_x,g->boss_y,31,16)){
   e->life=0;g->boss_hp--;g->score+=5;
   if(!g->boss_hp){g->state=VICTORY;g->score+=2000;g->shake=16;burst(g,g->boss_x,g->boss_y,13);for(int j=0;j<GAME_BULLETS;j++)g->bullets[j].life=0;break;}
   continue;
  }
  for(int j=0;j<GAME_ENEMIES;j++){Entity *f=&g->enemies[j];if(f->life&&overlap(e->x,e->y,f->x,f->y,10,9)){
   e->life=0;f->hp--;if(!f->hp){f->life=0;g->score+=100;g->kills++;burst(g,f->x,f->y,8);
    if(g->kills%4==0){g->pickup.x=f->x;g->pickup.y=f->y;g->pickup.life=350;}
   }break;
  }}
 }
 if(g->pickup.life){g->pickup.life--;g->pickup.y+=180;
  if(overlap(g->x,g->y,g->pickup.x,g->pickup.y,13,13)){g->pickup.life=0;g->power=2;g->score+=50;burst(g,g->x,g->y,11);}
  else if(g->pickup.y>240*256)g->pickup.life=0;
 }
}
uint32_t game_hash(const uint8_t *p,uint32_t n){uint32_t h=2166136261u;while(n--)h=(h^*p++)*16777619u;return h;}
uint32_t game_state_hash(const Game *g){return game_hash((const uint8_t *)g,sizeof(*g));}
