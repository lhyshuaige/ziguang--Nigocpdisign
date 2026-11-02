`timescale 1ns/1ps
`default_nettype none
module ethernet_pixel_unpacker(
 input wire clk,reset,clear,start,input wire rgb565,input wire [15:0] width,
 input wire [31:0] s_data,input wire [3:0] s_keep,input wire s_valid,
 output wire s_ready,input wire s_last,
 output wire [31:0] m_data,output wire [3:0] m_keep,
 output wire m_valid,input wire m_ready,output wire m_last,m_user,m_packet_last,
 output wire idle
);
 reg [31:0] word_q;reg [2:0] bytes_q;reg packet_last_q;
 reg [15:0] x;reg first;
 wire [2:0] step=rgb565?2:1;
 assign s_ready=bytes_q==0;assign idle=bytes_q==0;
 assign m_valid=bytes_q!=0;assign m_data=rgb565?{16'd0,word_q[15:0]}:{24'd0,word_q[7:0]};
 assign m_keep=15;assign m_last=x==width-1'b1;assign m_user=first;
 assign m_packet_last=packet_last_q && bytes_q==step;
 always @(posedge clk)begin
  if(reset || clear || start)begin word_q<=0;bytes_q<=0;packet_last_q<=0;x<=0;first<=1;end
  else begin
   if(s_valid && s_ready)begin
    word_q<=s_data;bytes_q<=s_keep==15?4:s_keep==7?3:s_keep==3?2:1;packet_last_q<=s_last;
   end
   if(m_valid && m_ready)begin
    word_q<=word_q>>(rgb565?16:8);bytes_q<=bytes_q-step;
    x<=m_last?0:x+1'b1;first<=0;
   end
  end
 end
endmodule
`default_nettype wire
