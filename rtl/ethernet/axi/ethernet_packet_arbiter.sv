`timescale 1ns/1ps
`default_nettype none
// Packet lock includes descriptor AND payload. Round-robin at packet boundary.
module ethernet_packet_arbiter(
 input wire clk,reset,
 input wire [79:0] a_desc,input wire a_desc_valid,output wire a_desc_ready,
 input wire [31:0] a_data,input wire [3:0] a_keep,input wire a_valid,output wire a_ready,input wire a_last,a_bad,
 input wire [79:0] b_desc,input wire b_desc_valid,output wire b_desc_ready,
 input wire [31:0] b_data,input wire [3:0] b_keep,input wire b_valid,output wire b_ready,input wire b_last,b_bad,
 output wire [79:0] m_desc,output wire m_desc_valid,input wire m_desc_ready,
 output wire [31:0] m_data,output wire [3:0] m_keep,output wire m_valid,input wire m_ready,output wire m_last,m_bad
);
 reg [1:0] state;reg selected,prefer_b;
 assign m_desc=selected?b_desc:a_desc;
 assign m_desc_valid=state==1 && (selected?b_desc_valid:a_desc_valid);
 assign a_desc_ready=state==1 && !selected && m_desc_ready;
 assign b_desc_ready=state==1 && selected && m_desc_ready;
 assign m_data=selected?b_data:a_data;assign m_keep=selected?b_keep:a_keep;
 assign m_valid=state==2 && (selected?b_valid:a_valid);
 assign m_last=selected?b_last:a_last;assign m_bad=selected?b_bad:a_bad;
 assign a_ready=state==2 && !selected && m_ready;assign b_ready=state==2 && selected && m_ready;
 always @(posedge clk)begin
    if(reset)begin state<=0;selected<=0;prefer_b<=0;end
    else case(state)
      0:if(a_desc_valid || b_desc_valid)begin selected<=b_desc_valid && (!a_desc_valid || prefer_b);state<=1;end
      1:if(m_desc_valid && m_desc_ready)state<=2;
      2:if(m_valid && m_ready && m_last)begin state<=0;prefer_b<=!selected;end
      default:state<=0;
    endcase
 end
endmodule
`default_nettype wire
