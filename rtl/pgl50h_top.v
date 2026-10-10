// PGL50H board-level top.  Pin numbers are intentionally kept in the PDS
// constraint project; this module only exposes the board signals and maps the
// active-low user keys to active-high SoC key status.

module pgl50h_top #(
  parameter integer USE_DDR_AXI = 0,
  // The board top uses the completed AXI skeleton by default.  Pass 0 only
  // for the legacy/native bring-up path or an older regression that needs it.
  parameter integer USE_AXI_FABRIC = 1,
  parameter integer HMIC_ADDR_WIDTH = 28,
  parameter integer HMIC_DATA_WIDTH = 256
) (
  input  wire        clk_50m,
  input  wire        reset_n,
  input  wire  [7:0] key_n,
  output wire  [7:0] led,

  output wire [15:0] ddr3_addr,
  output wire  [2:0] ddr3_ba,
  output wire        ddr3_ras_n,
  output wire        ddr3_cas_n,
  output wire        ddr3_we_n,
  output wire        ddr3_reset_n,
  output wire        ddr3_ck_p,
  output wire        ddr3_ck_n,
  output wire        ddr3_cke,
  output wire        ddr3_cs_n,
  output wire        ddr3_odt,
  output wire  [3:0] ddr3_dm,
  inout  wire [31:0] ddr3_dq,
  inout  wire  [3:0] ddr3_dqs_p,
  inout  wire  [3:0] ddr3_dqs_n,

  output wire        qspi_cs_n,
  output wire        qspi_sck,
  inout  wire  [3:0] qspi_dq,
  inout  wire [33:0] ext_io
);

  wire       clk_sys;
  wire       pll_locked;
  wire       ddr_init_done;
  wire       ddrphy_clkin;
  wire       ddr_pll_lock;
  wire       soc_reset;
  wire       soc_reset_n;
  wire [7:0] keys;
  wire       timer_irq;
  wire [63:0] mtime;
  wire        ai_start;
  wire [31:0] ai_control;
  wire [31:0] ai_src_addr;
  wire [31:0] ai_dst_addr;
  wire [31:0] ai_length;

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

// The PDS HMIC project includes this file through pgl50h_top_pds.v, which
// defines PGL50H_PDS_DDR3 before textual inclusion.  Keeping both spellings
// lets the same RTL remain usable from the GUI project and from standalone
// simulation/lint flows.
`ifdef PGL50H_USE_PDS_DDR3
  localparam integer SOC_USE_DDR_AXI = 1;
`elsif PGL50H_PDS_DDR3
  localparam integer SOC_USE_DDR_AXI = 1;
`else
  localparam integer SOC_USE_DDR_AXI = USE_DDR_AXI;
`endif

`ifdef PGL50H_USE_AXI_FABRIC
  localparam integer SOC_USE_AXI_FABRIC = 1;
`else
  localparam integer SOC_USE_AXI_FABRIC = USE_AXI_FABRIC;
`endif

  assign keys = ~key_n;

  pgl50h_ddr3_boundary u_ddr3 (
    .clk_sys(clk_sys),
    .reset(soc_reset),
    .ref_clk(clk_50m),
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

  pgl50h_clock_reset u_clock_reset (
    .clk_50m(clk_50m),
    .reset_ext_n(reset_n),
    .ddr_init_done(ddr_init_done),
    .clk_sys_ext(ddrphy_clkin),
    .ext_pll_locked(ddr_pll_lock),
    // CPU/AXI/AI/DMA always use the dedicated 100 MHz PLL clock.  The HMIC
    // user port remains in its own ddrphy_clkin domain and is crossed in the
    // SoC core by pgl50h_axi_hmic_cdc.
    .use_external_clk(1'b0),
    .clk_sys(clk_sys),
    .pll_locked(pll_locked),
    .soc_reset(soc_reset),
    .soc_reset_n(soc_reset_n)
  );

  pgl50h_soc_core #(
    .USE_DDR_AXI(SOC_USE_DDR_AXI),
    .USE_AXI_FABRIC(SOC_USE_AXI_FABRIC),
    .HMIC_ADDR_WIDTH(HMIC_ADDR_WIDTH),
    .HMIC_DATA_WIDTH(HMIC_DATA_WIDTH)
  ) u_soc_core (
    .clk(clk_sys),
    .reset(soc_reset),
    .ddr_init_done(ddr_init_done),
    .ddr_clk(ddrphy_clkin),
    .keys(keys),
    .leds(led),
    .timer_irq(timer_irq),
    .mtime(mtime),
    .software_irq(1'b0),
    .external_irq(1'b0),
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
    .axi_rvalid(axi_rvalid)
  );

  // QSPI and the 40-pin header are reserved for the next integration step.
  assign qspi_cs_n = 1'b1;
  assign qspi_sck  = 1'b0;
  assign qspi_dq   = {4{1'bz}};
  assign ext_io    = {34{1'bz}};

endmodule
