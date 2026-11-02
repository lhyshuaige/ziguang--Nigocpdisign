#ifndef NIGO_ETHERNET_H
#define NIGO_ETHERNET_H
#include <stdint.h>
#include <stddef.h>
typedef struct {
    volatile uint32_t *base;
    uint32_t active_mode, last_sequence, last_status;
    uint32_t last_source_ip, last_source_port, last_requested_mode;
    int have_sequence;
} nigo_eth;
/* Callback performs mode changes at a frame boundary. Return zero on success;
 * return a nonzero application status for unsupported/busy modes (e.g. CNN). */
typedef uint32_t (*nigo_mode_fn)(uint32_t mode, void *context);
void nigo_eth_open(nigo_eth *eth, uintptr_t csr_base);
int nigo_eth_configure(nigo_eth *eth, uint64_t mac, uint32_t ip,
                       uint32_t mask, uint32_t gateway, unsigned timeout);
int nigo_eth_ready(nigo_eth *eth);
/* Poll or call from deferred IRQ work. No image copying. One short command per call. */
int nigo_eth_service(nigo_eth *eth, nigo_mode_fn apply_mode, void *context);
/* Images: configure existing DMA MM2S and Ethernet image job in integration
 * controller. Hold DDR buffer until both DMA memory completion AND packetizer
 * completion. Flush/link loss: drain accepted AXI reads before rearming DMA. */
#endif
