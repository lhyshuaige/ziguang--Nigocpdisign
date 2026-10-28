`timescale 1ns/1ps
`default_nettype none
// Control-only owner of the EXISTING DMA MM2S. No AXI master or data mover here.
// Derived from this project's proven hdmi_dma_job_adapter drain contract.
// On abort the integration must drive DMA AXIS TREADY=1 to discard old pixels;
// assert image_abort to finish any visible UDP packet before starting a new job.
module ethernet_dma_job_adapter(
 input wire clk,reset,input wire job_valid,abort,output wire job_ready,idle,
 input wire [31:0] job_base,job_stride,input wire [15:0] job_width,job_height,
 output reg done,error,output wire dma_start,dma_local_reset,
 output reg [31:0] dma_base,dma_stride,output reg [15:0] dma_width,dma_height,
 input wire [31:0] dma_status,input wire dma_done_irq,dma_error_irq,dma_axis_valid,
 input wire dma_arvalid,dma_arready,dma_rvalid,dma_rready,dma_rlast
);
 localparam [2:0] IDLE=0,START=1,ACTIVE=2,REARM=3,SETTLE=4;
 reg [2:0] state;reg pending,aborted;
 wire begin_read=dma_arvalid && dma_arready,end_read=dma_rvalid && dma_rready && dma_rlast;
 wire quiet=!dma_status[0] && !dma_axis_valid && !dma_arvalid && !pending;
 assign idle=!reset && state==IDLE && quiet;assign job_ready=idle && !abort;
 assign dma_start=state==START && !abort && !reset;
 assign dma_local_reset=reset || state==REARM;
 always @(posedge clk)begin
  if(reset)begin state<=IDLE;pending<=0;aborted<=0;dma_base<=0;dma_stride<=0;dma_width<=0;dma_height<=0;done<=0;error<=0;end
  else begin
   done<=0;error<=0;
   case({begin_read,end_read})2'b10:pending<=1;2'b01:pending<=0;default:;endcase
   case(state)
    IDLE:if(job_valid && job_ready)begin
      dma_base<=job_base;dma_stride<=job_stride;dma_width<=job_width;dma_height<=job_height;aborted<=0;state<=START;
    end
    START:if(abort)begin aborted<=1;error<=1;state<=REARM;end else state<=ACTIVE;
    ACTIVE:begin
      if(abort && !aborted)begin aborted<=1;error<=1;end
      if(dma_error_irq)begin error<=1;aborted<=1;end
      if(dma_done_irq && !aborted && !abort && !dma_error_irq)done<=1;
      if(quiet)state<=REARM;
    end
    REARM:state<=SETTLE;SETTLE:state<=IDLE;default:state<=IDLE;
   endcase
  end
 end
endmodule
`default_nettype wire
