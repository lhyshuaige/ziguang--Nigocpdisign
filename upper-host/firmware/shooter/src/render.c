#include "game.h"
#include "gfx.h"
const uint32_t game_palette[32]={
 0x070d20,0x0e1934,0x162849,0x254568,0x367ca0,0x73d6ec,0xd8faff,0xef5573,
 0xff955c,0xffd67c,0x6d59c7,0x63efb0,0x29a59e,0xf0b4ff,0x946ff5,0x34465d,
 0x122039,0x203453,0x86a3b9,0xffffff,0x1a5770,0x543c6d,0x8b395d,0xb8cbdf,0,0,0,0,0,0,0,0};
static const char *const fighter[]={
 "............5............","...........565...........","...........565...........",
 "..........35653..........","..........35653..........",".........2356532.........",
 "....2....2354532....2....","....52...2354532...25....","....542..2354532..245....",
 "....54322355455322345....","...254333555555333452...","..254433335555533334452..",
 ".25444333335553333344452.","2544433323355532333444452","2555433222355532223345552",
 "2333322222355532222233332",".222222..2355532..222222.","...222...2355532...222...",
 "....2....2355532....2....",".........2235322.........",".........2.353.2........."};
static const char *const raider[]={
 "...C...............C...","..C7C.............C7C..",".C77C...CCC...CCC.C77C.",
 ".C77CC.C777C.C777CC77C.","C7777CC788877887CC7777C","C77777C7855587C777777C",
 "C7B777C7856587C777B77C","C7BB77CC85558CC77BB77C",".C7777C7855587C77777C.",
 "..CC77C7788877C77CC...","....CCC7777777CCC.....","......C77C7C77C.......",
 "......C7CC7CC7C.......",".......C.C7C.C........","..........C..........."};
static void sprite(uint8_t *p,int x,int y,const char *const *rows,int height,int scale,int kind){
 static const uint8_t colors[16]={0,2,3,4,5,6,19,7,8,9,14,13,22,21,11,12};
 for(int yy=0;yy<height;yy++)for(int xx=0;rows[yy][xx];xx++){char ch=rows[yy][xx];if(ch=='.')continue;
  unsigned token=(unsigned)(ch<='9'?ch-'0':ch-'A'+10);int c=colors[token];
  if(kind==1){if(c==7)c=14;else if(c==22)c=21;else if(c==8)c=13;}
  else if(kind==2){if(c==7)c=8;else if(c==8)c=9;}
  gx_rect(p,x+xx*scale,y+yy*scale,scale,scale,c);
 }
}
void game_draw_player(uint8_t *p,int x,int y,int tick,int scale){
 int flame=3+(tick/3)%4;
 gx_rect(p,x-2*scale,y+8*scale,5*scale,(flame+3)*scale,4);
 gx_rect(p,x-scale,y+8*scale,3*scale,(flame+1)*scale,5);
 gx_rect(p,x,y+8*scale,scale,flame*scale,6);
 sprite(p,x-12*scale,y-12*scale,fighter,21,scale,0);
}
void game_draw_enemy(uint8_t *p,int x,int y,int kind,int tick){
 gx_rect(p,x-6,y-9,3,3+tick%3,22);gx_rect(p,x+5,y-9,3,3+tick%3,22);
 sprite(p,x-11,y-7,raider,15,1,kind);
}
void game_draw_boss(uint8_t *p,int x,int y,int phase,int tick){
 int accent=phase==1?14:phase==2?7:8;
 for(int row=0;row<22;row++){int half=34-row/3;gx_rect(p,x-half,y-10+row,half*2+1,1,21);}
 gx_rect(p,x-30,y-7,61,2,13);gx_rect(p,x-29,y-5,59,14,accent);
 for(int side=-1;side<=1;side+=2){int px=x+side*25;
  gx_panel(p,px-8,y+2,17,19,22,accent);gx_rect(p,px-6,y+4,13,2,13);
  for(int j=0;j<3;j++)gx_rect(p,px-5,y+9+j*3,11,1,21);
  gx_rect(p,px-4,y+21,9,3+tick/4%3,8);gx_rect(p,px-2,y+21,5,2,9);
  gx_rect(p,px-5,y-13,11,7,21);gx_rect(p,px-4,y-13,9,1,13);
  gx_rect(p,px-2,y-10,5,2,accent);gx_pixel(p,px,y-8,6);
 }
 gx_panel(p,x-12,y-19,25,34,3,18);gx_rect(p,x-9,y-16,19,26,20);
 gx_rect(p,x-6,y-13,13,20,4);gx_rect(p,x-4,y-11,9,16,5);
 gx_rect(p,x-2,y-8,5,10,(tick/8&1)?6:13);gx_rect(p,x-8,y+11,17,2,18);
 gx_rect(p,x-10,y-18,21,1,6);gx_rect(p,x-6,y+15,13,4,0);
 gx_rect(p,x-3,y+15,7,6,accent);gx_rect(p,x-1,y+16,3,5,9);
}
static void heart(uint8_t *p,int x,int y,int live){int c=live?7:2;gx_rect(p,x,y,3,3,c);gx_rect(p,x+4,y,3,3,c);gx_rect(p,x,y+2,7,3,c);gx_rect(p,x+1,y+5,5,1,c);gx_rect(p,x+2,y+6,3,1,c);gx_pixel(p,x+3,y+7,c);if(live)gx_rect(p,x+1,y+1,2,1,13);}
void game_render(const Game *g,uint8_t *p){
 gx_rect(p,0,0,320,240,0);
 gx_rect(p,9,32,302,34,16);gx_rect(p,9,66,302,28,1);
 for(int i=0;i<52;i++){uint32_t h=(uint32_t)i*2654435761u;int x=16+(int)(h%288),y=34+(int)(((h>>10)+g->tick*(1+i%3)/3)%196);int c=i%9==0?18:3;
  gx_pixel(p,x,y,c);if(i%13==0){gx_pixel(p,x-1,y,2);gx_pixel(p,x+1,y,2);gx_pixel(p,x,y-1,2);gx_pixel(p,x,y+1,2);}}
 gx_rect(p,4,32,3,198,2);gx_rect(p,313,32,3,198,2);
 for(int y=38+(int)(g->tick/3%28);y<230;y+=28){gx_rect(p,4,y,3,4,4);gx_rect(p,313,y,3,4,4);}
 int sx=g->shake?(int)(g->tick%3)-1:0;
 for(int i=0;i<GAME_ENEMIES;i++)if(g->enemies[i].life)game_draw_enemy(p,g->enemies[i].x/256+sx,g->enemies[i].y/256,g->enemies[i].kind,(int)g->tick);
 if(g->state==BOSS)game_draw_boss(p,g->boss_x/256+sx,g->boss_y/256,g->boss_phase,g->boss_tick);
 if(g->pickup.life){int x=g->pickup.x/256,y=g->pickup.y/256;gx_panel(p,x-7,y-7,15,15,20,11);gx_text(p,x-2,y-3,"P",6,1);gx_rect(p,x-3,y-10,7,1,12);}
 for(int i=0;i<GAME_BULLETS;i++)if(g->bullets[i].life){const Entity *e=&g->bullets[i];int x=e->x/256,y=e->y/256;
  if(!e->kind){gx_rect(p,x-2,y-4,5,10,20);gx_rect(p,x-1,y-5,3,9,5);gx_rect(p,x,y-5,1,7,6);}
  else{int c=e->kind==2?13:7;gx_rect(p,x-1,y-3,3,7,22);gx_rect(p,x-3,y-1,7,3,22);gx_rect(p,x-2,y-1,5,3,c);gx_rect(p,x-1,y-2,3,5,c);gx_pixel(p,x,y-1,9);}
 }
 for(int i=0;i<GAME_PARTICLES;i++)if(g->particles[i].life){const Entity *e=&g->particles[i];int x=e->x/256,y=e->y/256;gx_rect(p,x,y,2,2,e->life>8?e->kind:3);if(e->life>14)gx_pixel(p,x+1,y-1,9);}
 if(g->hp&&(!g->invulnerable||(g->tick/4&1)))game_draw_player(p,g->x/256+sx,g->y/256,(int)g->tick,1);
 gx_rect(p,0,0,320,32,1);gx_rect(p,0,31,320,1,3);gx_rect(p,8,7,3,17,5);
 gx_text(p,17,6,"STARFALL",5,1);gx_number(p,17,18,g->score,7,6,1);
 gx_text(p,110,6,g->state==BOSS?"DREADNOUGHT":"SECTOR 01",18,1);
 if(g->state==BOSS){gx_rect(p,110,19,100,5,21);gx_rect(p,111,20,g->boss_hp*98/126,3,7);for(int i=1;i<5;i++)gx_rect(p,110+20*i,20,1,3,1);}
 else{gx_text(p,110,18,"WAVE",3,1);gx_number(p,146,18,(uint32_t)(g->spawned/6+1),2,6,1);}
 for(int i=0;i<3;i++)heart(p,241+13*i,5,i<g->hp);
 gx_text(p,234,20,"PWR",18,1);for(int i=0;i<3;i++)gx_rect(p,260+9*i,20,6,6,i<g->power?11:2);
 if(g->state==TITLE||g->state==VICTORY||g->state==GAME_OVER){
  gx_panel(p,36,84,248,88,1,4);gx_rect(p,52,97,216,1,3);
  if(g->state==TITLE){gx_text(p,64,110,"NIGO STARFALL",6,2);gx_text(p,85,145,"PRESS A DIRECTION",5,1);}
  else if(g->state==VICTORY){gx_text(p,88,110,"SECTOR CLEAR",11,2);gx_text(p,94,145,"BOSS ELIMINATED",18,1);}
  else{gx_text(p,106,110,"GAME OVER",7,2);gx_text(p,103,145,"FLY ANOTHER DAY",18,1);}
 }
}
