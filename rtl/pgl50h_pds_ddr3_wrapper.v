// Thin board/SoC wrapper around the PDS-generated Logos HMIC instance.
//
// Generate the instance with name `pgl50h_hmic_ddr3` and the parameters
// MEM_ROW_WIDTH=15, MEM_COLUMN_WIDTH=10, MEM_BANK_WIDTH=3,
// MEM_DQ_WIDTH=32, MEM_DM_WIDTH=4, MEM_DQS_WIDTH=4, REGION_NUM=3.
// The generated Verilog and its controller/PHY filelists are kept under
// project/NAX/ip/ddr3 and added to the PDS project only for the real-board
// build (`PGL50H_USE_PDS_DDR3`).

module pgl50h_pds_ddr3_wrapper #(
  parameter integer HMIC_ADDR_WIDTH = 28,
  parameter integer HMIC_DATA_WIDTH = 256
) (
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

  wire [14:0] mem_a;
  wire  [2:0] mem_ba;
  wire        mem_rst_n;
  wire        mem_ck;
  wire        mem_ck_n;
  wire        mem_cke;
  wire        mem_cs_n;
  wire        mem_ras_n;
  wire        mem_cas_n;
  wire        mem_we_n;
  wire        mem_odt;
  wire  [3:0] mem_dm;

  wire        apb_ready;
  wire [15:0] apb_rdata;
  wire        apb_int;
  wire [135:0] debug_data;
  wire  [51:0] debug_slice_state;
  wire  [23:0] debug_calib_ctrl;
  wire   [7:0] ck_dly_set_bin;
  wire   [3:0] wl_step_ov_warning;
  wire   [7:0] dll_step;
  wire         dll_lock;
  wire   [7:0] init_read_clk_ctrl;
  wire  [15:0] init_slip_step;
  wire   [3:0] update_com_val_err_flag;

  // The generated module name is set by the PDS IP Compiler instance name.
  // Keep this wrapper out of default simulation so Verilator does not need
  // vendor PHY primitives.
  pgl50h_hmic_ddr3 #(
    .DFI_CLK_PERIOD(10000),
    .MEM_ROW_WIDTH(15),
    .MEM_COLUMN_WIDTH(10),
    .MEM_BANK_WIDTH(3),
    .MEM_DQ_WIDTH(32),
    .MEM_DM_WIDTH(4),
    .MEM_DQS_WIDTH(4),
    .REGION_NUM(3),
    .CTRL_ADDR_WIDTH(28)
  ) u_hmic (
    .ref_clk(ref_clk),
    .resetn(reset_n),
    .ddr_init_done(init_done),
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
    .apb_clk(ddrphy_clkin),
    .apb_rst_n(reset_n),
    .apb_sel(1'b0),
    .apb_enable(1'b0),
    .apb_addr(8'h00),
    .apb_write(1'b0),
    .apb_ready(apb_ready),
    .apb_wdata(16'h0000),
    .apb_rdata(apb_rdata),
    .apb_int(apb_int),
    .debug_data(debug_data),
    .debug_slice_state(debug_slice_state),
    .debug_calib_ctrl(debug_calib_ctrl),
    .ck_dly_set_bin(ck_dly_set_bin),
    .ck_dly_en(1'b0),
    .init_ck_dly_step(8'h00),
    .wl_step_ov_warning(wl_step_ov_warning),
    .dll_step(dll_step),
    .dll_lock(dll_lock),
    .init_read_clk_ctrl(init_read_clk_ctrl),
    .init_slip_step(init_slip_step),
    .force_read_clk_ctrl(1'b0),
    .ddrphy_gate_update_en(1'b0),
    .update_com_val_err_flag(update_com_val_err_flag),
    .rd_fake_stop(1'b0),
    .mem_rst_n(mem_rst_n),
    .mem_ck(mem_ck),
    .mem_ck_n(mem_ck_n),
    .mem_cke(mem_cke),
    .mem_cs_n(mem_cs_n),
    .mem_ras_n(mem_ras_n),
    .mem_cas_n(mem_cas_n),
    .mem_we_n(mem_we_n),
    .mem_odt(mem_odt),
    .mem_a(mem_a),
    .mem_ba(mem_ba),
    .mem_dqs(ddr3_dqs_p),
    .mem_dqs_n(ddr3_dqs_n),
    .mem_dq(ddr3_dq),
    .mem_dm(mem_dm)
  );

  assign ddr3_addr    = {1'b0, mem_a};
  assign ddr3_ba      = mem_ba;
  assign ddr3_ras_n   = mem_ras_n;
  assign ddr3_cas_n   = mem_cas_n;
  assign ddr3_we_n    = mem_we_n;
  assign ddr3_reset_n = mem_rst_n;
  assign ddr3_ck_p    = mem_ck;
  assign ddr3_ck_n    = mem_ck_n;
  assign ddr3_cke     = mem_cke;
  assign ddr3_cs_n    = mem_cs_n;
  assign ddr3_odt     = mem_odt;
  assign ddr3_dm      = mem_dm;
endmodule
