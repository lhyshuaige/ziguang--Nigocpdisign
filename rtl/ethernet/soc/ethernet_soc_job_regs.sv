`timescale 1ns/1ps
`default_nettype none
// Ethernet image jobs at Ethernet CSR base + 0x1000. Descriptors stay immutable
// from START through both DMA drain and packetizer completion.
module ethernet_soc_job_regs(
 input wire clk,reset,network_ready,
 input wire [11:0] s_awaddr,input wire s_awvalid,output wire s_awready,
 input wire [31:0] s_wdata,input wire [3:0] s_wstrb,input wire s_wvalid,output wire s_wready,
 output reg [1:0] s_bresp,output reg s_bvalid,input wire s_bready,
 input wire [11:0] s_araddr,input wire s_arvalid,output wire s_arready,
 output reg [31:0] s_rdata,output reg [1:0] s_rresp,output reg s_rvalid,input wire s_rready,
 output wire job_valid,input wire job_ready,job_owner,job_done,job_error,
 output reg job_abort,output wire irq,
 output reg [31:0] job_base,job_stride,job_frame_id,job_frame_bytes,job_timestamp,job_peer_ip,
 output wire [15:0] job_width,job_height,output wire job_rgb565,
 input wire [31:0] image_packets,input wire rx_discard_packet
);
 reg aw_hold,w_hold,pending;
 reg [11:0] awaddr;
 reg [31:0] wdata,size_reg,format_reg,frames_done,frames_error,rx_discard;
 reg [3:0] wstrb;
 reg [1:0] irq_pending,irq_mask;
 // Completion pulses arrive from the owner one cycle before the sticky IRQ
 // update is visible. Keep BUSY asserted through that event so an AR accepted
 // at the boundary cannot return idle with neither DONE nor ERROR set.
 wire busy=pending || job_owner || job_done || job_error;
 wire write_fire=aw_hold && w_hold && !s_bvalid;
 wire abort_write=write_fire && awaddr==12'h008 && wstrb[0] && wdata[7:0]==8'h02;
 wire pending_cancel=(abort_write && pending && !job_ready) || (pending && !network_ready);
 wire start_link_error=write_fire && awaddr==12'h008 && wstrb[0] && wdata[7:0]==8'h01 &&
                       !busy && !invalid_descriptor && !network_ready;
 wire [1:0] irq_clear=(write_fire && awaddr==12'h010 && wstrb[0])?wdata[1:0]:2'b00;
 wire invalid_descriptor=(job_base[4:0]!=0) || (job_stride[4:0]!=0) ||
                         size_reg[15:0]==0 || size_reg[31:16]==0 ||
                         job_frame_bytes==0 || format_reg>1;
 assign job_valid=pending;assign job_width=size_reg[15:0];assign job_height=size_reg[31:16];
 assign job_rgb565=format_reg[0];assign irq=|(irq_pending & irq_mask);
 assign s_awready=!reset && !aw_hold && !s_bvalid;
 assign s_wready=!reset && !w_hold && !s_bvalid;
 assign s_arready=!reset && !s_rvalid;
 function [31:0] merge_bytes;
  input [31:0] old_data,new_data;input [3:0] strobe;
  integer i;
  begin merge_bytes=old_data;for(i=0;i<4;i=i+1)if(strobe[i])merge_bytes[i*8+:8]=new_data[i*8+:8];end
 endfunction
 always @(posedge clk)begin
  if(reset)begin
   aw_hold<=0;w_hold<=0;awaddr<=0;wdata<=0;wstrb<=0;s_bvalid<=0;s_bresp<=0;s_rvalid<=0;s_rdata<=0;s_rresp<=0;
   pending<=0;job_abort<=0;irq_pending<=0;irq_mask<=0;
   job_base<=0;job_stride<=0;size_reg<=0;format_reg<=0;job_frame_id<=0;job_frame_bytes<=0;job_timestamp<=0;job_peer_ip<=32'hc0a80164;
   frames_done<=0;frames_error<=0;rx_discard<=0;
  end else begin
   job_abort<=0;
   irq_pending<=(irq_pending & ~irq_clear) | {job_error || pending_cancel || start_link_error,job_done};
   if(job_done)frames_done<=frames_done+1'b1;
   if(job_error || pending_cancel || start_link_error)frames_error<=frames_error+1'b1;
   if(rx_discard_packet)rx_discard<=rx_discard+1'b1;
   if(job_valid && job_ready)pending<=0;
   if(pending && !network_ready)pending<=0;
   if(s_awvalid && s_awready)begin aw_hold<=1;awaddr<=s_awaddr;end
   if(s_wvalid && s_wready)begin w_hold<=1;wdata<=s_wdata;wstrb<=s_wstrb;end
   if(s_bvalid && s_bready)s_bvalid<=0;
   if(s_rvalid && s_rready)s_rvalid<=0;
   if(write_fire)begin
    aw_hold<=0;w_hold<=0;s_bvalid<=1;s_bresp<=0;
    if(awaddr[1:0]!=0)s_bresp<=2'b10;
    else case(awaddr)
     12'h008:if(wstrb[0])begin
      if(wdata[7:2]!=0 || wdata[1:0]==2'b11)s_bresp<=2'b10;
      else if(wdata[1])begin job_abort<=1;pending<=0;end
      else if(wdata[0])begin
       if(busy || invalid_descriptor)s_bresp<=2'b10;
       // Link loss is a normal runtime job error, not a CPU bus fault.
       else if(network_ready)pending<=1;
      end
     end
     12'h00c:if(wstrb[0])irq_mask<=wdata[1:0];
     12'h010:;
     12'h020,12'h024,12'h028,12'h02c,12'h030,12'h034,12'h038,12'h03c:
      if(busy)s_bresp<=2'b10;
      else case(awaddr)
       12'h020:job_base<=merge_bytes(job_base,wdata,wstrb);
       12'h024:job_stride<=merge_bytes(job_stride,wdata,wstrb);
       12'h028:size_reg<=merge_bytes(size_reg,wdata,wstrb);
       12'h02c:format_reg<=merge_bytes(format_reg,wdata,wstrb);
       12'h030:job_frame_id<=merge_bytes(job_frame_id,wdata,wstrb);
       12'h034:job_frame_bytes<=merge_bytes(job_frame_bytes,wdata,wstrb);
       12'h038:job_timestamp<=merge_bytes(job_timestamp,wdata,wstrb);
       12'h03c:job_peer_ip<=merge_bytes(job_peer_ip,wdata,wstrb);
       default:;
      endcase
     default:s_bresp<=2'b10;
    endcase
   end
   if(s_arvalid && s_arready)begin
    s_rvalid<=1;s_rresp<=0;s_rdata<=0;
    if(s_araddr[1:0]!=0)s_rresp<=2'b10;
    else case(s_araddr)
     12'h000:s_rdata<=32'h45544a31;
     12'h004:s_rdata<={27'b0,network_ready,job_owner,irq_pending[1],irq_pending[0],busy};
     12'h008:s_rdata<={31'b0,pending};
     12'h00c:s_rdata<={30'b0,irq_mask};
     12'h010:s_rdata<={30'b0,irq_pending};
     12'h020:s_rdata<=job_base;
     12'h024:s_rdata<=job_stride;
     12'h028:s_rdata<=size_reg;
     12'h02c:s_rdata<=format_reg;
     12'h030:s_rdata<=job_frame_id;
     12'h034:s_rdata<=job_frame_bytes;
     12'h038:s_rdata<=job_timestamp;
     12'h03c:s_rdata<=job_peer_ip;
     12'h040:s_rdata<=image_packets;
     12'h044:s_rdata<=frames_done;
     12'h048:s_rdata<=frames_error;
     12'h04c:s_rdata<=rx_discard;
     default:s_rresp<=2'b10;
    endcase
   end
  end
 end
endmodule
`default_nettype wire
