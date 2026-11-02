#ifndef NIGO_ETHERNET_RX_H
#define NIGO_ETHERNET_RX_H
#include <stdint.h>
#include <stddef.h>
#define NIGO_RX_CSR_BASE ((uintptr_t)0x10021800u)
enum { NIGO_RX_OK=0, NIGO_RX_INVALID=-1, NIGO_RX_BUSY=-2,
       NIGO_RX_LINK_DOWN=-3, NIGO_RX_HARDWARE=-4, NIGO_RX_CACHE_REQUIRED=-5 };
enum { NIGO_RX_PREPARE=0, NIGO_RX_ACQUIRE=1 };
typedef uint32_t (*nigo_rx_read_fn)(void *,unsigned);
typedef void (*nigo_rx_write_fn)(void *,unsigned,uint32_t);
/* PREPARE must clean+invalidate before DMA; ACQUIRE invalidates before CPU
 * reads. The caller must not write a FILL/READY slot, including cached aliases.
 * This SoC is not cache coherent. A null callback is intentionally rejected. */
typedef void (*nigo_rx_cache_fn)(void *,unsigned);
typedef struct {
    uintptr_t base;
    nigo_rx_read_fn read;
    nigo_rx_write_fn write;
    nigo_rx_cache_fn cache;
    void *io_context,*cache_context;
} nigo_rx;
typedef struct {
    uint32_t base[2],capacity,stride,id,peer_ip;
    uint16_t width,height;
    uint8_t rgb565;
} nigo_rx_job;
typedef struct {
    uint32_t base,stride,id;
    uint16_t width,height;
    uint8_t rgb565,slot;
} nigo_rx_frame;
typedef struct {
    uint32_t status,events,offset,frames_ok,frames_bad,packets_ok,packets_bad,states;
} nigo_rx_progress;
void nigo_rx_open(nigo_rx *,uintptr_t,nigo_rx_cache_fn,void *);
int nigo_rx_arm(nigo_rx *,const nigo_rx_job *);
void nigo_rx_get_progress(nigo_rx *,nigo_rx_progress *);
int nigo_rx_take(nigo_rx *,nigo_rx_frame *);
int nigo_rx_release(nigo_rx *);
/* Nonblocking. Ownership remains with RX until busy and pending both clear. */
void nigo_rx_cancel(nigo_rx *);
#if defined(__riscv)
/* Verified NaxRiscvContest FLUSH_DATA instruction, all-cache writeback+invalidate. */
void nigo_rx_nax_cache(void *,unsigned);
#endif
#endif
