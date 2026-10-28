`timescale 1ns/1ps
`default_nettype none
// Owns the existing DMA only while sending a DDR image. No new AXI master.
// Frame cancellation flushes the pixel ingress at BOTH ends; packetizer abort
// still finishes an already-visible UDP packet. Accepted DDR reads always drain.
module ethernet_soc_dma_link(
 input wire clk,reset,network_ready,cpu_start,
 input wire job_valid,job_abort,input wire [31:0] job_base,job_stride,
 input wire [15:0] job_width,job_height,output wire job_ready,
 output reg owner,job_done,job_error,
 output wire image_start_valid,input wire image_start_ready,image_done,image_error,
 output wire image_abort,
 output wire dma_start,dma_local_reset,output wire [31:0] dma_base,dma_stride,
 output wire [15:0] dma_width,dma_height,
 input wire [31:0] dma_status,input wire dma_done_irq,dma_error_irq,
 input wire [31:0] dma_tdata,input wire [3:0] dma_tkeep,input wire dma_tvalid,output wire dma_tready,
 input wire dma_tlast,dma_tuser,
 output wire [31:0] image_tdata,output wire [3:0] image_tkeep,output wire image_tvalid,
 input wire image_tready,output wire image_tlast,image_tuser,
 input wire dma_arvalid,dma_arready,dma_rvalid,dma_rready,dma_rlast
);
 wire adapter_ready,adapter_idle,adapter_done,adapter_error,adapter_reset;
 reg memory_complete,packet_complete,failed;
 wire cancel=job_abort || !network_ready || image_error || dma_error_irq || adapter_error;
 wire grant_enable=!owner && !cpu_start && network_ready && !job_abort;
 assign job_ready=grant_enable && adapter_ready && image_start_ready;
 assign image_start_valid=grant_enable && adapter_ready && job_valid;
 assign image_abort=owner && (failed || cancel);
 assign dma_local_reset=owner && adapter_reset;
 wire slice_ready;
 assign dma_tready=image_abort?1'b1:slice_ready;
 vision_stream_adapter u_pixel_ingress(
  .clk(clk),.reset(reset || image_abort),
  .s_tdata(dma_tdata),.s_tkeep(dma_tkeep),.s_tvalid(dma_tvalid && owner && !image_abort),.s_tready(slice_ready),
  .s_tlast(dma_tlast),.s_tuser(dma_tuser),
  .m_tdata(image_tdata),.m_tkeep(image_tkeep),.m_tvalid(image_tvalid),.m_tready(image_tready),
  .m_tlast(image_tlast),.m_tuser(image_tuser));
 ethernet_dma_job_adapter u_job(
  .clk(clk),.reset(reset),.job_valid(job_valid && grant_enable && image_start_ready),
  .abort(image_abort),.job_ready(adapter_ready),.idle(adapter_idle),
  .job_base(job_base),.job_stride(job_stride),.job_width(job_width),.job_height(job_height),
  .done(adapter_done),.error(adapter_error),.dma_start(dma_start),.dma_local_reset(adapter_reset),
  .dma_base(dma_base),.dma_stride(dma_stride),.dma_width(dma_width),.dma_height(dma_height),
  .dma_status(dma_status),.dma_done_irq(dma_done_irq && owner),.dma_error_irq(dma_error_irq && owner),
  .dma_axis_valid(dma_tvalid),.dma_arvalid(dma_arvalid && owner),.dma_arready(dma_arready),
  .dma_rvalid(dma_rvalid && owner),.dma_rready(dma_rready),.dma_rlast(dma_rlast));
 always @(posedge clk)begin
  if(reset)begin owner<=0;job_done<=0;job_error<=0;memory_complete<=0;packet_complete<=0;failed<=0;end
  else begin
   job_done<=0;job_error<=0;
   if(job_valid && job_ready)begin owner<=1;memory_complete<=0;packet_complete<=0;failed<=0;end
   if(owner)begin
    if(adapter_done)memory_complete<=1;
    if(image_done)packet_complete<=1;
    if(cancel)failed<=1;
    if(adapter_idle && ((failed || cancel) || (memory_complete && packet_complete)))begin
     owner<=0;
     if(failed || cancel)job_error<=1;else job_done<=1;
    end
   end
  end
 end
endmodule
`default_nettype wire
