// MES2L676-100HP baseline: real DDR, CPU, Fabric, DMA, Vision and INT8 AI.
// Ethernet modular integration; external Camera pins and HDMI remain outside this candidate.
module pg2l100h_soc_top (
  input wire clk_125m_p, input wire clk_125m_n,
  input wire reset_n, input wire key_n, output wire [7:0] led,
  input wire rgmii_rxc,rgmii_rx_ctl,input wire [3:0] rgmii_rxd,
  output wire rgmii_txc,rgmii_tx_ctl,output wire [3:0] rgmii_txd,
  output wire phy_rstn,mdc,inout wire mdio,
  output wire [14:0] ddr3_addr, output wire [2:0] ddr3_ba,
  output wire ddr3_ras_n, ddr3_cas_n, ddr3_we_n, ddr3_reset_n,
  output wire ddr3_ck_p, ddr3_ck_n, ddr3_cke, ddr3_cs_n, ddr3_odt,
  output wire [3:0] ddr3_dm, inout wire [31:0] ddr3_dq,
  inout wire [3:0] ddr3_dqs_p, ddr3_dqs_n
);
  localparam HMIC_ADDR_WIDTH=28;
  localparam HMIC_DATA_WIDTH=256;
  wire [12:0] eth_axil_awaddr;
  wire eth_axil_awvalid;
  wire eth_axil_awready;
  wire [31:0] eth_axil_wdata;
  wire [3:0] eth_axil_wstrb;
  wire eth_axil_wvalid;
  wire eth_axil_wready;
  wire [1:0] eth_axil_bresp;
  wire eth_axil_bvalid;
  wire eth_axil_bready;
  wire [12:0] eth_axil_araddr;
  wire eth_axil_arvalid;
  wire eth_axil_arready;
  wire [31:0] eth_axil_rdata;
  wire [1:0] eth_axil_rresp;
  wire eth_axil_rvalid;
  wire eth_axil_rready;
  wire eth_job_valid;
  wire eth_job_abort;
  wire eth_network_ready;
  wire [31:0] eth_job_base;
  wire [31:0] eth_job_stride;
  wire [15:0] eth_job_width;
  wire [15:0] eth_job_height;
  wire eth_job_ready;
  wire eth_job_owner;
  wire eth_job_done;
  wire eth_job_error;
  wire eth_image_start_valid;
  wire eth_image_start_ready;
  wire eth_image_done;
  wire eth_image_error;
  wire eth_image_abort;
  wire [31:0] eth_image_tdata;
  wire [3:0] eth_image_tkeep;
  wire eth_image_tvalid;
  wire eth_image_tready;
  wire eth_image_tlast;
  wire eth_image_tuser;
  wire eth_irq;
  wire ref125, clk_sys, reserved_net125, pll_locked;
  wire ddrphy_clkin, ddr_init_done, ddr_pll_lock, soc_reset;
  wire timer_irq; wire [63:0] mtime;
  wire ai_start; wire [31:0] ai_control,ai_src_addr,ai_dst_addr,ai_length;
  wire [7:0] keys;
  (* ASYNC_REG = "TRUE" *) reg [1:0] key_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] ready_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] reset_release;
  wire async_not_ready = !reset_n || !pll_locked || !ddr_pll_lock || !ddr_init_done;
  GTP_INBUFDS #(.IOSTANDARD("SSTL15D_I")) u_reference (.I(clk_125m_p), .IB(clk_125m_n), .O(ref125));
  // The same reference and PLL can be shared with Ethernet in the next phase.
  pg2l100h_ethernet_pll u_system_pll (.clkin1(ref125), .clkout0(reserved_net125),
    .clkout1(clk_sys), .lock(pll_locked));
  // HMIC reset is independent of CPU reset: calibration must run before CPU release.
  always @(posedge clk_sys or posedge async_not_ready)
    if (async_not_ready) reset_release <= 2'b11;
    else reset_release <= {reset_release[0],1'b0};
  assign soc_reset=reset_release[1];
  always @(posedge clk_sys or negedge reset_n)
    if (!reset_n) begin key_sync<=2'b11; ready_sync<=2'b00; end
    else begin key_sync<={key_sync[0],key_n}; ready_sync<={ready_sync[0],ddr_init_done}; end
  assign keys={7'b0,~key_sync[1]};
  wire [HMIC_ADDR_WIDTH-1:0]   axi_awaddr;
  wire                         axi_awuser_ap;
  wire [3:0]                   axi_awuser_id;
  wire [3:0]                   axi_awlen;
  wire                         axi_awready;
  wire                         axi_awvalid;
  wire [HMIC_DATA_WIDTH-1:0]   axi_wdata;
  wire [HMIC_DATA_WIDTH/8-1:0] axi_wstrb;
  wire                         axi_wready;
  wire [3:0]                   axi_wusero_id;
  wire                         axi_wusero_last;
  wire [HMIC_ADDR_WIDTH-1:0]   axi_araddr;
  wire                         axi_aruser_ap;
  wire [3:0]                   axi_aruser_id;
  wire [3:0]                   axi_arlen;
  wire                         axi_arready;
  wire                         axi_arvalid;
  wire [HMIC_DATA_WIDTH-1:0]   axi_rdata;
  wire [3:0]                   axi_rid;
  wire                         axi_rlast;
  wire                         axi_rvalid;

  pg2l100h_ddr3_wrapper u_ddr3 (
        .ref_clk(ref125),
    .reset_n(reset_n),
    .init_done(ddr_init_done),
    .ddrphy_clkin(ddrphy_clkin),
    .pll_lock(ddr_pll_lock),
    .axi_awaddr(axi_awaddr),
    .axi_awuser_ap(axi_awuser_ap),
    .axi_awuser_id(axi_awuser_id),
    .axi_awlen(axi_awlen),
    .axi_awready(axi_awready),
    .axi_awvalid(axi_awvalid),
    .axi_wdata(axi_wdata),
    .axi_wstrb(axi_wstrb),
    .axi_wready(axi_wready),
    .axi_wusero_id(axi_wusero_id),
    .axi_wusero_last(axi_wusero_last),
    .axi_araddr(axi_araddr),
    .axi_aruser_ap(axi_aruser_ap),
    .axi_aruser_id(axi_aruser_id),
    .axi_arlen(axi_arlen),
    .axi_arready(axi_arready),
    .axi_arvalid(axi_arvalid),
    .axi_rdata(axi_rdata),
    .axi_rid(axi_rid),
    .axi_rlast(axi_rlast),
    .axi_rvalid(axi_rvalid),
    .ddr3_addr(ddr3_addr),
    .ddr3_ba(ddr3_ba),
    .ddr3_ras_n(ddr3_ras_n),
    .ddr3_cas_n(ddr3_cas_n),
    .ddr3_we_n(ddr3_we_n),
    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_ck_p(ddr3_ck_p),
    .ddr3_ck_n(ddr3_ck_n),
    .ddr3_cke(ddr3_cke),
    .ddr3_cs_n(ddr3_cs_n),
    .ddr3_odt(ddr3_odt),
    .ddr3_dm(ddr3_dm),
    .ddr3_dq(ddr3_dq),
    .ddr3_dqs_p(ddr3_dqs_p),
    .ddr3_dqs_n(ddr3_dqs_n)
  );

  pg2l100h_soc_core #(
    .USE_BOOT_ROM(1),
    .BOOT_ROM_FILE("firmware/build/boot64.hex"),
    .USE_DDR_AXI(1),
    .USE_AXI_FABRIC(1),
    .HMIC_ADDR_WIDTH(HMIC_ADDR_WIDTH),
    .HMIC_DATA_WIDTH(HMIC_DATA_WIDTH)
  ) u_soc_core (
    .clk(clk_sys),
    .reset(soc_reset),
    .ddr_init_done(ready_sync[1]),
    .ddr_clk(ddrphy_clkin),
    .keys(keys),
    .leds(led),
    .timer_irq(timer_irq),
    .mtime(mtime),
    .software_irq(1'b0),
    .external_irq(eth_irq),
    .ai_start(ai_start),
    .ai_control(ai_control),
    .ai_src_addr(ai_src_addr),
    .ai_dst_addr(ai_dst_addr),
    .ai_length(ai_length),
    .axi_awaddr(axi_awaddr),
    .axi_awuser_ap(axi_awuser_ap),
    .axi_awuser_id(axi_awuser_id),
    .axi_awlen(axi_awlen),
    .axi_awready(axi_awready),
    .axi_awvalid(axi_awvalid),
    .axi_wdata(axi_wdata),
    .axi_wstrb(axi_wstrb),
    .axi_wready(axi_wready),
    .axi_wusero_id(axi_wusero_id),
    .axi_wusero_last(axi_wusero_last),
    .axi_araddr(axi_araddr),
    .axi_aruser_ap(axi_aruser_ap),
    .axi_aruser_id(axi_aruser_id),
    .axi_arlen(axi_arlen),
    .axi_arready(axi_arready),
    .axi_arvalid(axi_arvalid),
    .axi_rdata(axi_rdata),
    .axi_rid(axi_rid),
    .axi_rlast(axi_rlast),
    .axi_rvalid(axi_rvalid),
    .cam_pclk(1'b0),
    .cam_vsync(1'b0),
    .cam_href(1'b0),
    .cam_data(8'h00),
    .eth_axil_awaddr(eth_axil_awaddr),
    .eth_axil_awvalid(eth_axil_awvalid),
    .eth_axil_awready(eth_axil_awready),
    .eth_axil_wdata(eth_axil_wdata),
    .eth_axil_wstrb(eth_axil_wstrb),
    .eth_axil_wvalid(eth_axil_wvalid),
    .eth_axil_wready(eth_axil_wready),
    .eth_axil_bresp(eth_axil_bresp),
    .eth_axil_bvalid(eth_axil_bvalid),
    .eth_axil_bready(eth_axil_bready),
    .eth_axil_araddr(eth_axil_araddr),
    .eth_axil_arvalid(eth_axil_arvalid),
    .eth_axil_arready(eth_axil_arready),
    .eth_axil_rdata(eth_axil_rdata),
    .eth_axil_rresp(eth_axil_rresp),
    .eth_axil_rvalid(eth_axil_rvalid),
    .eth_axil_rready(eth_axil_rready),
    .eth_job_valid(eth_job_valid),
    .eth_job_abort(eth_job_abort),
    .eth_network_ready(eth_network_ready),
    .eth_job_base(eth_job_base),
    .eth_job_stride(eth_job_stride),
    .eth_job_width(eth_job_width),
    .eth_job_height(eth_job_height),
    .eth_job_ready(eth_job_ready),
    .eth_job_owner(eth_job_owner),
    .eth_job_done(eth_job_done),
    .eth_job_error(eth_job_error),
    .eth_image_start_valid(eth_image_start_valid),
    .eth_image_start_ready(eth_image_start_ready),
    .eth_image_done(eth_image_done),
    .eth_image_error(eth_image_error),
    .eth_image_abort(eth_image_abort),
    .eth_image_tdata(eth_image_tdata),
    .eth_image_tkeep(eth_image_tkeep),
    .eth_image_tvalid(eth_image_tvalid),
    .eth_image_tready(eth_image_tready),
    .eth_image_tlast(eth_image_tlast),
    .eth_image_tuser(eth_image_tuser)
  );

  ethernet_soc_subsystem u_ethernet(
    .sys_clk(clk_sys),.sys_reset(soc_reset),.net_clk(reserved_net125),.clocks_ready(pll_locked),
    .rgmii_rxc(rgmii_rxc),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
    .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd),
    .phy_rstn(phy_rstn),.mdc(mdc),.mdio(mdio),.irq(eth_irq),
    .s_awaddr(eth_axil_awaddr),
    .s_awvalid(eth_axil_awvalid),
    .s_awready(eth_axil_awready),
    .s_wdata(eth_axil_wdata),
    .s_wstrb(eth_axil_wstrb),
    .s_wvalid(eth_axil_wvalid),
    .s_wready(eth_axil_wready),
    .s_bresp(eth_axil_bresp),
    .s_bvalid(eth_axil_bvalid),
    .s_bready(eth_axil_bready),
    .s_araddr(eth_axil_araddr),
    .s_arvalid(eth_axil_arvalid),
    .s_arready(eth_axil_arready),
    .s_rdata(eth_axil_rdata),
    .s_rresp(eth_axil_rresp),
    .s_rvalid(eth_axil_rvalid),
    .s_rready(eth_axil_rready),
    .job_valid(eth_job_valid),
    .job_abort(eth_job_abort),
    .network_ready(eth_network_ready),
    .job_base(eth_job_base),
    .job_stride(eth_job_stride),
    .job_width(eth_job_width),
    .job_height(eth_job_height),
    .job_ready(eth_job_ready),
    .job_owner(eth_job_owner),
    .job_done(eth_job_done),
    .job_error(eth_job_error),
    .image_start_valid(eth_image_start_valid),
    .image_start_ready(eth_image_start_ready),
    .image_done(eth_image_done),
    .image_error(eth_image_error),
    .image_abort(eth_image_abort),
    .image_tdata(eth_image_tdata),
    .image_tkeep(eth_image_tkeep),
    .image_tvalid(eth_image_tvalid),
    .image_tready(eth_image_tready),
    .image_tlast(eth_image_tlast),
    .image_tuser(eth_image_tuser));

endmodule
