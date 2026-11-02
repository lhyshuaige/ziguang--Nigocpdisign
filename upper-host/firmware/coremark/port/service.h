#ifndef NIGO_CM_SERVICE_H
#define NIGO_CM_SERVICE_H
#include <stddef.h>
#include <stdint.h>
typedef struct {uint32_t run_id,state,iterations,log_crc;} cm_service;
/* NCQ1 request: version, operation, sequence, run ID, argument. */
size_t cm_request(cm_service *,const uint8_t *,size_t,uint8_t *);
uint32_t cm_crc32(const void *,size_t);
#endif
