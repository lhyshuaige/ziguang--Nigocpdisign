// PGL50H Bank3 x32 DDR3 boundary.
//
// In a default RTL build this is a safe board-pin stub plus an inactive HMIC
// user port. Defining PGL50H_USE_PDS_DDR3 selects the generated
// pgl50h_pds_ddr3_wrapper, which contains the PDS Logos HMIC controller.

module pgl50h_ddr3_boundary #(
  parameter integer HMIC_ADDR_WIDTH = 28,
  parameter integer HMIC_DATA_WIDTH = 256
) (
  input  wire        clk_sys,
  input  wire        reset,
  input  wire        ref_clk,
  input  wire        reset_n,
  output wire        init_done,
  output wire        ddrphy_clkin,
  output wire        pll_lock,

  input  wire [HMIC_ADDR_WIDTH-1:0]   axi_awaddr,
  input  wire                         axi_awuser_ap,
  input  wire [3:0]                   axi_awuser_id,
  input  wire [3:0]                   axi_awlen,
  output wire                         axi_awready,
  input  wire                         axi_awvalid,
  input  wire [HMIC_DATA_WIDTH-1:0]   axi_wdata,
  input  wire [HMIC_DATA_WIDTH/8-1:0] axi_wstrb,
  output wire                         axi_wready,
  output wire [3:0]                   axi_wusero_id,
  output wire                         axi_wusero_last,
  input  wire [HMIC_ADDR_WIDTH-1:0]   axi_araddr,
  input  wire                         axi_aruser_ap,
  input  wire [3:0]                   axi_aruser_id,
  input  wire [3:0]                   axi_arlen,
  output wire                         axi_arready,
  input  wire                         axi_arvalid,
  output wire [HMIC_DATA_WIDTH-1:0]   axi_rdata,
  output wire [3:0]                   axi_rid,
  output wire                         axi_rlast,
  output wire                         axi_rvalid,

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
  inout  wire  [3:0] ddr3_dqs_n
);

`ifdef PGL50H_USE_PDS_DDR3
  pgl50h_pds_ddr3_wrapper #(
    .HMIC_ADDR_WIDTH(HMIC_ADDR_WIDTH),
    .HMIC_DATA_WIDTH(HMIC_DATA_WIDTH)
  ) u_pds_ddr3 (
    .ref_clk(ref_clk),
    .reset_n(reset_n),
    .init_done(init_done),
    .ddrphy_clkin(ddrphy_clkin),
    .pll_lock(pll_lock),
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
`elsif PGL50H_PDS_DDR3
  pgl50h_pds_ddr3_wrapper #(
    .HMIC_ADDR_WIDTH(HMIC_ADDR_WIDTH),
    .HMIC_DATA_WIDTH(HMIC_DATA_WIDTH)
  ) u_pds_ddr3 (
    .ref_clk(ref_clk),
    .reset_n(reset_n),
    .init_done(init_done),
    .ddrphy_clkin(ddrphy_clkin),
    .pll_lock(pll_lock),
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
`else
  assign init_done       = 1'b1;
  assign ddrphy_clkin    = clk_sys;
  assign pll_lock        = 1'b1;
  assign axi_awready     = 1'b0;
  assign axi_wready      = 1'b0;
  assign axi_wusero_id   = 4'h0;
  assign axi_wusero_last = 1'b0;
  assign axi_arready     = 1'b0;
  assign axi_rdata       = {HMIC_DATA_WIDTH{1'b0}};
  assign axi_rid         = 4'h0;
  assign axi_rlast       = 1'b0;
  assign axi_rvalid      = 1'b0;

  assign ddr3_addr       = 16'h0000;
  assign ddr3_ba         = 3'h0;
  assign ddr3_ras_n      = 1'b1;
  assign ddr3_cas_n      = 1'b1;
  assign ddr3_we_n       = 1'b1;
  assign ddr3_reset_n    = 1'b0;
  assign ddr3_ck_p       = 1'b0;
  assign ddr3_ck_n       = 1'b0;
  assign ddr3_cke        = 1'b0;
  assign ddr3_cs_n       = 1'b1;
  assign ddr3_odt        = 1'b0;
  assign ddr3_dm         = 4'hf;
  assign ddr3_dq         = {32{1'bz}};
  assign ddr3_dqs_p      = {4{1'bz}};
  assign ddr3_dqs_n      = {4{1'bz}};
`endif

  wire unused_boundary = reset ^ reset_n ^ ref_clk ^ axi_awaddr[0]
                       ^ axi_awuser_ap ^ axi_awuser_id[0] ^ axi_awlen[0]
                       ^ axi_awvalid ^ axi_wdata[0] ^ axi_wstrb[0]
                       ^ axi_araddr[0] ^ axi_aruser_ap ^ axi_aruser_id[0]
                       ^ axi_arlen[0] ^ axi_arvalid;

endmodule
