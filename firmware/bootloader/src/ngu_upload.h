#ifndef NGU_UPLOAD_H
#define NGU_UPLOAD_H
#include <stdint.h>
#include <stddef.h>
enum {NGU_OK=0,NGU_BAD=1,NGU_BUSY=2,NGU_ORDER=3,NGU_CRC=4,NGU_SIZE=5,NGU_OWNER=6};
enum {NGU_BEGIN=1,NGU_DATA=2,NGU_COMMIT=3,NGU_ABORT=4};
#define NGU_HEADER 32u
#define NGU_ACK 24u
#define NGU_CHUNK 224u
#define NGU_MODEL_MAX (2u*1024u*1024u)
#define NGU_FRAME_BYTES (320u*240u*3u)
typedef struct {
 /* begin returns NGU_BUSY without disturbing an active inference/model.
  * store writes a private buffer; commit atomically publishes a checked blob.
  * kind 1=model, 2=RGB888 frame, fixed 320x240. */
 int (*begin)(void *,unsigned kind,uint32_t bytes,uint32_t frame_id,uint32_t timestamp);
 void (*store)(void *,uint32_t offset,const uint8_t *,size_t);
 int (*commit)(void *,unsigned kind,uint32_t frame_id,uint32_t timestamp);
 void (*abort)(void *);
 void *context;
} ngu_sink;
typedef struct {
 ngu_sink sink;
 uint32_t source,session,total,offset,expected_crc,running_crc,timestamp,last_crc;
 uint32_t last_source,last_session,last_sequence;
 uint16_t port,last_port;
 unsigned active,kind,last_valid;
 uint8_t last_ack[NGU_ACK];
} ngu_upload;
void ngu_init(ngu_upload *,const ngu_sink *);
/* Return 24 for an ACK, 0 for a packet too short/unrecognizable to answer.
 * Caller serializes control mailbox access and sends ACK to source UDP port.
 * Call ngu_cancel on link loss/session timeout, never publish a partial frame. */
size_t ngu_handle(ngu_upload *,uint32_t source,uint16_t port,const uint8_t *,size_t,uint8_t ack[NGU_ACK]);
void ngu_cancel(ngu_upload *);
uint32_t ngu_crc32(uint32_t state,const void *,size_t);
#endif
