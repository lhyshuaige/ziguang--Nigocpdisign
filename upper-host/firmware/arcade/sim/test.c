#include "arcade.h"
#include "protocol.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static Arcade a;static uint8_t pixels[GAME_W*GAME_H+32],encoded[ARCADE_RLE_MAX];
static void hold(unsigned keys,int n){while(n--)arcade_step(&a,keys);}
static void press(unsigned keys){hold(0,3);hold(keys,3);hold(0,3);}
static void put(uint8_t *p,uint32_t v){p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v;}
int main(void){
 arcade_init(&a,123);hold(2,1);hold(0,3);assert(a.selected==0);press(2);assert(a.selected==1);press(1);assert(a.selected==0);
 for(int m=1;m<=4;m++){a.selected=m-1;press(4);assert(a.mode==m);hold(3,48);hold(0,3);assert(a.mode==0);}
 arcade_enter(&a,ARCADE_SNAKE);a.snake_food=a.snake[0]+1;hold(0,10);assert(a.snake_len==5&&a.score==10);press(4);assert(a.snake_next==3);hold(8,200);assert(a.ended==1);press(8);assert(a.mode==0);
 arcade_enter(&a,ARCADE_BREAKOUT);press(4);assert(a.ball_live);a.ball_x=30*256;a.ball_y=45*256;a.ball_vx=0;a.ball_vy=512;hold(0,1);assert(a.brick_left==47&&a.score==25);
 a.ball_y=239*256;a.ball_vy=512;hold(0,1);assert(a.lives==2&&!a.ball_live);
 arcade_enter(&a,ARCADE_BLOCKS);for(int x=0;x<10;x++)a.board[170+x]=(x>=3&&x<=6)?0:1;a.piece=0;a.rotation=0;a.px=3;a.py=0;
 press(8);assert(a.lines==1&&a.score>=100);for(int x=0;x<10;x++)assert(!a.board[170+x]);
 for(int m=0;m<=4;m++){arcade_init(&a,123);if(m)arcade_enter(&a,m);memset(pixels,0xa5,sizeof pixels);arcade_render(&a,pixels+16);
  for(int i=0;i<16;i++)assert(pixels[i]==0xa5&&pixels[GAME_W*GAME_H+16+i]==0xa5);
  uint32_t n=arcade_encode(pixels+16,encoded,sizeof encoded),at=0;assert(n>0&&!(n&1));
  for(uint32_t i=0;i<n;i+=2){assert(encoded[i]&&encoded[i+1]<32);for(unsigned j=0;j<encoded[i];j++)assert(pixels[16+at++]==encoded[i+1]);}assert(at==GAME_W*GAME_H);
  assert(!arcade_encode(pixels+16,encoded,1));
 }
 assert(arcade_crc((const uint8_t *)"123456789",9)==0xcbf43926u);
 ArcadeStream s={0};uint8_t q[24]={0},reply[64];memcpy(q,"NGGQ",4);put(q+4,1);put(q+8,1);put(q+12,9);put(q+16,77);
 assert(arcade_request(&s,q,24,100,5003,0,0,0,0,0,reply)==64&&s.peer==100);
 assert(arcade_request(&s,q,24,101,5003,1,0,0,0,0,reply)==64&&reply[23]==2&&s.peer==100);
 put(q+8,2);assert(arcade_request(&s,q,24,101,5003,2,0,0,0,0,reply)==64&&reply[23]==3);
 assert(arcade_request(&s,q,24,100,5003,3,0,0,0,0,reply)==64&&!s.peer);
 put(q+8,1);assert(arcade_request(&s,q,23,100,5003,3,0,0,0,0,reply)==0);
 for(int m=1;m<=4;m++){arcade_init(&a,19);arcade_enter(&a,m);uint32_t r=17;for(int i=0;i<12000;i++){r=r*1664525u+1013904223u;hold((r>>24)&15,1);assert(a.mode>=0&&a.mode<=4);assert(a.snake_len<=504);if(a.ended||!a.mode)arcade_enter(&a,m);}}
 puts("ARCADE_NATIVE_PASS menu debounce, four games, exit gesture, snake growth/reverse/walls, bricks/lives, block line clear, guarded render/RLE, CRC, ownership, 48000-step soak");return 0;
}
