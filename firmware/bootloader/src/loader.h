#ifndef NIGO_NETWORK_LOADER_H
#define NIGO_NETWORK_LOADER_H
#include "ngu_upload.h"

#define NGB_HEADER 32u
#define NGB_LOAD UINT32_C(0x82000000)
#define NGB_LIMIT (2u*1024u*1024u)
#define NGB_STAGE UINT32_C(0x94000000)
#define NGB_CONTROL 24u
#define NGB_REPLY 32u
#define NGB_EXECUTE_GRACE_MS 300u
enum { NGB_QUERY=1, NGB_EXECUTE=2 };

typedef struct {
    ngu_upload upload;
    uint8_t *stage, *destination;
    void (*publish)(void *);
    void *publish_context;
    uint32_t ready, entry, payload_bytes, payload_crc;
    uint32_t image_source, image_session, image_port;
    uint32_t incoming_source, incoming_port;
    uint32_t execute_pending, execute_deadline, execute_sequence;
} ngb_loader;

void ngb_init(ngb_loader *, uint8_t *stage, uint8_t *destination,
              void (*publish)(void *), void *context);
/* An NGU1 transfer carries a 32-byte NGB1 header followed by an RV32 binary.
 * Header words are big endian: magic, version, load, entry, size, CRC, flags, reserved.
 * No destination write occurs until both upload CRC and header/payload validation pass. */
size_t ngb_upload(ngb_loader *, uint32_t source, uint16_t port,
                  const uint8_t *, size_t, uint8_t ack[NGU_ACK]);
/* NGBX + version/op/session/sequence/reserved; replies NGBR + version/op/status/
 * session/sequence/entry/payload CRC. Source IP/port and committed session own execution. */
size_t ngb_control(ngb_loader *, uint32_t source, uint16_t port, const uint8_t *,
                   size_t, uint8_t reply[NGB_REPLY], uint32_t now_ms);
int ngb_jump_due(const ngb_loader *, uint32_t now_ms);
void ngb_cancel(ngb_loader *);
#endif
