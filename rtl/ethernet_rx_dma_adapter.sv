`timescale 1ns/1ps
`default_nettype none
// Same-cycle elastic register; abort completes the fixed-size frame with zeros.
// It never resets a DMA which owns an accepted AXI write.
module ethernet_rx_dma_adapter(
 input wire clk,reset,clear,start,pad,input wire [15:0] width,height,
 input wire [31:0] s_data,input wire s_valid,output wire s_ready,
 output reg [31:0] m_data,output reg m_valid,input wire m_ready,
 output reg m_last,m_user,output wire [3:0] m_keep,
 output wire all_generated
);
 reg [15:0] x,y;reg active;
 wire space=!m_valid || m_ready;
 assign s_ready=active && space && !pad;
 assign m_keep=15;assign all_generated=!active;
 always @(posedge clk)begin
  if(reset || clear)begin active<=0;m_valid<=0;m_data<=0;m_last<=0;m_user<=0;x<=0;y<=0;end
  else if(start)begin active<=1;m_valid<=0;x<=0;y<=0;end
  else begin
   if(m_valid && m_ready)m_valid<=0;
   if(active && space && (pad || s_valid))begin
    m_valid<=1;m_data<=pad?0:s_data;m_user<=x==0 && y==0;m_last<=x==width-1'b1;
    if(x==width-1'b1)begin x<=0;if(y==height-1'b1)active<=0;else y<=y+1'b1;end
    else x<=x+1'b1;
   end
  end
 end
endmodule
`default_nettype wire
