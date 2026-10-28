`timescale 1ns/1ps
`default_nettype none
// Logos2 native DDR cells. Production profile uses PHY TX/RX internal delay;
// Data IODELAY compensates the measured FPGA clock insertion; PHY owns the RGMII phase.
// tx_forward_clk equals tx_clk; no additional FPGA clock phase shift.
module pg2l100h_rgmii_io (
    input wire tx_clk,tx_forward_clk,tx_reset,rx_reset,
    input wire [7:0] gmii_txd,input wire gmii_tx_en,gmii_tx_er,
    output wire [7:0] gmii_rxd,output wire gmii_rx_dv,gmii_rx_er,
    output wire rx_clk,input wire rgmii_rxc,rgmii_rx_ctl,input wire [3:0] rgmii_rxd,
    output wire rgmii_txc,rgmii_tx_ctl,output wire [3:0] rgmii_txd
);
    wire [3:0] rx_pad,tx_pad;
    // RX data and control use identical fixed 25-tap delay (Gray code 21).
    wire [3:0] rx_sample;wire rx_ctl_sample;
    wire rx_ctl_pad,rx_ctl_rise,rx_ctl_fall,tx_ctl_pad,tx_clock_pad;
    GTP_CLKBUFR u_rx_clock(.CLKIN(rgmii_rxc),.CLKOUT(rx_clk));
    genvar i;
    generate for(i=0;i<4;i=i+1)begin:g_data
        GTP_ODDR_E1 #(.GRS_EN("FALSE"),.ODDR_MODE("SAME_EDGE"),.RS_TYPE("ASYNC_RESET")) u_tx(
            .Q(tx_pad[i]),.CE(1'b1),.CLK(tx_clk),.D0(gmii_txd[i]),.D1(gmii_txd[i+4]),.RS(tx_reset));
        GTP_OUTBUF #(.IOSTANDARD("LVCMOS33"),.SLEW_RATE("FAST"),.DRIVE_STRENGTH("12")) u_out(.I(tx_pad[i]),.O(rgmii_txd[i]));
        GTP_INBUF #(.IOSTANDARD("LVCMOS33")) u_in(.I(rgmii_rxd[i]),.O(rx_pad[i]));
    GTP_IODELAY_E2 #(.DELAY_STEP_SEL("PARAMETER"),.DELAY_STEP_VALUE(8'd21),.TDELAY_EN("FALSE")) u_rx_data_delay(
        .DI(rx_pad[i]),.DO(rx_sample[i]),.DELAY_SEL(1'b1),.DELAY_STEP(8'd21),.EN_N(1'b0));
        GTP_IDDR_E1 #(.GRS_EN("FALSE"),.IDDR_MODE("SAME_PIPELINED"),.RS_TYPE("ASYNC_RESET")) u_rx(
            .Q0(gmii_rxd[i]),.Q1(gmii_rxd[i+4]),.CE(1'b1),.CLK(rx_clk),.D(rx_sample[i]),.RS(rx_reset));
    end endgenerate
    GTP_ODDR_E1 #(.GRS_EN("FALSE"),.ODDR_MODE("SAME_EDGE"),.RS_TYPE("ASYNC_RESET")) u_tx_ctl(
        .Q(tx_ctl_pad),.CE(1'b1),.CLK(tx_clk),.D0(gmii_tx_en),.D1(gmii_tx_en^gmii_tx_er),.RS(tx_reset));
    GTP_OUTBUF #(.IOSTANDARD("LVCMOS33"),.SLEW_RATE("FAST"),.DRIVE_STRENGTH("12")) u_ctl_out(.I(tx_ctl_pad),.O(rgmii_tx_ctl));
    GTP_ODDR_E1 #(.GRS_EN("FALSE"),.ODDR_MODE("SAME_EDGE"),.RS_TYPE("ASYNC_RESET")) u_clock_forward(
        .Q(tx_clock_pad),.CE(1'b1),.CLK(tx_forward_clk),.D0(1'b1),.D1(1'b0),.RS(tx_reset));
    GTP_OUTBUF #(.IOSTANDARD("LVCMOS33"),.SLEW_RATE("FAST"),.DRIVE_STRENGTH("12")) u_clock_out(.I(tx_clock_pad),.O(rgmii_txc));
    GTP_INBUF #(.IOSTANDARD("LVCMOS33")) u_ctl_in(.I(rgmii_rx_ctl),.O(rx_ctl_pad));
    GTP_IODELAY_E2 #(.DELAY_STEP_SEL("PARAMETER"),.DELAY_STEP_VALUE(8'd21),.TDELAY_EN("FALSE")) u_rx_ctl_delay(
        .DI(rx_ctl_pad),.DO(rx_ctl_sample),.DELAY_SEL(1'b1),.DELAY_STEP(8'd21),.EN_N(1'b0));
    GTP_IDDR_E1 #(.GRS_EN("FALSE"),.IDDR_MODE("SAME_PIPELINED"),.RS_TYPE("ASYNC_RESET")) u_rx_ctl(
        .Q0(rx_ctl_rise),.Q1(rx_ctl_fall),.CE(1'b1),.CLK(rx_clk),.D(rx_ctl_sample),.RS(rx_reset));
    assign gmii_rx_dv=rx_ctl_rise;
    assign gmii_rx_er=rx_ctl_rise^rx_ctl_fall;
endmodule
`default_nettype wire
