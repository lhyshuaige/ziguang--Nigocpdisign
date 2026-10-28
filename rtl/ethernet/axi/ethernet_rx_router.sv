`timescale 1ns/1ps
`default_nettype none
module ethernet_rx_router(
 input wire clk,reset,input wire [15:0] control_port,data_port,
 input wire [79:0] s_desc,input wire s_desc_valid,output wire s_desc_ready,
 input wire [31:0] s_data,input wire [3:0] s_keep,input wire s_valid,output wire s_ready,input wire s_last,s_bad,
 output wire [79:0] cpu_desc,output wire cpu_desc_valid,input wire cpu_desc_ready,
 output wire [31:0] cpu_data,output wire [3:0] cpu_keep,output wire cpu_valid,input wire cpu_ready,output wire cpu_last,
 output wire [79:0] dma_desc,output wire dma_desc_valid,input wire dma_desc_ready,
 output wire [31:0] dma_data,output wire [3:0] dma_keep,output wire dma_valid,input wire dma_ready,output wire dma_last,dma_bad,
 output reg dropped,control_dropped,packet_done
);
 reg [2:0] state;reg [79:0] desc;
 assign s_desc_ready=state==0;assign cpu_desc=desc;assign dma_desc=desc;
 assign cpu_desc_valid=state==1;assign dma_desc_valid=state==2;
 assign cpu_data=s_data;assign cpu_keep=s_keep;assign cpu_last=s_last;
 assign dma_data=s_data;assign dma_keep=s_keep;assign dma_last=s_last;assign dma_bad=s_bad;
 assign cpu_valid=state==3 && s_valid;assign dma_valid=state==4 && s_valid;
 assign s_ready=state==5 || (state==3 && cpu_ready) || (state==4 && dma_ready);
 always @(posedge clk)begin
   if(reset)begin state<=0;desc<=0;dropped<=0;control_dropped<=0;packet_done<=0;end
   else begin
    dropped<=0;control_dropped<=0;packet_done<=0;
    case(state)
      0:if(s_desc_valid)begin
        desc<=s_desc;
        if(s_desc[47:32]==control_port && s_desc[79:64]<=256 && cpu_desc_ready)state<=1;
        else if(s_desc[47:32]==data_port)state<=2;
        else begin state<=5;dropped<=1;if(s_desc[47:32]==control_port)control_dropped<=1;end
      end
      1:if(cpu_desc_ready)state<=3;
      2:if(dma_desc_ready)state<=4;
      3,4,5:if(s_valid && s_ready && s_last)begin state<=0;packet_done<=1;end
      default:state<=0;
    endcase
   end
 end
endmodule
`default_nettype wire
