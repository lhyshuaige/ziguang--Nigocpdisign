#include "arcade.h"
#include "gfx.h"
#include <string.h>
static uint32_t rng(Arcade *a){a->rng=a->rng*1664525u+1013904223u;return a->rng;}
static int clamp(int x,int lo,int hi){return x<lo?lo:x>hi?hi:x;}
static int absolute(int x){return x<0?-x:x;}
static const uint16_t shapes[7][4]={
 {0x00f0,0x4444,0x0f00,0x2222},{0x0066,0x0066,0x0066,0x0066},
 {0x0072,0x0262,0x0270,0x0232},{0x0071,0x0226,0x0470,0x0322},
 {0x0074,0x0622,0x0170,0x0223},{0x0036,0x0462,0x0360,0x0231},
 {0x0063,0x0264,0x0630,0x0132}};
static int fits(const Arcade *a,int x,int y,int rot){
 uint16_t s=shapes[a->piece][rot&3];
 for(int i=0;i<16;i++)if(s&(1u<<i)){int xx=x+i%4,yy=y+i/4;if(xx<0||xx>=10||yy<0||yy>=18||a->board[yy*10+xx])return 0;}return 1;
}
static void spawn_piece(Arcade *a){a->piece=(int)(rng(a)%7);a->rotation=0;a->px=3;a->py=0;a->fall_clock=0;if(!fits(a,a->px,a->py,0))a->ended=1;}
static void lock_piece(Arcade *a){
 uint16_t s=shapes[a->piece][a->rotation];for(int i=0;i<16;i++)if(s&(1u<<i))a->board[(a->py+i/4)*10+a->px+i%4]=(uint8_t)(a->piece+1);
 int removed=0;
 for(int y=17;y>=0;y--){int full=1;for(int x=0;x<10;x++)if(!a->board[y*10+x])full=0;if(full){for(int j=y;j>0;j--)memcpy(a->board+j*10,a->board+(j-1)*10,10);memset(a->board,0,10);removed++;y++;}}
 a->lines+=removed;a->score+=(uint32_t)(removed*removed*100);a->level=a->lines/5;spawn_piece(a);
}
static void food(Arcade *a){
 if(a->snake_len>=504){a->ended=2;return;}int cell=(int)(rng(a)%504);
 for(int trial=0;trial<504;trial++){int free=1;for(int i=0;i<a->snake_len;i++)if(a->snake[i]==cell)free=0;if(free){a->snake_food=cell;return;}cell=(cell+1)%504;}
}
void arcade_enter(Arcade *a,int mode){
 a->mode=mode;a->ended=0;a->score=0;a->back_hold=0;a->previous=a->keys;
 if(mode==ARCADE_SHOOTER){game_init(&a->shooter,rng(a));game_start(&a->shooter);}
 if(mode==ARCADE_SNAKE){a->snake_len=4;a->snake_dir=3;a->snake_next=3;a->snake_clock=0;for(int i=0;i<4;i++)a->snake[i]=(uint16_t)(9*28+14-i);food(a);}
 if(mode==ARCADE_BREAKOUT){memset(a->bricks,1,sizeof a->bricks);a->brick_left=48;a->paddle=160;a->ball_x=160*256;a->ball_y=202*256;a->ball_vx=340;a->ball_vy=-440;a->ball_live=0;a->lives=3;}
 if(mode==ARCADE_BLOCKS){memset(a->board,0,sizeof a->board);a->lines=0;a->level=0;spawn_piece(a);}
}
void arcade_init(Arcade *a,uint32_t seed){memset(a,0,sizeof(*a));a->rng=seed?seed:1;}
void arcade_step(Arcade *a,uint32_t raw){
 a->tick++;raw&=15;
 for(int i=0;i<4;i++){uint32_t bit=1u<<i;if((raw&bit)==(a->candidate&bit)){if(a->debounce[i]<2)a->debounce[i]++;}else{a->candidate=(a->candidate&~bit)|(raw&bit);a->debounce[i]=1;}if(a->debounce[i]>=2)a->keys=(a->keys&~bit)|(raw&bit);}
 uint32_t edge=a->keys&~a->previous;a->previous=a->keys;
 if(a->mode==ARCADE_MENU){
  if(edge&1)a->selected=(a->selected+3)%4;if(edge&2)a->selected=(a->selected+1)%4;
  if(edge&4)arcade_enter(a,a->selected+1);return;
 }
 if((a->keys&3)==3){if(++a->back_hold>=45){a->mode=ARCADE_MENU;a->back_hold=0;return;}}else a->back_hold=0;
 if(a->ended){if(edge&8){a->mode=ARCADE_MENU;return;}if(edge&4)arcade_enter(a,a->mode);return;}
 uint32_t keys=(a->keys&3)==3?0:a->keys;
 if(a->mode==ARCADE_SHOOTER){game_step(&a->shooter,keys);a->score=a->shooter.score;if(a->shooter.state==VICTORY)a->ended=2;if(a->shooter.state==GAME_OVER)a->ended=1;return;}
 if(a->mode==ARCADE_SNAKE){
  for(int d=0;d<4;d++)if((keys&(1u<<d))&&d!=(a->snake_dir^1))a->snake_next=d;
  int period=clamp(10-(a->snake_len-4)/5,3,10);
  if(++a->snake_clock<period)return;a->snake_clock=0;a->snake_dir=a->snake_next;
  int x=a->snake[0]%28,y=a->snake[0]/28;x+=(a->snake_dir==3)-(a->snake_dir==2);y+=(a->snake_dir==1)-(a->snake_dir==0);
  if(x<0||x>=28||y<0||y>=18){a->ended=1;return;}int next=y*28+x,grow=next==a->snake_food;
  for(int i=0;i<a->snake_len-(grow?0:1);i++)if(a->snake[i]==next){a->ended=1;return;}
  if(grow)a->snake_len++;for(int i=a->snake_len-1;i>0;i--)a->snake[i]=a->snake[i-1];a->snake[0]=(uint16_t)next;
  if(grow){a->score+=10;food(a);}return;
 }
 if(a->mode==ARCADE_BREAKOUT){
  a->paddle=clamp(a->paddle+(((keys&2)!=0)-((keys&1)!=0))*4,32,288);
  if(!a->ball_live){a->ball_x=a->paddle*256;a->ball_y=202*256;if(edge&4)a->ball_live=1;return;}
  int old_y=a->ball_y;a->ball_x+=a->ball_vx;a->ball_y+=a->ball_vy;
  if(a->ball_x<15*256){a->ball_x=15*256;a->ball_vx=absolute(a->ball_vx);}if(a->ball_x>305*256){a->ball_x=305*256;a->ball_vx=-absolute(a->ball_vx);}
  if(a->ball_y<36*256){a->ball_y=36*256;a->ball_vy=absolute(a->ball_vy);}
  int x=a->ball_x/256,y=a->ball_y/256;
  if(a->ball_vy>0&&old_y<=204*256&&a->ball_y>=204*256&&absolute(x-a->paddle)<29){a->ball_y=204*256;a->ball_vy=-absolute(a->ball_vy);a->ball_vx=(x-a->paddle)*24;}
  for(int i=0;i<48;i++)if(a->bricks[i]){int bx=18+(i%8)*36,by=48+(i/8)*16;if(x>=bx-3&&x<=bx+31&&y>=by-3&&y<=by+13){a->bricks[i]=0;a->brick_left--;a->score+=25;a->ball_vy=-a->ball_vy;if(!a->brick_left)a->ended=2;break;}}
  if(y>238){a->lives--;a->ball_live=0;if(!a->lives)a->ended=1;}return;
 }
 if(a->mode==ARCADE_BLOCKS){
  int dx=((keys&2)!=0)-((keys&1)!=0);
  if(dx&&((edge&3)||a->tick%7==0)&&fits(a,a->px+dx,a->py,a->rotation))a->px+=dx;
  if(edge&4){int r=(a->rotation+1)&3;if(fits(a,a->px,a->py,r))a->rotation=r;else if(fits(a,a->px-1,a->py,r)){a->px--;a->rotation=r;}else if(fits(a,a->px+1,a->py,r)){a->px++;a->rotation=r;}}
  if(edge&8){while(fits(a,a->px,a->py+1,a->rotation)){a->py++;a->score++;}lock_piece(a);return;}
  if(++a->fall_clock>=clamp(36-a->level*3,6,36)){a->fall_clock=0;if(fits(a,a->px,a->py+1,a->rotation))a->py++;else lock_piece(a);}
 }
}
static void menu_art(uint8_t *p,int selected){
 gx_panel(p,12,51,152,162,1,3);
 static const char *titles[4]={"STARFALL","NEON SNAKE","BREAKOUT","STACK"};
 static const char *sub[4]={"THE LAST ORBIT","ONE MORE BITE","MAKE IT SHATTER","FIND YOUR RHYTHM"};
 static const int accents[4]={5,11,8,14};
 int accent=accents[selected];
 gx_rect(p,24,64,20,2,accent);gx_text(p,24,75,titles[selected],6,2);
 gx_text(p,24,96,sub[selected],18,1);
 gx_rect(p,20,112,136,80,0);gx_rect(p,20,112,136,14,16);
 if(selected==0){
  for(int i=0;i<18;i++)gx_pixel(p,25+(i*37)%125,117+(i*23)%69,i%4?3:18);
  game_draw_boss(p,85,137,1,80);game_draw_player(p,86,177,120,1);
  gx_rect(p,85,153,2,7,5);gx_pixel(p,86,152,6);
 }else if(selected==1){
  static const int cells[11][2]={{7,2},{6,2},{5,2},{4,2},{4,3},{4,4},{3,4},{2,4},{1,4},{1,3},{1,2}};
  for(int i=10;i>=0;i--){int x=32+cells[i][0]*12,y=117+cells[i][1]*12;gx_rect(p,x,y,11,11,i?12:11);gx_rect(p,x+2,y+1,7,2,i?11:6);}
  gx_pixel(p,124,143,0);gx_pixel(p,124,148,0);gx_rect(p,58,130,7,7,7);gx_rect(p,59,130,2,2,13);gx_rect(p,61,127,3,2,11);
 }else if(selected==2){
  for(int row=0;row<3;row++)for(int col=0;col<5;col++)if(!(row==2&&col==2))gx_tile(p,27+col*24,122+row*13,22,10,row==0?7:row==1?8:9);
  gx_rect(p,63,178,50,6,4);gx_rect(p,66,178,44,2,6);gx_rect(p,98,164,4,4,6);
  gx_rect(p,95,169,3,3,4);gx_pixel(p,92,174,3);
 }else{
  static const int tiles[13][3]={{0,4,7},{1,4,7},{1,3,7},{2,3,7},{3,4,5},{4,4,5},{5,4,5},{5,3,5},{4,3,9},{4,2,9},{3,3,9},{3,2,9},{2,4,14}};
  for(int i=0;i<13;i++)gx_tile(p,40+tiles[i][0]*15,115+tiles[i][1]*15,14,14,tiles[i][2]);
  gx_tile(p,70,119,14,14,14);gx_tile(p,85,119,14,14,14);gx_tile(p,100,119,14,14,14);gx_tile(p,85,104,14,14,14);
 }
 gx_text(p,24,199,"PRESS K3 TO PLAY",accent,1);
}
static void hud(uint8_t *p,const char *title,uint32_t score,int accent){
 gx_rect(p,0,0,320,30,1);gx_rect(p,0,29,320,1,3);gx_rect(p,12,7,3,15,accent);
 gx_text(p,22,9,title,6,2);gx_text(p,230,5,"SCORE",18,1);gx_number(p,230,16,score,7,accent,1);
}
static void snake_view(const Arcade *a,uint8_t *p){
 gx_panel(p,18,40,284,184,0,4);
 for(int yy=0;yy<18;yy+=2)for(int xx=0;xx<28;xx+=2)gx_pixel(p,20+xx*10,42+yy*10,1);
 for(int i=a->snake_len-1;i>=0;i--){
  int x=20+(a->snake[i]%28)*10,y=42+(a->snake[i]/28)*10;
  if(i){int px=20+(a->snake[i-1]%28)*10,py=42+(a->snake[i-1]/28)*10;
   if(px==x)gx_rect(p,x+2,y<py?y+7:y-1,6,4,12);else gx_rect(p,x<px?x+7:x-1,y+2,4,6,12);}
  gx_rect(p,x+1,y+1,8,8,i?12:11);gx_rect(p,x+2,y+1,6,2,i?11:6);gx_rect(p,x+2,y+8,6,1,20);
  if(!i){if(a->snake_dir>=2){int eye=x+(a->snake_dir==3?6:2);gx_rect(p,eye,y+2,2,2,0);gx_rect(p,eye,y+6,2,2,0);}
   else{int eye=y+(a->snake_dir==1?6:2);gx_rect(p,x+2,eye,2,2,0);gx_rect(p,x+6,eye,2,2,0);}}
 }
 int x=20+(a->snake_food%28)*10,y=42+(a->snake_food/28)*10;
 gx_rect(p,x+2,y+3,6,5,7);gx_rect(p,x+3,y+2,4,7,7);gx_rect(p,x+3,y+3,2,2,13);gx_rect(p,x+5,y,3,2,11);
}
static void breakout_view(const Arcade *a,uint8_t *p){
 gx_rect(p,9,39,302,187,1);gx_rect(p,10,40,300,184,0);gx_rect(p,9,39,302,1,3);
 gx_rect(p,9,40,2,184,3);gx_rect(p,309,40,2,184,3);
 for(int y=146;y<220;y+=24)gx_rect(p,14,y,292,1,1);
 static const int colors[6]={7,8,9,11,5,14};
 for(int i=0;i<48;i++)if(a->bricks[i])gx_tile(p,18+(i%8)*36,48+(i/8)*16,31,11,colors[i/8]);
 int x=a->ball_x/256,y=a->ball_y/256;
 if(a->ball_live){gx_rect(p,x-a->ball_vx/100-1,y-a->ball_vy/100-1,3,3,3);gx_rect(p,x-a->ball_vx/60,y-a->ball_vy/60,2,2,2);}
 gx_rect(p,x-2,y-3,4,6,9);gx_rect(p,x-3,y-2,6,4,9);gx_rect(p,x-1,y-2,2,2,6);
 gx_rect(p,a->paddle-26,210,53,8,0);gx_rect(p,a->paddle-25,209,51,6,4);
 gx_rect(p,a->paddle-22,209,45,2,6);gx_rect(p,a->paddle-25,210,4,5,5);gx_rect(p,a->paddle+22,210,4,5,5);
 gx_text(p,17,32,"LIVES",18,1);for(int i=0;i<a->lives;i++)gx_rect(p,55+i*7,33,4,4,7);
 if(!a->ball_live&&!a->ended){gx_panel(p,90,153,140,28,1,3);gx_text(p,101,164,"K3  LAUNCH THE BALL",6,1);}
}
static void shape_view(uint8_t *p,int x,int y,uint16_t mask,int color,int size,int ghost){
 for(int i=0;i<16;i++)if(mask&(1u<<i)){int xx=x+i%4*size,yy=y+i/4*size;
  if(ghost)gx_outline(p,xx+1,yy+1,size-2,size-2,3);else gx_tile(p,xx,yy,size-1,size-1,color);}
}
static void blocks_view(const Arcade *a,uint8_t *p){
 static const int colors[7]={5,9,14,7,8,11,12};
 gx_panel(p,107,38,106,186,0,4);gx_rect(p,110,41,100,180,1);
 for(int y=0;y<18;y++)for(int x=0;x<10;x++){if(a->board[y*10+x])gx_tile(p,110+x*10,41+y*10,9,9,colors[a->board[y*10+x]-1]);else gx_pixel(p,110+x*10,41+y*10,2);}
 int ghost_y=a->py;while(fits(a,a->px,ghost_y+1,a->rotation))ghost_y++;
 shape_view(p,110+a->px*10,41+ghost_y*10,shapes[a->piece][a->rotation],colors[a->piece],10,1);
 shape_view(p,110+a->px*10,41+a->py*10,shapes[a->piece][a->rotation],colors[a->piece],10,0);
 gx_panel(p,12,48,82,59,1,3);gx_text(p,22,58,"LINES",18,1);gx_number(p,22,78,(uint32_t)a->lines,3,11,2);
 gx_panel(p,12,117,82,52,1,3);gx_text(p,22,127,"LEVEL",18,1);gx_number(p,22,145,(uint32_t)a->level+1,2,5,2);
 gx_panel(p,226,48,82,69,1,3);gx_text(p,238,58,"NEXT",18,1);
 unsigned next=(a->rng*1664525u+1013904223u)%7u;shape_view(p,245,80,shapes[next][0],colors[next],10,0);
 gx_text(p,230,139,"K3 ROTATE",18,1);gx_text(p,230,155,"K4 DROP",18,1);
}
void arcade_render(const Arcade *a,uint8_t *p){
 memset(p,0,GAME_W*GAME_H);
 if(a->mode==ARCADE_MENU){
  gx_rect(p,0,0,320,41,1);gx_rect(p,12,39,296,1,3);gx_text(p,17,14,"NIGO ARCADE",6,2);
  gx_rect(p,253,13,53,15,20);gx_text(p,259,17,"4 GAMES",5,1);menu_art(p,a->selected);
  static const char *names[4]={"STARFALL","NEON SNAKE","BREAKOUT","STACK"};
  static const char *desc[4]={"SPACE / BOSS","GROW / SURVIVE","CLEAR THE WALL","BUILD / COMBO"};
  static const int colors[4]={5,11,8,14};
  for(int i=0;i<4;i++){int y=51+i*42,on=a->selected==i,c=on?colors[i]:3;
   gx_panel(p,174,y,134,36,on?2:1,c);gx_rect(p,174,y+4,3,28,c);
   gx_number(p,184,y+8,(uint32_t)i+1,1,on?6:18,1);gx_text(p,199,y+7,names[i],on?6:18,1);
   gx_text(p,184,y+22,desc[i],on?colors[i]:3,1);
  }
  gx_rect(p,0,219,320,21,1);gx_key(p,14,223,"K1",5);gx_key(p,34,223,"K2",5);gx_text(p,57,226,"SELECT",18,1);
  gx_key(p,110,223,"K3",11);gx_text(p,134,226,"PLAY",11,1);gx_number(p,266,226,(uint32_t)a->selected+1,2,6,1);gx_text(p,282,226,"/04",3,1);return;
 }
 if(a->mode==ARCADE_SHOOTER)game_render(&a->shooter,p);
 else if(a->mode==ARCADE_SNAKE){hud(p,"NEON SNAKE",a->score,11);snake_view(a,p);}
 else if(a->mode==ARCADE_BREAKOUT){hud(p,"BREAKOUT",a->score,8);breakout_view(a,p);}
 else if(a->mode==ARCADE_BLOCKS){hud(p,"STACK",a->score,14);blocks_view(a,p);}
 gx_rect(p,0,230,320,10,1);gx_text(p,88,232,"HOLD K1 + K2 FOR MENU",18,1);
 if(a->ended){
  gx_panel(p,35,87,250,76,1,3);gx_rect(p,51,97,218,1,a->ended==2?11:7);
  gx_text(p,a->ended==2?118:106,110,a->ended==2?"YOU WIN":"GAME OVER",a->ended==2?11:7,2);
  gx_text(p,88,143,"K3 RETRY  K4 MENU",6,1);
 }
}
uint32_t arcade_encode(const uint8_t *p,uint8_t *out,uint32_t capacity){
 uint32_t n=GAME_W*GAME_H,at=0,i=0;
 while(i<n){uint32_t run=1;while(run<255&&i+run<n&&p[i+run]==p[i])run++;if(at+2>capacity)return 0;out[at++]=(uint8_t)run;out[at++]=p[i];i+=run;}return at;
}
uint32_t arcade_crc(const uint8_t *p,uint32_t n){uint32_t c=0xffffffffu;while(n--){c^=*p++;for(int i=0;i<8;i++)c=(c>>1)^(0xedb88320u&(0u-(c&1)));}return c^0xffffffffu;}
