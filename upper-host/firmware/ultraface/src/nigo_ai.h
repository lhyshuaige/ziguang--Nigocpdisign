#ifndef NIGO_AI_H
#define NIGO_AI_H
#include <stdint.h>
#include <stddef.h>
#define NIGO_AI_BASE ((uintptr_t)0x10010000u)
typedef uint32_t (*nigo_ai_read_fn)(void *,unsigned);
typedef void (*nigo_ai_write_fn)(void *,unsigned,uint32_t);
typedef struct {uint32_t word[22];int32_t bias[8];uint32_t multiplier[8];uint8_t q24_config;} nigo_ai_job;
typedef struct {
 void *context;nigo_ai_read_fn read;nigo_ai_write_fn write;
 uint32_t shadow[22],bias[8],multiplier[8],known;
 uint8_t bias_known,multiplier_known,config_known,config;
} nigo_ai;
/* Single owner for staging + doorbell. ISR only sets an event flag.
 * Caller cleans input DDR caches and invalidates output caches as appropriate.
 * IO fences do not perform cache maintenance. */
void nigo_ai_open(nigo_ai *,uintptr_t);
void nigo_ai_bind(nigo_ai *,void *,nigo_ai_read_fn,nigo_ai_write_fn);
void nigo_ai_invalidate_shadow(nigo_ai *);
/* 0 submitted; 1 queue full (no writes); -1 bad Q24; -2 sticky HW error. */
int nigo_ai_try_submit(nigo_ai *,const nigo_ai_job *);
uint32_t nigo_ai_status(nigo_ai *);
uint32_t nigo_ai_completions(nigo_ai *);
void nigo_ai_ack(nigo_ai *,int clear_error);
uint64_t nigo_ai_counter(nigo_ai *,unsigned low_offset);
#endif
