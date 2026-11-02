#ifndef NIGO_ARCADE_PROTOCOL_H
#define NIGO_ARCADE_PROTOCOL_H
#include <stdint.h>
#include <stddef.h>
typedef struct {uint32_t peer,port,session,last_seen,frame,total,offset,crc;uint8_t *encoded;} ArcadeStream;
/* NGGQ: version, op(1 subscribe/2 stop/3 query), sequence, session, reserved. */
size_t arcade_request(ArcadeStream *,const uint8_t *,size_t,uint32_t peer,uint16_t port,uint32_t now,
                     uint32_t mode,uint32_t selected,uint32_t keys,uint32_t score,uint8_t reply[64]);
size_t arcade_packet(ArcadeStream *,uint8_t packet[256]);
#endif
