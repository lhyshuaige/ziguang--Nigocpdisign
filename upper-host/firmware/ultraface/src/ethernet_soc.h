#ifndef NIGO_ETHERNET_SOC_H
#define NIGO_ETHERNET_SOC_H
#include "ethernet.h"
/* Current Nax PMA marks 0x1xxxxxxx as IO. Use this canonical CPU address;
 * 0x40020000 is only a native-decoder alias, not a CPU uncached MMIO alias. */
#define NIGO_ETHERNET_SOC_BASE ((uintptr_t)0x10020000u)
#define NIGO_ETHERNET_IMAGE_JOB_OFFSET 0x1000u
typedef struct {
    nigo_eth network;
    volatile uint32_t *image;
} nigo_eth_soc;
typedef struct {
    uint32_t ddr_base, stride_bytes;
    uint16_t width, height;
    uint32_t frame_id, timestamp, peer_ip;
    unsigned rgb565;
} nigo_eth_image;
/* Use a single deferred-IRQ/main-loop owner for these MMIO APIs. */
void nigo_eth_soc_open(nigo_eth_soc *soc, uintptr_t base);
/* Source must already be visible in DDR (normally produced by Vision/DMA).
 * CPU-written cached buffers require platform cache cleaning before submit;
 * an IO fence does not clean the data cache. No image data is copied here.
 * 0=queued, -1=busy, -2=invalid descriptor/range, -3=link not ready. */
int nigo_eth_image_submit(nigo_eth_soc *soc, const nigo_eth_image *image);
/* 0=idle/in progress, 1=complete, -1=failed; completion flags stay sticky.
 * Buffer ownership ends only after this terminal result. */
int nigo_eth_image_poll(nigo_eth_soc *soc);
void nigo_eth_image_abort(nigo_eth_soc *soc);
void nigo_eth_image_ack(nigo_eth_soc *soc);
/* Small inference/control results only, <=256 bytes, through the CPU mailbox.
 * The caller supplies the result representation and handles shared-DDR cache
 * coherence before reading hardware-produced data. Large images use DMA. */
int nigo_eth_result_send(nigo_eth_soc *soc, uint32_t peer_ip,
                         const void *payload, size_t bytes);
#endif
