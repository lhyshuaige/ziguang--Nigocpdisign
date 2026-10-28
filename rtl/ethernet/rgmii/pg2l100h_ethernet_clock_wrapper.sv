`timescale 1ns/1ps
`default_nettype none
module pg2l100h_ethernet_clock_wrapper(
    input wire clk_125m_p,clk_125m_n,async_reset,rx_clk,
    output wire tx_clk,sys_clk,locked,tx_reset,sys_reset,rx_reset
);
    wire reference_clk;
    GTP_INBUFDS #(.IOSTANDARD("SSTL15D_I")) u_reference(.I(clk_125m_p),.IB(clk_125m_n),.O(reference_clk));
    pg2l100h_ethernet_pll u_pll(.clkin1(reference_clk),.clkout0(tx_clk),.clkout1(sys_clk),.lock(locked));
    wire reset_request=async_reset || !locked;
    ethernet_reset_sync u_tx_reset(.clk(tx_clk),.async_reset(reset_request),.reset(tx_reset));
    ethernet_reset_sync u_sys_reset(.clk(sys_clk),.async_reset(reset_request),.reset(sys_reset));
    ethernet_reset_sync u_rx_reset(.clk(rx_clk),.async_reset(reset_request),.reset(rx_reset));
endmodule
`default_nettype wire
