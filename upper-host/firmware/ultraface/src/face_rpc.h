#ifndef FACE_RPC_H
#define FACE_RPC_H
#include <stdint.h>
#include <stddef.h>
#define FACE_STATUS_WORDS 23u
/* Read-only status and owner/frame-qualified retained-result retrieval. */
size_t face_rpc_handle(const uint8_t *request,size_t bytes,uint32_t source,
 const uint32_t status[FACE_STATUS_WORDS],const uint8_t *result,size_t result_bytes,
 uint32_t result_source,uint32_t result_frame,uint8_t reply[256]);
#endif
