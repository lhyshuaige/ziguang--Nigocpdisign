`timescale 1ns/1ps
`default_nettype none
// Periodic coherent snapshot; held bus settles before two-flop ack reaches host.
module ethernet_stats_cdc(
 input wire net_clk,net_reset,input wire [5:0] events,
 input wire sys_clk,sys_reset,output reg [191:0] statistics
);
 reg [31:0] counters[0:5];reg [191:0] held;
 reg request,ack;reg [7:0] timer;
 (* ASYNC_REG="TRUE", syn_preserve=1 *) reg [1:0] request_sync,ack_sync;
 integer i;
 always @(posedge net_clk)begin
  if(net_reset)begin for(i=0;i<6;i=i+1)counters[i]<=0;held<=0;ack<=0;request_sync<=0;end
  else begin
   request_sync<={request_sync[0],request};
   for(i=0;i<6;i=i+1)if(events[i])counters[i]<=counters[i]+1'b1;
   if(request_sync[1]!=ack)begin for(i=0;i<6;i=i+1)held[i*32+:32]<=counters[i];ack<=request_sync[1];end
  end
 end
 always @(posedge sys_clk)begin
  if(sys_reset)begin request<=0;ack_sync<=0;timer<=0;statistics<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};
   if(ack_sync[1]==request)begin
    statistics<=held;
    if(timer==255)begin request<=!request;timer<=0;end else timer<=timer+1'b1;
   end
  end
 end
endmodule
`default_nettype wire
