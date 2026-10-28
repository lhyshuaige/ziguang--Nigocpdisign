`timescale 1ns/1ps
`default_nettype none
// Same portable counter circuit as the E profile, with F-specific 50 ms settle.
// This wrapper reuses the timer implementation only, not the E PHY register map.
module rtl8211f_reset #(
    parameter integer RESET_CYCLES=1000000,
    parameter integer SETTLE_CYCLES=5000000
)(
    input wire clk,reset,clocks_ready,restart,
    output wire phy_reset_n,management_ready
);
    rtl8211e_reset #(.RESET_CYCLES(RESET_CYCLES),.SETTLE_CYCLES(SETTLE_CYCLES)) u_timer(
        .clk(clk),.reset(reset),.clocks_ready(clocks_ready),.restart(restart),
        .phy_reset_n(phy_reset_n),.management_ready(management_ready));
endmodule
`default_nettype wire
