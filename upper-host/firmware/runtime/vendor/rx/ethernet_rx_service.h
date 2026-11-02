#ifndef NIGO_ETHERNET_RX_SERVICE_H
#define NIGO_ETHERNET_RX_SERVICE_H
#include "ethernet_rx.h"
/* Optional dedicated receiver demo. Owns the UDP5001 mailbox; do not call
 * nigo_eth_service or the UltraFace upload service on that mailbox concurrently.
 * No image bytes pass through this service. Buffers are CPU-allocated constants. */
typedef struct {
    nigo_rx *rx,mailbox;
    nigo_rx_job job;
    nigo_rx_frame acquired;
    uint32_t allowed_peer,last_ip,last_ports,last_seq;
    uint8_t request[32],last_request[32],ack[64];
    int have_request,have_frame;
} nigo_rx_service;
void nigo_rx_service_open(nigo_rx_service *,nigo_rx *,uintptr_t,const nigo_rx_job *,uint32_t);
/* Poll in main/deferred IRQ work. One bounded control transaction per call. */
int nigo_rx_service_poll(nigo_rx_service *);
#endif
