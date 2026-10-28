`timescale 1ns/1ps
`default_nettype none
module ethernet_soc_subsystem #(parameter integer PHY_RESET_CYCLES=1000000,PHY_SETTLE_CYCLES=5000000)(
 input wire sys_clk,sys_reset,net_clk,clocks_ready,
 input wire rgmii_rxc,rgmii_rx_ctl,input wire [3:0] rgmii_rxd,
 output wire rgmii_txc,rgmii_tx_ctl,output wire [3:0] rgmii_txd,
 output wire phy_rstn,mdc,inout wire mdio,output wire irq,
 input wire [12:0] s_awaddr,
 input wire s_awvalid,
 output wire s_awready,
 input wire [31:0] s_wdata,
 input wire [3:0] s_wstrb,
 input wire s_wvalid,
 output wire s_wready,
 output wire [1:0] s_bresp,
 output wire s_bvalid,
 input wire s_bready,
 input wire [12:0] s_araddr,
 input wire s_arvalid,
 output wire s_arready,
 output wire [31:0] s_rdata,
 output wire [1:0] s_rresp,
 output wire s_rvalid,
 input wire s_rready,
 output wire job_valid,
 output wire job_abort,
 output wire network_ready,
 output wire [31:0] job_base,
 output wire [31:0] job_stride,
 output wire [15:0] job_width,
 output wire [15:0] job_height,
 input wire job_ready,
 input wire job_owner,
 input wire job_done,
 input wire job_error,
 input wire image_start_valid,
 output wire image_start_ready,
 output wire image_done,
 output wire image_error,
 input wire image_abort,
 input wire [31:0] image_tdata,
 input wire [3:0] image_tkeep,
 input wire image_tvalid,
 output wire image_tready,
 input wire image_tlast,
 input wire image_tuser
);
 wire [11:0] net_awaddr;
 wire net_awvalid;
 wire net_awready;
 wire [31:0] net_wdata;
 wire [3:0] net_wstrb;
 wire net_wvalid;
 wire net_wready;
 wire [1:0] net_bresp;
 wire net_bvalid;
 wire net_bready;
 wire [11:0] net_araddr;
 wire net_arvalid;
 wire net_arready;
 wire [31:0] net_rdata;
 wire [1:0] net_rresp;
 wire net_rvalid;
 wire net_rready;
 wire [11:0] job_awaddr;
 wire job_awvalid;
 wire job_awready;
 wire [31:0] job_wdata;
 wire [3:0] job_wstrb;
 wire job_wvalid;
 wire job_wready;
 wire [1:0] job_bresp;
 wire job_bvalid;
 wire job_bready;
 wire [11:0] job_araddr;
 wire job_arvalid;
 wire job_arready;
 wire [31:0] job_rdata;
 wire [1:0] job_rresp;
 wire job_rvalid;
 wire job_rready;
 wire [31:0] job_frame_id,job_frame_bytes,job_timestamp,job_peer_ip,image_packets;
 wire job_rgb565,network_irq,job_irq,rx_valid,rx_last;
 assign irq=network_irq || job_irq;
 ethernet_axil_split u_csr_split(.clk(sys_clk),.reset(sys_reset),
    .s_awaddr(s_awaddr),
    .s_awvalid(s_awvalid),
    .s_awready(s_awready),
    .s_wdata(s_wdata),
    .s_wstrb(s_wstrb),
    .s_wvalid(s_wvalid),
    .s_wready(s_wready),
    .s_bresp(s_bresp),
    .s_bvalid(s_bvalid),
    .s_bready(s_bready),
    .s_araddr(s_araddr),
    .s_arvalid(s_arvalid),
    .s_arready(s_arready),
    .s_rdata(s_rdata),
    .s_rresp(s_rresp),
    .s_rvalid(s_rvalid),
    .s_rready(s_rready),
    .m0_awaddr(net_awaddr),
    .m0_awvalid(net_awvalid),
    .m0_awready(net_awready),
    .m0_wdata(net_wdata),
    .m0_wstrb(net_wstrb),
    .m0_wvalid(net_wvalid),
    .m0_wready(net_wready),
    .m0_bresp(net_bresp),
    .m0_bvalid(net_bvalid),
    .m0_bready(net_bready),
    .m0_araddr(net_araddr),
    .m0_arvalid(net_arvalid),
    .m0_arready(net_arready),
    .m0_rdata(net_rdata),
    .m0_rresp(net_rresp),
    .m0_rvalid(net_rvalid),
    .m0_rready(net_rready),
    .m1_awaddr(job_awaddr),
    .m1_awvalid(job_awvalid),
    .m1_awready(job_awready),
    .m1_wdata(job_wdata),
    .m1_wstrb(job_wstrb),
    .m1_wvalid(job_wvalid),
    .m1_wready(job_wready),
    .m1_bresp(job_bresp),
    .m1_bvalid(job_bvalid),
    .m1_bready(job_bready),
    .m1_araddr(job_araddr),
    .m1_arvalid(job_arvalid),
    .m1_arready(job_arready),
    .m1_rdata(job_rdata),
    .m1_rresp(job_rresp),
    .m1_rvalid(job_rvalid),
    .m1_rready(job_rready));
 ethernet_soc_job_regs u_jobs(.clk(sys_clk),.reset(sys_reset),.network_ready(network_ready),
    .s_awaddr(job_awaddr),
    .s_awvalid(job_awvalid),
    .s_awready(job_awready),
    .s_wdata(job_wdata),
    .s_wstrb(job_wstrb),
    .s_wvalid(job_wvalid),
    .s_wready(job_wready),
    .s_bresp(job_bresp),
    .s_bvalid(job_bvalid),
    .s_bready(job_bready),
    .s_araddr(job_araddr),
    .s_arvalid(job_arvalid),
    .s_arready(job_arready),
    .s_rdata(job_rdata),
    .s_rresp(job_rresp),
    .s_rvalid(job_rvalid),
    .s_rready(job_rready),
 .job_valid(job_valid),.job_ready(job_ready),.job_owner(job_owner),.job_done(job_done),.job_error(job_error),
 .job_abort(job_abort),.irq(job_irq),.job_base(job_base),.job_stride(job_stride),.job_width(job_width),.job_height(job_height),
 .job_rgb565(job_rgb565),.job_frame_id(job_frame_id),.job_frame_bytes(job_frame_bytes),.job_timestamp(job_timestamp),.job_peer_ip(job_peer_ip),
 .image_packets(image_packets),.rx_discard_packet(rx_valid && rx_last));
 ethernet_soc_endpoint #(.PHY_RESET_CYCLES(PHY_RESET_CYCLES),.PHY_SETTLE_CYCLES(PHY_SETTLE_CYCLES)) u_endpoint(
 .sys_clk(sys_clk),.sys_reset(sys_reset),.net_clk(net_clk),.clocks_ready(clocks_ready),
 .rgmii_rxc(rgmii_rxc),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
 .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd),.phy_rstn(phy_rstn),.mdc(mdc),.mdio(mdio),
    .s_axil_awaddr(net_awaddr),
    .s_axil_awvalid(net_awvalid),
    .s_axil_awready(net_awready),
    .s_axil_wdata(net_wdata),
    .s_axil_wstrb(net_wstrb),
    .s_axil_wvalid(net_wvalid),
    .s_axil_wready(net_wready),
    .s_axil_bresp(net_bresp),
    .s_axil_bvalid(net_bvalid),
    .s_axil_bready(net_bready),
    .s_axil_araddr(net_araddr),
    .s_axil_arvalid(net_arvalid),
    .s_axil_arready(net_arready),
    .s_axil_rdata(net_rdata),
    .s_axil_rresp(net_rresp),
    .s_axil_rvalid(net_rvalid),
    .s_axil_rready(net_rready),
 .irq(network_irq),.ready(network_ready),.image_start_valid(image_start_valid),.image_abort(image_abort),.image_start_ready(image_start_ready),
 .image_width(job_width),.image_height(job_height),.image_rgb565(job_rgb565),
 .image_frame_id(job_frame_id),.image_frame_bytes(job_frame_bytes),.image_timestamp(job_timestamp),.image_peer_ip(job_peer_ip),
 .image_tdata(image_tdata),.image_tkeep(image_tkeep),.image_tvalid(image_tvalid),.image_tready(image_tready),.image_tlast(image_tlast),.image_tuser(image_tuser),
 .image_done(image_done),.image_error(image_error),.image_packets(image_packets),
 // Basic INT8 results/control replies use the CPU TX mailbox. The portable
 // endpoint retains its generic result-stream interface for a future producer.
 .result_desc(80'b0),.result_desc_valid(1'b0),.result_desc_ready(),
 .result_tdata(32'b0),.result_tkeep(4'b0),.result_tvalid(1'b0),.result_tready(),.result_tlast(1'b0),.result_tuser(1'b0),
 // UDP image upload needs a separate reassembler; consume complete data
 // packets and count them explicitly instead of stalling the control plane.
 .m_rx_desc(),.m_rx_desc_valid(),.m_rx_desc_ready(1'b1),
 .m_rx_tdata(),.m_rx_tkeep(),.m_rx_tvalid(rx_valid),.m_rx_tready(1'b1),.m_rx_tlast(rx_last),.m_rx_tuser());
endmodule
`default_nettype wire
