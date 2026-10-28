`timescale 1ns/1ps
`default_nettype none
module ethernet_reset_sync (
    input wire clk,
    input wire async_reset,
    output wire reset
);
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg [3:0] pipe;
    always @(posedge clk or posedge async_reset) begin
        if (async_reset) pipe <= 4'b1111;
        else pipe <= {pipe[2:0],1'b0};
    end
    assign reset=pipe[3];
endmodule
`default_nettype wire
