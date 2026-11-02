#include "arcade.h"
#include "gfx.h"
void arcade_rect(uint8_t *p,int x,int y,int w,int h,int c){gx_rect(p,x,y,w,h,c);}
void arcade_text(uint8_t *p,int x,int y,const char *s,int c,int size){gx_text(p,x,y,s,c,size);}
void arcade_number(uint8_t *p,int x,int y,uint32_t n,int count,int c){gx_number(p,x,y,n,count,c,1);}
