#ifndef FACE_EVENTS_H
#define FACE_EVENTS_H
#include "ultraface_runtime.h"
#define FACE_MAX 16u
#ifndef FACE_ENTER_HITS
#define FACE_ENTER_HITS 2u
#endif
#ifndef FACE_LEAVE_MISSES
#define FACE_LEAVE_MISSES 3u
#endif
typedef struct {uf_box previous[FACE_MAX];unsigned count,hits,misses,present;uint16_t next_id;} face_events;
/* Detection-to-detection association; this is not an inter-frame image tracker. */
unsigned face_events_update(face_events *,uf_box *,unsigned count);
size_t face_result_encode(uint8_t out[224],uint32_t frame,uint32_t timestamp,uint32_t sequence,
                          uint32_t duration_ms,const uf_box *,unsigned count,unsigned event,unsigned error);
#endif
