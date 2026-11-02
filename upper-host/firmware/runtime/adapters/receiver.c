#include "mode.h"
#include "ethernet_rx_service.h"
#include "ethernet.h"
void runtime_receiver(void){
 nigo_rx rx;nigo_rx_service service;
 nigo_rx_job layout={{0x94000000u,0x94100000u},0x100000u,0,0,0,0,0,0};
 nigo_rx_open(&rx,NIGO_RX_CSR_BASE,nigo_rx_nax_cache,0);
 nigo_rx_service_open(&service,&rx,0x10020000u,&layout,runtime_peer());
 int cancelling=0;
 for(;;){
  nigo_rx_progress p;nigo_rx_get_progress(&rx,&p);
  int safe=!(p.status&3u)&&p.states==0;
  if(runtime_poll(safe,safe?0:MODE_BUSY_RX,0))return;
  if(runtime_pending()){
   if(!cancelling){nigo_rx_cancel(&rx);cancelling=1;}
   if(!(p.status&3u)){
    if(p.status&32u)(void)nigo_rx_release(&rx);
    else if(p.status&16u){nigo_rx_frame f;if(!nigo_rx_take(&rx,&f))(void)nigo_rx_release(&rx);}
   }
   /* Keep buffers owned until cancel has drained and READY/READ are released. */
  }else if(runtime_application_rx_ready())nigo_rx_service_poll(&service);
 }
}
