`timescale 1ns/1ps
`default_nettype none
// Completion publishes only after DMA DONE. Abort never exposes a partial frame.
module frame_buffer_manager(
 input wire clk,reset,input wire allocate,output wire available,output wire allocation_slot,
 input wire finish,failed,input wire finish_slot,
 input wire take,output wire ready_valid,output wire ready_slot,
 input wire release_valid,release_slot,output reg protocol_error,
 output wire [3:0] states
);
 localparam FREE=0,FILL=1,READY=2,READ=3;
 reg [1:0] a,b;reg head;
 assign available=a==FREE || b==FREE;assign allocation_slot=a!=FREE;
 assign ready_valid=(head?b:a)==READY;assign ready_slot=head;
 assign states={b,a};
 always @(posedge clk)begin
  if(reset)begin a<=FREE;b<=FREE;head<=0;protocol_error<=0;end
  else begin
   if(allocate)begin
    if(!available)protocol_error<=1;
    else if(!allocation_slot)a<=FILL;else b<=FILL;
   end
   if(finish)begin
    if((finish_slot?b:a)!=FILL)protocol_error<=1;
    else if(!finish_slot)a<=failed?FREE:READY;else b<=failed?FREE:READY;
   end
   if(take)begin
    if(!ready_valid)protocol_error<=1;
    else if(!ready_slot)a<=READ;else b<=READ;
   end
   if(release_valid)begin
    if((release_slot?b:a)!=READ)protocol_error<=1;
    else if(!release_slot)a<=FREE;else b<=FREE;
   end
   // Preserve the READY descriptor while its consumer is stalled. New frames
   // append behind the current head, including simultaneous publish and take.
   if(take && ready_valid)begin
    if((head?a:b)==READY)head<=!head;
    else if(finish && !failed)head<=finish_slot;
   end else if(finish && !failed && !ready_valid)head<=finish_slot;
  end
 end
endmodule
`default_nettype wire
