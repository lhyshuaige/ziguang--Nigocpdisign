#include "ultraface_runtime.h"
#include <string.h>
#define CANDIDATES 200u
typedef struct {uf_box box;unsigned prior;} candidate;
static float maximum(float a,float b){return a>b?a:b;}
static float minimum(float a,float b){return a<b?a:b;}
static float clip(float a){return maximum(0,minimum(1,a));}
static int suppress(const uf_box *a,const uf_box *b){
 float w=maximum(0,minimum(a->x2,b->x2)-maximum(a->x1,b->x1));
 float h=maximum(0,minimum(a->y2,b->y2)-maximum(a->y1,b->y1));
 float inter=w*h,area_a=(a->x2-a->x1)*(a->y2-a->y1),area_b=(b->x2-b->x1)*(b->y2-b->y1);
 return inter>.3f*(area_a+area_b-inter+1e-5f);
}
unsigned uf_decode(const uf_runtime *r,uf_box *boxes,unsigned capacity){
 candidate sorted[CANDIDATES];unsigned count=0;
 const uf_head *heads=(const uf_head *)(r->model+r->header->head_offset);
 const float *priors=(const float *)(r->model+r->header->prior_offset);
 for(unsigned hi=0;hi<4;hi++){
  const uf_head *h=heads+hi;
  const int8_t *cls=r->tensors+r->layers[h->classification].tensor;
  const int8_t *loc=r->tensors+r->layers[h->regression].tensor;
  const float *confidence=(const float *)(r->model+h->confidence);
  const float *exponential=(const float *)(r->model+h->exponential);
  for(unsigned i=0;i<h->count;i++){
   float score=confidence[(int)cls[i*2+1]-(int)cls[i*2]+255];
   if(score<=.7f)continue;
   unsigned prior=h->first_prior+i;const float *p=priors+prior*4;
   float cx=(float)loc[i*4]*h->regression_scale*.1f*p[2]+p[0];
   float cy=(float)loc[i*4+1]*h->regression_scale*.1f*p[3]+p[1];
   float w=exponential[(int)loc[i*4+2]+128]*p[2],height=exponential[(int)loc[i*4+3]+128]*p[3];
   candidate c={{clip(cx-w*.5f),clip(cy-height*.5f),clip(cx+w*.5f),clip(cy+height*.5f),score,0},prior};
   if(c.box.x1>=c.box.x2||c.box.y1>=c.box.y2)continue;
   unsigned at=0;
   while(at<count&&(sorted[at].box.score>score||(sorted[at].box.score==score&&sorted[at].prior>prior)))at++;
   if(at==CANDIDATES)continue;
   if(count<CANDIDATES)count++;
   for(unsigned j=count-1;j>at;j--)sorted[j]=sorted[j-1];
   sorted[at]=c;
  }
 }
 unsigned kept=0;uint8_t removed[CANDIDATES];memset(removed,0,sizeof(removed));
 for(unsigned i=0;i<count&&kept<capacity;i++)if(!removed[i]){
  boxes[kept++]=sorted[i].box;
  for(unsigned j=i+1;j<count;j++)if(!removed[j]&&suppress(&sorted[i].box,&sorted[j].box))removed[j]=1;
 }
 return kept;
}
