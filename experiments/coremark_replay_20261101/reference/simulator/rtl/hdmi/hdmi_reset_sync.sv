`timescale 1ns/1ps
module hdmi_reset_sync (input wire clk, reset_request, output wire reset);
  (* ASYNC_REG="TRUE" *) reg [1:0] release_q;
  always @(posedge clk or posedge reset_request) begin
    if (reset_request) release_q <= 0;
    else release_q <= {release_q[0],1'b1};
  end
  assign reset = !release_q[1];
endmodule
