#ifndef NIGO_MODE_H
#define NIGO_MODE_H
#include <stddef.h>
#include <stdint.h>
enum { MODE_IDLE,MODE_RX,MODE_AI,MODE_COREMARK,MODE_GAME,MODE_KEYS,MODE_COUNT };
enum { MODE_BUSY_AI=1,MODE_BUSY_UPLOAD=2,MODE_BUSY_RESULT=4,MODE_BUSY_RX=8,MODE_BUSY_CM=16,MODE_BUSY_TX=32 };
typedef struct {
 uint32_t active,target,generation,busy,flags,build;
 uint32_t peer,port,session,sequence,last_target,last_generation,have_last;
} mode_state;
size_t mode_request(mode_state *,const uint8_t *,size_t,uint32_t,uint16_t,uint8_t *);
int mode_commit(mode_state *,int safe,int tx_idle);
/* Called only outside benchmark timing and at application safe points.
 * Non-management mailbox packets are left for the current application. */
int runtime_poll(int safe,uint32_t busy,uint32_t flags);
int runtime_pending(void);
/* The RX packet is immutable while full. Check this at the consumer's read
 * point, not only at the start of an application iteration. */
int runtime_application_rx_ready(void);
uint32_t runtime_peer(void);
void runtime_mode_changed(uint32_t mode);
void runtime_game(void);void runtime_face(void);void runtime_coremark(void);void runtime_receiver(void);
#endif
