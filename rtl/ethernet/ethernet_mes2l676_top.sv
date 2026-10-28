`timescale 1ns/1ps
`default_nettype none
// Board-specific shell; AXI-Lite/stream ports attach to existing SoC externally.
module ethernet_mes2l676_top #(
 parameter integer PHY_RESET_CYCLES=1000000,PHY_SETTLE_CYCLES=5000000
)(
 input wire clk_125m_p,clk_125m_n,async_reset,
 input wire rgmii_rxc,rgmii_rx_ctl,input wire [3:0] rgmii_rxd,
 output wire rgmii_txc,rgmii_tx_ctl,output wire [3:0] rgmii_txd,
 output wire phy_rstn,mdc,inout wire mdio,
 output wire sys_clk,sys_reset,pll_locked,
 input wire [11:0] s_axil_awaddr,input wire s_axil_awvalid,output wire s_axil_awready,
 input wire [31:0] s_axil_wdata,input wire [3:0] s_axil_wstrb,input wire s_axil_wvalid,output wire s_axil_wready,
 output wire [1:0] s_axil_bresp,output wire s_axil_bvalid,input wire s_axil_bready,
 input wire [11:0] s_axil_araddr,input wire s_axil_arvalid,output wire s_axil_arready,
 output wire [31:0] s_axil_rdata,output wire [1:0] s_axil_rresp,output wire s_axil_rvalid,input wire s_axil_rready,
 output wire irq,ready,
 input wire [79:0] s_tx_desc,input wire s_tx_desc_valid,output wire s_tx_desc_ready,
 input wire [31:0] s_tx_tdata,input wire [3:0] s_tx_tkeep,input wire s_tx_tvalid,output wire s_tx_tready,input wire s_tx_tlast,s_tx_tuser,
 output wire [79:0] m_rx_desc,output wire m_rx_desc_valid,input wire m_rx_desc_ready,
 output wire [31:0] m_rx_tdata,output wire [3:0] m_rx_tkeep,output wire m_rx_tvalid,input wire m_rx_tready,output wire m_rx_tlast,m_rx_tuser
);
 wire net_clk,net_reset,rx_clk,rx_reset;
 wire [7:0] gmii_txd,gmii_rxd;wire gmii_tx_en,gmii_tx_er,gmii_rx_dv,gmii_rx_er;
 pg2l100h_ethernet_clock_wrapper u_clock(.clk_125m_p(clk_125m_p),.clk_125m_n(clk_125m_n),.async_reset(async_reset),.rx_clk(rx_clk),
  .tx_clk(net_clk),.sys_clk(sys_clk),.locked(pll_locked),.tx_reset(net_reset),.sys_reset(sys_reset),.rx_reset(rx_reset));
 pg2l100h_rgmii_io u_io(.tx_clk(net_clk),.tx_forward_clk(net_clk),.tx_reset(net_reset),.rx_reset(rx_reset),
  .gmii_txd(gmii_txd),.gmii_tx_en(gmii_tx_en),.gmii_tx_er(gmii_tx_er),.gmii_rxd(gmii_rxd),.gmii_rx_dv(gmii_rx_dv),.gmii_rx_er(gmii_rx_er),.rx_clk(rx_clk),
  .rgmii_rxc(rgmii_rxc),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),.rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
 wire management_ready;
 rtl8211f_reset #(.RESET_CYCLES(PHY_RESET_CYCLES),.SETTLE_CYCLES(PHY_SETTLE_CYCLES)) u_phy_reset(
  .clk(sys_clk),.reset(sys_reset),.clocks_ready(pll_locked),.restart(1'b0),.phy_reset_n(phy_rstn),.management_ready(management_ready));
 wire cmd_valid,cmd_ready,cmd_read,rsp_valid,rsp_ready;wire [4:0] cmd_phy,cmd_reg,phy_addr;
 wire [15:0] cmd_data,rsp_data,phy_status,bmsr;wire [1:0] rsp_error,last_error,speed;
 wire [31:0] phy_id,error_count,scan_rounds;wire phy_found,link_up,full_duplex,autoneg_complete,phy_ready;
 wire [31:0] phy_info={phy_status,5'd0,last_error,phy_found,phy_addr,speed,phy_ready};
 rtl8211f_probe u_probe(.clk(sys_clk),.reset(sys_reset),.management_ready(management_ready),
  .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_read(cmd_read),.cmd_phy_addr(cmd_phy),.cmd_reg_addr(cmd_reg),.cmd_wdata(cmd_data),
  .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_rdata(rsp_data),.rsp_error(rsp_error),
  .phy_found(phy_found),.phy_addr(phy_addr),.phy_id(phy_id),.phy_status(phy_status),.bmsr(bmsr),.link_up(link_up),.full_duplex(full_duplex),.autoneg_complete(autoneg_complete),
  .gigabit_ready(phy_ready),.speed(speed),.last_error(last_error),.error_count(error_count),.scan_rounds(scan_rounds));
 wire mdio_i,mdio_o,mdio_t;
 ethernet_mdio u_mdio(.clk_mgmt(sys_clk),.reset(sys_reset),.management_ready(management_ready),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_read(cmd_read),
  .cmd_phy_addr(cmd_phy),.cmd_reg_addr(cmd_reg),.cmd_wdata(cmd_data),.rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_rdata(rsp_data),.rsp_error(rsp_error),
  .mdc(mdc),.mdio_i(mdio_i),.mdio_o(mdio_o),.mdio_t(mdio_t));
 // Open-drain: only drive zero; pull-up is on the board. Never drive logical one.
 assign mdio=mdio_t || mdio_o?1'bz:1'b0;assign mdio_i=mdio;
 ethernet_top u_core(
.sys_clk(sys_clk),
.sys_reset(sys_reset),
.net_clk(net_clk),
.net_reset(net_reset),
.rx_clk(rx_clk),
.rx_reset(rx_reset),
.phy_ready(phy_ready),
.phy_info(phy_info),
.phy_id(phy_id),
.gmii_rxd(gmii_rxd),
.gmii_rx_dv(gmii_rx_dv),
.gmii_rx_er(gmii_rx_er),
.gmii_txd(gmii_txd),
.gmii_tx_en(gmii_tx_en),
.gmii_tx_er(gmii_tx_er),
.s_axil_awaddr(s_axil_awaddr),
.s_axil_awvalid(s_axil_awvalid),
.s_axil_awready(s_axil_awready),
.s_axil_wdata(s_axil_wdata),
.s_axil_wstrb(s_axil_wstrb),
.s_axil_wvalid(s_axil_wvalid),
.s_axil_wready(s_axil_wready),
.s_axil_bresp(s_axil_bresp),
.s_axil_bvalid(s_axil_bvalid),
.s_axil_bready(s_axil_bready),
.s_axil_araddr(s_axil_araddr),
.s_axil_arvalid(s_axil_arvalid),
.s_axil_arready(s_axil_arready),
.s_axil_rdata(s_axil_rdata),
.s_axil_rresp(s_axil_rresp),
.s_axil_rvalid(s_axil_rvalid),
.s_axil_rready(s_axil_rready),
.irq(irq),
.ready(ready),
.s_tx_desc(s_tx_desc),
.s_tx_desc_valid(s_tx_desc_valid),
.s_tx_desc_ready(s_tx_desc_ready),
.s_tx_tdata(s_tx_tdata),
.s_tx_tkeep(s_tx_tkeep),
.s_tx_tvalid(s_tx_tvalid),
.s_tx_tready(s_tx_tready),
.s_tx_tlast(s_tx_tlast),
.s_tx_tuser(s_tx_tuser),
.m_rx_desc(m_rx_desc),
.m_rx_desc_valid(m_rx_desc_valid),
.m_rx_desc_ready(m_rx_desc_ready),
.m_rx_tdata(m_rx_tdata),
.m_rx_tkeep(m_rx_tkeep),
.m_rx_tvalid(m_rx_tvalid),
.m_rx_tready(m_rx_tready),
.m_rx_tlast(m_rx_tlast),
.m_rx_tuser(m_rx_tuser));
endmodule
`default_nettype wire
