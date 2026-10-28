#ifndef ULTRAFACE_RUNTIME_H
#define ULTRAFACE_RUNTIME_H
#include "nigo_ai.h"
typedef struct {
 uint32_t magic,version,bytes,layers,layer_offset,head_offset,prior_offset,priors;
 uint32_t tensor_bytes,arena_bytes,heads,input_bytes,reserved[4];
} uf_header;
typedef struct {
 int32_t id,source,h,w,ci,oh,ow,co,k,stride,pad,dw,relu,count;
 uint32_t weights,weight_bytes,bias,mult,jobs,tensor,tensor_bytes;
 float scale;uint32_t reserved[2];
} uf_layer;
typedef struct {
 uint32_t classification,regression,count,first_prior,confidence,exponential;
 float regression_scale;uint32_t reserved;
} uf_head;
typedef struct {uint32_t descriptor[22];int32_t y,x,h,w,ci,co,ni,no,ih,iw,iy,ix;} uf_job;
typedef struct {
 const uint8_t *model;const uf_header *header;const uf_layer *layers;
 uint8_t *arena;int8_t *tensors;uint32_t arena_address;
 nigo_ai *ai;void (*cache_sync)(void *);void *cache_context;
 unsigned state,layer,job,submitted,failed;
 uint32_t completion_start,frame_id;
} uf_runtime;
/* Frozen model CRC is checked before interpreting any records. All work areas
 * must remain private until uf_poll returns completion/error and hardware idle.
 * cache_sync MUST write back and invalidate CPU data cache, and wait for drain. */
int uf_bind(uf_runtime *,const void *model,size_t model_bytes,nigo_ai *,
            void *arena,size_t arena_bytes,uint32_t arena_address,
            void *tensors,size_t tensor_bytes,void (*cache_sync)(void *),void *cache_context);
int uf_start(uf_runtime *,const uint8_t *rgb888,uint32_t frame_id);
/* 0=in progress, 1=completed, -1=failed and drained; -2=not running.
 * No timeout releases DMA buffers: platform reset is required for a hung bus. */
int uf_poll(uf_runtime *);
typedef struct {float x1,y1,x2,y2,score;uint16_t track_id;} uf_box;
/* Confidence >.7, hard NMS IoU .3, top 200 pre-NMS, at most capacity returned.
 * Coordinates are normalized. No host/PC neural inference is performed. */
unsigned uf_decode(const uf_runtime *,uf_box *boxes,unsigned capacity);
#endif
