#include "ultraface_runtime.h"
#include "ngu_upload.h"
#include "model_asset.h"
#include <string.h>
_Static_assert(sizeof(uf_header)==64,"model header ABI");
_Static_assert(sizeof(uf_layer)==96,"layer ABI");
_Static_assert(sizeof(uf_head)==32,"head ABI");
_Static_assert(sizeof(uf_job)==136,"job ABI");
enum {IDLE=0,PACK=1,CLEAN=2,SUBMIT=3,WAIT=4,COLLECT=5,FAILED=6};
static const uf_job *jobs(const uf_runtime *r,const uf_layer *l){return (const uf_job *)(r->model+l->jobs);}
static int range(size_t total,uint32_t at,size_t n){return at<=total&&n<=total-at;}
int uf_bind(uf_runtime *r,const void *model,size_t bytes,nigo_ai *ai,void *arena,size_t arena_bytes,
 uint32_t address,void *tensors,size_t tensor_bytes,void (*sync)(void *),void *context){
 if(!model||bytes!=NIGO_MODEL_BYTES||((uintptr_t)model&3)||!sync||!arena||!tensors||!ai)return -1;
 if((ngu_crc32(0xffffffffu,model,bytes)^0xffffffffu)!=NIGO_MODEL_CRC32)return -1;
 const uf_header *h=model;
 if(h->magic!=0x314d474e||h->version!=1||h->bytes!=bytes||h->layers!=42||h->heads!=4||h->priors!=4420||
    h->input_bytes!=NGU_FRAME_BYTES||arena_bytes<h->arena_bytes||tensor_bytes<h->tensor_bytes||
    (address&31)||((uint64_t)address+h->arena_bytes)>UINT64_C(0xc0000000)||address<0x80000000u)return -1;
 if(!range(bytes,h->layer_offset,42*sizeof(uf_layer))||!range(bytes,h->head_offset,4*sizeof(uf_head))||
    !range(bytes,h->prior_offset,4420*16u))return -1;
 const uf_layer *layers=(const uf_layer *)((const uint8_t *)model+h->layer_offset);
 for(unsigned i=0;i<42;i++){
  const uf_layer *l=layers+i;
  if(l->id!=(int)i||l->source>=(int)i||l->source< -1||l->count<=0||l->count>2048||
     !range(bytes,l->jobs,(size_t)l->count*sizeof(uf_job))||!range(bytes,l->weights,l->weight_bytes)||
     !range(bytes,l->bias,(size_t)l->co*4)||!range(bytes,l->mult,(size_t)l->co*4)||
     !range(h->tensor_bytes,l->tensor,l->tensor_bytes))return -1;
  const uf_job *js=(const uf_job *)((const uint8_t *)model+l->jobs);
  for(int j=0;j<l->count;j++){
   const uf_job *v=js+j;
   if(v->descriptor[1]!=0x10000u+(unsigned)j*0x4000u||
      v->descriptor[2]!=0x10000u+(unsigned)l->count*0x4000u+(unsigned)j*0x1000u||
      !range(h->arena_bytes,v->descriptor[1],0x4000)||!range(h->arena_bytes,v->descriptor[2],0x1000)||
      v->ni<1||v->ni>8||v->no<1||v->no>8||v->ih<1||v->ih>32||v->iw<1||v->iw>32||
      v->h<1||v->w<1||v->h*v->w>256||v->ci<0||v->ci+v->ni>l->ci||v->co<0||v->co+v->no>l->co)return -1;
  }
 }
 memset(r,0,sizeof(*r));r->model=model;r->header=h;r->layers=layers;r->ai=ai;
 r->arena=arena;r->arena_address=address;r->tensors=tensors;r->cache_sync=sync;r->cache_context=context;
 return 0;
}
int uf_start(uf_runtime *r,const uint8_t *rgb,uint32_t frame_id){
 if(!r->header||r->state!=IDLE||(nigo_ai_status(r->ai)&1u)||!rgb)return -1;
 nigo_ai_ack(r->ai,1); /* frame starts only after the previous queue drained */
 for(unsigned i=0;i<NGU_FRAME_BYTES;i++){int v=(int)rgb[i]-127;r->tensors[i]=(int8_t)(v>127?127:v);}
 r->layer=0;r->job=0;r->submitted=0;r->failed=0;r->frame_id=frame_id;r->state=PACK;return 0;
}
static void pack_job(uf_runtime *r,const uf_layer *l,const uf_job *j){
 uint8_t *p=r->arena+j->descriptor[1],*start=p;
 const uint8_t *weight=r->model+l->weights;
 const int8_t *input=l->source<0?r->tensors:r->tensors+r->layers[l->source].tensor;
 for(int ky=0;ky<l->k;ky++)for(int kx=0;kx<l->k;kx++)for(int ic=0;ic<(l->dw?1:j->ni);ic++)for(int lane=0;lane<8;lane++){
  int oc=j->co+lane;uint8_t v=0;
  if(oc<l->co){unsigned at=l->dw?(unsigned)((oc*l->k+ky)*l->k+kx):
     (unsigned)(((oc*l->ci+j->ci+ic)*l->k+ky)*l->k+kx);v=weight[at];}
  *p++=v;
 }
 while((unsigned)(p-start)&31u)*p++=0;
 for(int y=0;y<j->ih;y++)for(int x=0;x<j->iw;x++)for(int lane=0;lane<8;lane++){
  int iy=j->iy+y,ix=j->ix+x;uint8_t v=0;
  if(iy>=0&&iy<l->h&&ix>=0&&ix<l->w&&lane<j->ni)v=(uint8_t)input[(iy*l->w+ix)*l->ci+j->ci+lane];
  *p++=v;
 }
 while((unsigned)(p-start)&31u)*p++=0;
}
static int submit_job(uf_runtime *r,const uf_layer *l,const uf_job *j){
 nigo_ai_job d;memcpy(d.word,j->descriptor,sizeof(d.word));d.word[1]+=r->arena_address;d.word[2]+=r->arena_address;
 d.q24_config=(uint8_t)(1|(l->relu?2:0));
 const int32_t *bias=(const int32_t *)(r->model+l->bias);const uint32_t *mult=(const uint32_t *)(r->model+l->mult);
 for(int i=0;i<8;i++){int c=j->co+i;d.bias[i]=c<l->co?bias[c]:0;d.multiplier[i]=c<l->co?mult[c]:0;}
 return nigo_ai_try_submit(r->ai,&d);
}
static void collect_job(uf_runtime *r,const uf_layer *l,const uf_job *j){
 if(!(j->descriptor[0]&(1u<<14)))return;
 const uint8_t *src=r->arena+j->descriptor[2];int8_t *dst=r->tensors+l->tensor;
 for(int y=0;y<j->h;y++)for(int x=0;x<j->w;x++)for(int lane=0;lane<j->no;lane++)
  dst[((j->y+y)*l->ow+j->x+x)*l->co+j->co+lane]=(int8_t)src[(y*j->w+x)*8+lane];
}
int uf_poll(uf_runtime *r){
 if(r->state==IDLE)return -2;
 const uf_layer *l=r->layers+r->layer;const uf_job *js=jobs(r,l);
 if(r->state==PACK){pack_job(r,l,js+r->job);if(++r->job==(unsigned)l->count){r->job=0;r->state=CLEAN;}}
 else if(r->state==CLEAN){r->cache_sync(r->cache_context);r->completion_start=nigo_ai_completions(r->ai);r->submitted=0;r->state=SUBMIT;}
 else if(r->state==SUBMIT){
  int v=submit_job(r,l,js+r->job);
  if(v<0){r->failed=1;r->state=FAILED;}
  else if(v==0){r->submitted++;if(++r->job==(unsigned)l->count)r->state=WAIT;}
 }else if(r->state==WAIT||r->state==FAILED){
  uint32_t status=nigo_ai_status(r->ai);if(status&4u)r->failed=1;
  if((uint32_t)(nigo_ai_completions(r->ai)-r->completion_start)>=r->submitted&&!(status&1u)){
   r->cache_sync(r->cache_context);
   if(r->failed){nigo_ai_ack(r->ai,1);r->state=IDLE;return -1;}
   r->job=0;r->state=COLLECT;
  }
 }else if(r->state==COLLECT){
  collect_job(r,l,js+r->job);
  if(++r->job==(unsigned)l->count){
   r->job=0;if(++r->layer==42){r->state=IDLE;return 1;}r->state=PACK;
  }
 }
 return 0;
}
