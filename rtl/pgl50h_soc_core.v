// CPU-centric SoC layer.
//
// USE_AXI_FABRIC=0 keeps the proven legacy native bridge/fallback paths.
// USE_AXI_FABRIC=1 enables the complete contest skeleton: CPU I/D adapters,
// four-master AXI fabric, AXI4-to-HMIC boundary, CSR fabric, INT8 engine,
// camera/DMA master, and sticky interrupt aggregation.
module pgl50h_soc_core #(
  parameter integer USE_DDR_AXI    = 0,
  parameter integer USE_AXI_FABRIC = 0,
  parameter integer HMIC_ADDR_WIDTH = 28,
  parameter integer HMIC_DATA_WIDTH = 256
) (
  input  wire        clk,
  input  wire        reset,
  input  wire        ddr_init_done,
  input  wire        ddr_clk,
  input  wire  [7:0] keys,
  output wire  [7:0] leds,
  output wire        timer_irq,
  output wire [63:0] mtime,
  input  wire        software_irq,
  input  wire        external_irq,
  output wire        ai_start,
  output wire [31:0] ai_control,
  output wire [31:0] ai_src_addr,
  output wire [31:0] ai_dst_addr,
  output wire [31:0] ai_length,

  // PGL50H HMIC user port.
  output wire [HMIC_ADDR_WIDTH-1:0]   axi_awaddr,
  output wire                         axi_awuser_ap,
  output wire [3:0]                   axi_awuser_id,
  output wire [3:0]                   axi_awlen,
  input  wire                         axi_awready,
  output wire                         axi_awvalid,
  output wire [HMIC_DATA_WIDTH-1:0]   axi_wdata,
  output wire [HMIC_DATA_WIDTH/8-1:0] axi_wstrb,
  input  wire                         axi_wready,
  input  wire [3:0]                   axi_wusero_id,
  input  wire                         axi_wusero_last,
  output wire [HMIC_ADDR_WIDTH-1:0]   axi_araddr,
  output wire                         axi_aruser_ap,
  output wire [3:0]                   axi_aruser_id,
  output wire [3:0]                   axi_arlen,
  input  wire                         axi_arready,
  output wire                         axi_arvalid,
  input  wire [HMIC_DATA_WIDTH-1:0]   axi_rdata,
  input  wire [3:0]                   axi_rid,
  input  wire                         axi_rlast,
  input  wire                         axi_rvalid
);

  wire        if_cmd_valid;
  wire        if_cmd_ready;
  wire [31:0] if_cmd_address;
  wire        if_cmd_io;
  wire        if_rsp_valid;
  wire        if_rsp_ready;
  wire [63:0] if_rsp_data;
  wire        if_rsp_error;

  wire        peripheral_cmd_valid;
  wire        peripheral_cmd_ready;
  wire        peripheral_cmd_write;
  wire [31:0] peripheral_cmd_address;
  wire [31:0] peripheral_cmd_data;
  wire  [3:0] peripheral_cmd_mask;
  wire  [1:0] peripheral_cmd_size;
  wire        peripheral_rsp_valid;
  wire        peripheral_rsp_error;
  wire [31:0] peripheral_rsp_data;

  wire        d_read_cmd_valid;
  wire        d_read_cmd_ready;
  wire  [0:0] d_read_cmd_id;
  wire [31:0] d_read_cmd_address;
  wire        d_read_rsp_valid;
  wire        d_read_rsp_ready;
  wire  [0:0] d_read_rsp_id;
  wire [63:0] d_read_rsp_data;
  wire        d_read_rsp_error;

  wire        d_write_cmd_valid;
  wire        d_write_cmd_ready;
  wire        d_write_cmd_last;
  wire [31:0] d_write_cmd_address;
  wire [63:0] d_write_cmd_data;
  wire  [0:0] d_write_cmd_id;
  wire        d_write_rsp_valid;
  wire        d_write_rsp_error;
  wire  [0:0] d_write_rsp_id;

  wire [31:0] ai_status_value;
  wire        axi_fabric_irq;
  wire        cpu_external_irq = external_irq | axi_fabric_irq;

  NaxRiscvContest u_cpu (
    .FetchCachePlugin_mem_cmd_valid(if_cmd_valid),
    .FetchCachePlugin_mem_cmd_ready(if_cmd_ready),
    .FetchCachePlugin_mem_cmd_payload_address(if_cmd_address),
    .FetchCachePlugin_mem_cmd_payload_io(if_cmd_io),
    .FetchCachePlugin_mem_rsp_valid(if_rsp_valid),
    .FetchCachePlugin_mem_rsp_ready(if_rsp_ready),
    .FetchCachePlugin_mem_rsp_payload_data(if_rsp_data),
    .FetchCachePlugin_mem_rsp_payload_error(if_rsp_error),
    .PrivilegedPlugin_io_int_machine_timer(timer_irq),
    .PrivilegedPlugin_io_int_machine_software(software_irq),
    .PrivilegedPlugin_io_int_machine_external(cpu_external_irq),
    .PrivilegedPlugin_io_rdtime(mtime),
    .LsuPlugin_peripheralBus_cmd_valid(peripheral_cmd_valid),
    .LsuPlugin_peripheralBus_cmd_ready(peripheral_cmd_ready),
    .LsuPlugin_peripheralBus_cmd_payload_write(peripheral_cmd_write),
    .LsuPlugin_peripheralBus_cmd_payload_address(peripheral_cmd_address),
    .LsuPlugin_peripheralBus_cmd_payload_data(peripheral_cmd_data),
    .LsuPlugin_peripheralBus_cmd_payload_mask(peripheral_cmd_mask),
    .LsuPlugin_peripheralBus_cmd_payload_size(peripheral_cmd_size),
    .LsuPlugin_peripheralBus_rsp_valid(peripheral_rsp_valid),
    .LsuPlugin_peripheralBus_rsp_payload_error(peripheral_rsp_error),
    .LsuPlugin_peripheralBus_rsp_payload_data(peripheral_rsp_data),
    .DataCachePlugin_mem_read_cmd_valid(d_read_cmd_valid),
    .DataCachePlugin_mem_read_cmd_ready(d_read_cmd_ready),
    .DataCachePlugin_mem_read_cmd_payload_id(d_read_cmd_id),
    .DataCachePlugin_mem_read_cmd_payload_address(d_read_cmd_address),
    .DataCachePlugin_mem_read_rsp_valid(d_read_rsp_valid),
    .DataCachePlugin_mem_read_rsp_ready(d_read_rsp_ready),
    .DataCachePlugin_mem_read_rsp_payload_id(d_read_rsp_id),
    .DataCachePlugin_mem_read_rsp_payload_data(d_read_rsp_data),
    .DataCachePlugin_mem_read_rsp_payload_error(d_read_rsp_error),
    .DataCachePlugin_mem_write_cmd_valid(d_write_cmd_valid),
    .DataCachePlugin_mem_write_cmd_ready(d_write_cmd_ready),
    .DataCachePlugin_mem_write_cmd_payload_last(d_write_cmd_last),
    .DataCachePlugin_mem_write_cmd_payload_fragment_address(d_write_cmd_address),
    .DataCachePlugin_mem_write_cmd_payload_fragment_data(d_write_cmd_data),
    .DataCachePlugin_mem_write_cmd_payload_fragment_id(d_write_cmd_id),
    .DataCachePlugin_mem_write_rsp_valid(d_write_rsp_valid),
    .DataCachePlugin_mem_write_rsp_payload_error(d_write_rsp_error),
    .DataCachePlugin_mem_write_rsp_payload_id(d_write_rsp_id),
    .clk(clk),
    .reset(reset)
  );

  generate
    if (USE_AXI_FABRIC != 0) begin : g_axi_fabric
      // CPU adapter master 0 (I) and master 1 (D).
      wire [3:0]   m0_arid, m0_arlen, m0_rid;
      wire [31:0]  m0_araddr;
      wire         m0_arvalid, m0_arready, m0_rvalid, m0_rready, m0_rlast;
      wire [255:0] m0_rdata;
      wire [1:0]   m0_rresp;
      wire [3:0]   m1_awid, m1_awlen, m1_arid, m1_arlen, m1_bid, m1_rid;
      wire [31:0]  m1_awaddr, m1_araddr;
      wire [255:0] m1_wdata, m1_rdata;
      wire [31:0]  m1_wstrb;
      wire         m1_awvalid, m1_awready, m1_wvalid, m1_wready, m1_wlast;
      wire         m1_bvalid, m1_bready, m1_arvalid, m1_arready, m1_rvalid, m1_rready, m1_rlast;
      wire [1:0]   m1_bresp, m1_rresp;

      wire [3:0]   m2_awid, m2_awlen, m2_arid, m2_arlen, m2_bid, m2_rid;
      wire [31:0]  m2_awaddr, m2_araddr;
      wire [255:0] m2_wdata, m2_rdata;
      wire [31:0]  m2_wstrb;
      wire         m2_awvalid, m2_awready, m2_wvalid, m2_wready, m2_wlast;
      wire         m2_bvalid, m2_bready, m2_arvalid, m2_arready, m2_rvalid, m2_rready, m2_rlast;
      wire [1:0]   m2_bresp, m2_rresp;

      wire [3:0]   m3_awid, m3_awlen, m3_arid, m3_arlen, m3_bid, m3_rid;
      wire [31:0]  m3_awaddr, m3_araddr;
      wire [255:0] m3_wdata, m3_rdata;
      wire [31:0]  m3_wstrb;
      wire         m3_awvalid, m3_awready, m3_wvalid, m3_wready, m3_wlast;
      wire         m3_bvalid, m3_bready, m3_arvalid, m3_arready, m3_rvalid, m3_rready, m3_rlast;
      wire [1:0]   m3_bresp, m3_rresp;

      wire [3:0]   f_awid, f_awlen, f_bid, f_arid, f_arlen, f_rid;
      wire [31:0]  f_awaddr, f_araddr;
      wire [255:0] f_wdata, f_rdata;
      wire [31:0]  f_wstrb;
      wire         f_awvalid, f_awready, f_wvalid, f_wready, f_wlast;
      wire         f_bvalid, f_bready, f_arvalid, f_arready, f_rvalid, f_rready, f_rlast;
      wire [1:0]   f_bresp, f_rresp;

      wire [5:0] irq_enable;
      wire [5:0] irq_clear;
      wire [5:0] irq_pending;
      wire [31:0] dma_status_value;
      wire dma_start;
      wire [31:0] dma_control, dma_src_addr, dma_dst_addr, dma_length, dma_stride;
      wire [31:0] ai_channels_cfg, ai_scale_cfg;
      wire ai_done_irq, ai_error_irq, dma_done_irq, dma_error_irq;
      wire [31:0] qspi_control_unused, qspi_txdata_unused;
      wire        pixel_ready_unused;
      wire        m0_awready_unused, m0_wready_unused, m0_bvalid_unused;
      wire [3:0]  m0_bid_unused;
      wire [1:0]  m0_bresp_unused;
      wire [7:0]  perf_max_wait0, perf_max_wait1, perf_max_wait2, perf_max_wait3;

      // The AXI fabric and all compute engines run on pll_clk_sys.  The
      // generated HMIC user port is crossed explicitly to ddrphy_clkin by
      // the single-outstanding mailbox below.
      wire [HMIC_ADDR_WIDTH-1:0]   hmic_awaddr;
      wire                         hmic_awuser_ap;
      wire [3:0]                   hmic_awuser_id;
      wire [3:0]                   hmic_awlen;
      wire                         hmic_awready;
      wire                         hmic_awvalid;
      wire [HMIC_DATA_WIDTH-1:0]   hmic_wdata;
      wire [HMIC_DATA_WIDTH/8-1:0] hmic_wstrb;
      wire                         hmic_wready;
      wire [3:0]                   hmic_wusero_id;
      wire                         hmic_wusero_last;
      wire [HMIC_ADDR_WIDTH-1:0]   hmic_araddr;
      wire                         hmic_aruser_ap;
      wire [3:0]                   hmic_aruser_id;
      wire [3:0]                   hmic_arlen;
      wire                         hmic_arready;
      wire                         hmic_arvalid;
      wire [HMIC_DATA_WIDTH-1:0]   hmic_rdata;
      wire [3:0]                   hmic_rid;
      wire                         hmic_rlast;
      wire                         hmic_rvalid;

      pgl50h_cpu_axi_adapter #(
        .ADDR_WIDTH(32), .DATA_WIDTH(256), .ID_WIDTH(4), .CPU_MEM_BASE(32'h8000_0000)
      ) u_cpu_axi_adapter (
        .clk(clk), .reset(reset), .init_done(ddr_init_done),
        .if_cmd_valid(if_cmd_valid), .if_cmd_ready(if_cmd_ready),
        .if_cmd_address(if_cmd_address), .if_rsp_valid(if_rsp_valid),
        .if_rsp_ready(if_rsp_ready), .if_rsp_data(if_rsp_data), .if_rsp_error(if_rsp_error),
        .d_read_cmd_valid(d_read_cmd_valid), .d_read_cmd_ready(d_read_cmd_ready),
        .d_read_cmd_id(d_read_cmd_id), .d_read_cmd_address(d_read_cmd_address),
        .d_read_rsp_valid(d_read_rsp_valid), .d_read_rsp_ready(d_read_rsp_ready),
        .d_read_rsp_id(d_read_rsp_id), .d_read_rsp_data(d_read_rsp_data), .d_read_rsp_error(d_read_rsp_error),
        .d_write_cmd_valid(d_write_cmd_valid), .d_write_cmd_ready(d_write_cmd_ready),
        .d_write_cmd_last(d_write_cmd_last), .d_write_cmd_address(d_write_cmd_address),
        .d_write_cmd_data(d_write_cmd_data), .d_write_cmd_id(d_write_cmd_id),
        .d_write_rsp_valid(d_write_rsp_valid), .d_write_rsp_id(d_write_rsp_id), .d_write_rsp_error(d_write_rsp_error),
        .if_axi_arid(m0_arid), .if_axi_araddr(m0_araddr), .if_axi_arlen(m0_arlen),
        .if_axi_arvalid(m0_arvalid), .if_axi_arready(m0_arready), .if_axi_rid(m0_rid),
        .if_axi_rdata(m0_rdata), .if_axi_rresp(m0_rresp), .if_axi_rlast(m0_rlast),
        .if_axi_rvalid(m0_rvalid), .if_axi_rready(m0_rready),
        .d_axi_arid(m1_arid), .d_axi_araddr(m1_araddr), .d_axi_arlen(m1_arlen),
        .d_axi_arvalid(m1_arvalid), .d_axi_arready(m1_arready), .d_axi_rid(m1_rid),
        .d_axi_rdata(m1_rdata), .d_axi_rresp(m1_rresp), .d_axi_rlast(m1_rlast),
        .d_axi_rvalid(m1_rvalid), .d_axi_rready(m1_rready),
        .d_axi_awid(m1_awid), .d_axi_awaddr(m1_awaddr), .d_axi_awlen(m1_awlen),
        .d_axi_awvalid(m1_awvalid), .d_axi_awready(m1_awready), .d_axi_wdata(m1_wdata),
        .d_axi_wstrb(m1_wstrb), .d_axi_wlast(m1_wlast), .d_axi_wvalid(m1_wvalid),
        .d_axi_wready(m1_wready), .d_axi_bid(m1_bid), .d_axi_bresp(m1_bresp),
        .d_axi_bvalid(m1_bvalid), .d_axi_bready(m1_bready)
      );

      pgl50h_csr_fabric u_csr_fabric (
        .clk(clk), .reset(reset),
        .cmd_valid(peripheral_cmd_valid), .cmd_write(peripheral_cmd_write),
        .cmd_addr(peripheral_cmd_address), .cmd_wdata(peripheral_cmd_data),
        .cmd_wstrb(peripheral_cmd_mask), .cmd_ready(peripheral_cmd_ready),
        .rsp_valid(peripheral_rsp_valid), .rsp_rdata(peripheral_rsp_data),
        .rsp_error(peripheral_rsp_error), .keys(keys), .leds(leds),
        .timer_irq(timer_irq), .mtime_value(mtime), .ai_status(ai_status_value),
        .ai_start(ai_start), .ai_control(ai_control), .ai_src_addr(ai_src_addr),
        .ai_dst_addr(ai_dst_addr), .ai_length(ai_length), .ai_channels(ai_channels_cfg), .ai_scale(ai_scale_cfg),
        .dma_status(dma_status_value), .dma_start(dma_start), .dma_control(dma_control),
        .dma_src_addr(dma_src_addr), .dma_dst_addr(dma_dst_addr), .dma_length(dma_length),
        .dma_stride(dma_stride), .qspi_status(32'h0), .qspi_rxdata(32'h0),
        .qspi_control(qspi_control_unused), .qspi_txdata(qspi_txdata_unused), .irq_enable(irq_enable), .irq_clear(irq_clear),
        .irq_pending(irq_pending)
      );

      pgl50h_ai_engine u_ai_engine (
        .clk(clk), .reset(reset), .start(ai_start), .control(ai_control),
        .src_addr(ai_src_addr), .dst_addr(ai_dst_addr), .length(ai_length),
        .channels(ai_channels_cfg), .scale(ai_scale_cfg), .status(ai_status_value),
        .done_irq(ai_done_irq), .error_irq(ai_error_irq),
        .m_awid(m2_awid), .m_awaddr(m2_awaddr), .m_awlen(m2_awlen), .m_awvalid(m2_awvalid), .m_awready(m2_awready),
        .m_wdata(m2_wdata), .m_wstrb(m2_wstrb), .m_wlast(m2_wlast), .m_wvalid(m2_wvalid), .m_wready(m2_wready),
        .m_bid(m2_bid), .m_bresp(m2_bresp), .m_bvalid(m2_bvalid), .m_bready(m2_bready),
        .m_arid(m2_arid), .m_araddr(m2_araddr), .m_arlen(m2_arlen), .m_arvalid(m2_arvalid), .m_arready(m2_arready),
        .m_rid(m2_rid), .m_rdata(m2_rdata), .m_rresp(m2_rresp), .m_rlast(m2_rlast), .m_rvalid(m2_rvalid), .m_rready(m2_rready)
      );

      pgl50h_camera_dma u_camera_dma (
        .clk(clk), .reset(reset), .start(dma_start), .control(dma_control),
        .src_addr(dma_src_addr), .dst_addr(dma_dst_addr), .length(dma_length), .stride(dma_stride),
        .status(dma_status_value), .done_irq(dma_done_irq), .error_irq(dma_error_irq),
        .pixel_valid(1'b0), .pixel_ready(pixel_ready_unused), .pixel_data(32'h0), .pixel_sof(1'b0), .pixel_eol(1'b0),
        .m_awid(m3_awid), .m_awaddr(m3_awaddr), .m_awlen(m3_awlen), .m_awvalid(m3_awvalid), .m_awready(m3_awready),
        .m_wdata(m3_wdata), .m_wstrb(m3_wstrb), .m_wlast(m3_wlast), .m_wvalid(m3_wvalid), .m_wready(m3_wready),
        .m_bid(m3_bid), .m_bresp(m3_bresp), .m_bvalid(m3_bvalid), .m_bready(m3_bready),
        .m_arid(m3_arid), .m_araddr(m3_araddr), .m_arlen(m3_arlen), .m_arvalid(m3_arvalid), .m_arready(m3_arready),
        .m_rid(m3_rid), .m_rdata(m3_rdata), .m_rresp(m3_rresp), .m_rlast(m3_rlast), .m_rvalid(m3_rvalid), .m_rready(m3_rready)
      );

      pgl50h_interrupt_aggregator u_irq_aggregator (
        .clk(clk), .reset(reset), .timer_irq(timer_irq), .ai_done_irq(ai_done_irq),
        .ai_error_irq(ai_error_irq), .dma_done_irq(dma_done_irq), .dma_error_irq(dma_error_irq),
        .qspi_irq(1'b0), .enable(irq_enable), .clear(irq_clear), .pending(irq_pending),
        .irq(axi_fabric_irq)
      );

      // I master has no write channel; tie those inputs off and keep its
      // response channels permanently ready at the fabric boundary.
      pgl50h_axi4_mem_fabric u_axi_fabric (
        .clk(clk), .reset(reset), .init_done(ddr_init_done),
        .m0_awid(4'h0), .m0_awaddr(32'h0), .m0_awlen(4'h0), .m0_awvalid(1'b0), .m0_awready(m0_awready_unused),
        .m0_wdata(256'h0), .m0_wstrb(32'h0), .m0_wlast(1'b1), .m0_wvalid(1'b0), .m0_wready(m0_wready_unused),
        .m0_bid(m0_bid_unused), .m0_bresp(m0_bresp_unused), .m0_bvalid(m0_bvalid_unused), .m0_bready(1'b1),
        .m0_arid(m0_arid), .m0_araddr(m0_araddr), .m0_arlen(m0_arlen), .m0_arvalid(m0_arvalid), .m0_arready(m0_arready),
        .m0_rid(m0_rid), .m0_rdata(m0_rdata), .m0_rresp(m0_rresp), .m0_rlast(m0_rlast), .m0_rvalid(m0_rvalid), .m0_rready(m0_rready),
        .m1_awid(m1_awid), .m1_awaddr(m1_awaddr), .m1_awlen(m1_awlen), .m1_awvalid(m1_awvalid), .m1_awready(m1_awready),
        .m1_wdata(m1_wdata), .m1_wstrb(m1_wstrb), .m1_wlast(m1_wlast), .m1_wvalid(m1_wvalid), .m1_wready(m1_wready),
        .m1_bid(m1_bid), .m1_bresp(m1_bresp), .m1_bvalid(m1_bvalid), .m1_bready(m1_bready),
        .m1_arid(m1_arid), .m1_araddr(m1_araddr), .m1_arlen(m1_arlen), .m1_arvalid(m1_arvalid), .m1_arready(m1_arready),
        .m1_rid(m1_rid), .m1_rdata(m1_rdata), .m1_rresp(m1_rresp), .m1_rlast(m1_rlast), .m1_rvalid(m1_rvalid), .m1_rready(m1_rready),
        .m2_awid(m2_awid), .m2_awaddr(m2_awaddr), .m2_awlen(m2_awlen), .m2_awvalid(m2_awvalid), .m2_awready(m2_awready),
        .m2_wdata(m2_wdata), .m2_wstrb(m2_wstrb), .m2_wlast(m2_wlast), .m2_wvalid(m2_wvalid), .m2_wready(m2_wready),
        .m2_bid(m2_bid), .m2_bresp(m2_bresp), .m2_bvalid(m2_bvalid), .m2_bready(m2_bready),
        .m2_arid(m2_arid), .m2_araddr(m2_araddr), .m2_arlen(m2_arlen), .m2_arvalid(m2_arvalid), .m2_arready(m2_arready),
        .m2_rid(m2_rid), .m2_rdata(m2_rdata), .m2_rresp(m2_rresp), .m2_rlast(m2_rlast), .m2_rvalid(m2_rvalid), .m2_rready(m2_rready),
        .m3_awid(m3_awid), .m3_awaddr(m3_awaddr), .m3_awlen(m3_awlen), .m3_awvalid(m3_awvalid), .m3_awready(m3_awready),
        .m3_wdata(m3_wdata), .m3_wstrb(m3_wstrb), .m3_wlast(m3_wlast), .m3_wvalid(m3_wvalid), .m3_wready(m3_wready),
        .m3_bid(m3_bid), .m3_bresp(m3_bresp), .m3_bvalid(m3_bvalid), .m3_bready(m3_bready),
        .m3_arid(m3_arid), .m3_araddr(m3_araddr), .m3_arlen(m3_arlen), .m3_arvalid(m3_arvalid), .m3_arready(m3_arready),
        .m3_rid(m3_rid), .m3_rdata(m3_rdata), .m3_rresp(m3_rresp), .m3_rlast(m3_rlast), .m3_rvalid(m3_rvalid), .m3_rready(m3_rready),
        .d_awid(f_awid), .d_awaddr(f_awaddr), .d_awlen(f_awlen), .d_awvalid(f_awvalid), .d_awready(f_awready),
        .d_wdata(f_wdata), .d_wstrb(f_wstrb), .d_wlast(f_wlast), .d_wvalid(f_wvalid), .d_wready(f_wready),
        .d_bid(f_bid), .d_bresp(f_bresp), .d_bvalid(f_bvalid), .d_bready(f_bready),
        .d_arid(f_arid), .d_araddr(f_araddr), .d_arlen(f_arlen), .d_arvalid(f_arvalid), .d_arready(f_arready),
        .d_rid(f_rid), .d_rdata(f_rdata), .d_rresp(f_rresp), .d_rlast(f_rlast), .d_rvalid(f_rvalid), .d_rready(f_rready),
        .perf_max_wait0(perf_max_wait0), .perf_max_wait1(perf_max_wait1), .perf_max_wait2(perf_max_wait2), .perf_max_wait3(perf_max_wait3)
      );

      pgl50h_axi4_hmic_adapter #(
        .AXI_ADDR_WIDTH(32), .HMIC_ADDR_WIDTH(HMIC_ADDR_WIDTH),
        .AXI_DATA_WIDTH(256), .ID_WIDTH(4), .CPU_MEM_BASE(32'h8000_0000), .HMIC_ADDR_SHIFT(3)
      ) u_axi4_hmic (
        .clk(clk), .reset(reset), .init_done(ddr_init_done),
        .s_axi_awid(f_awid), .s_axi_awaddr(f_awaddr), .s_axi_awlen(f_awlen), .s_axi_awvalid(f_awvalid), .s_axi_awready(f_awready),
        .s_axi_wdata(f_wdata), .s_axi_wstrb(f_wstrb), .s_axi_wlast(f_wlast), .s_axi_wvalid(f_wvalid), .s_axi_wready(f_wready),
        .s_axi_bid(f_bid), .s_axi_bresp(f_bresp), .s_axi_bvalid(f_bvalid), .s_axi_bready(f_bready),
        .s_axi_arid(f_arid), .s_axi_araddr(f_araddr), .s_axi_arlen(f_arlen), .s_axi_arvalid(f_arvalid), .s_axi_arready(f_arready),
        .s_axi_rid(f_rid), .s_axi_rdata(f_rdata), .s_axi_rresp(f_rresp), .s_axi_rlast(f_rlast), .s_axi_rvalid(f_rvalid), .s_axi_rready(f_rready),
        .axi_awaddr(hmic_awaddr), .axi_awuser_ap(hmic_awuser_ap), .axi_awuser_id(hmic_awuser_id), .axi_awlen(hmic_awlen),
        .axi_awready(hmic_awready), .axi_awvalid(hmic_awvalid), .axi_wdata(hmic_wdata), .axi_wstrb(hmic_wstrb),
        .axi_wready(hmic_wready), .axi_wusero_id(hmic_wusero_id), .axi_wusero_last(hmic_wusero_last),
        .axi_araddr(hmic_araddr), .axi_aruser_ap(hmic_aruser_ap), .axi_aruser_id(hmic_aruser_id), .axi_arlen(hmic_arlen),
        .axi_arready(hmic_arready), .axi_arvalid(hmic_arvalid), .axi_rdata(hmic_rdata), .axi_rid(hmic_rid),
        .axi_rlast(hmic_rlast), .axi_rvalid(hmic_rvalid)
      );

      wire ddr_cdc_reset;
      pgl50h_ddr_cdc_reset u_ddr_cdc_reset (
        .ddr_clk(ddr_clk),
        .async_reset(reset | !ddr_init_done),
        .ddr_reset(ddr_cdc_reset)
      );

      pgl50h_axi_hmic_cdc #(
        .ADDR_WIDTH(HMIC_ADDR_WIDTH), .DATA_WIDTH(HMIC_DATA_WIDTH), .ID_WIDTH(4)
      ) u_axi_hmic_cdc (
        .src_clk(clk), .src_reset(reset),
        .dst_clk(ddr_clk), .dst_reset(ddr_cdc_reset),
        .s_awaddr(hmic_awaddr), .s_awuser_ap(hmic_awuser_ap), .s_awuser_id(hmic_awuser_id),
        .s_awlen(hmic_awlen), .s_awvalid(hmic_awvalid), .s_awready(hmic_awready),
        .s_wdata(hmic_wdata), .s_wstrb(hmic_wstrb), .s_wready(hmic_wready),
        .s_wusero_id(hmic_wusero_id), .s_wusero_last(hmic_wusero_last),
        .s_araddr(hmic_araddr), .s_aruser_ap(hmic_aruser_ap), .s_aruser_id(hmic_aruser_id),
        .s_arlen(hmic_arlen), .s_arvalid(hmic_arvalid), .s_arready(hmic_arready),
        .s_rdata(hmic_rdata), .s_rid(hmic_rid), .s_rlast(hmic_rlast), .s_rvalid(hmic_rvalid),
        .d_awaddr(axi_awaddr), .d_awuser_ap(axi_awuser_ap), .d_awuser_id(axi_awuser_id),
        .d_awlen(axi_awlen), .d_awvalid(axi_awvalid), .d_awready(axi_awready),
        .d_wdata(axi_wdata), .d_wstrb(axi_wstrb), .d_wready(axi_wready),
        .d_wusero_id(axi_wusero_id), .d_wusero_last(axi_wusero_last),
        .d_araddr(axi_araddr), .d_aruser_ap(axi_aruser_ap), .d_aruser_id(axi_aruser_id),
        .d_arlen(axi_arlen), .d_arvalid(axi_arvalid), .d_arready(axi_arready),
        .d_rdata(axi_rdata), .d_rid(axi_rid), .d_rlast(axi_rlast), .d_rvalid(axi_rvalid)
      );
    end else begin : g_legacy
      assign axi_fabric_irq = 1'b0;

      if (USE_DDR_AXI != 0) begin : g_ddr_axi
        pgl50h_native_axi_bridge #(
          .AXI_ADDR_WIDTH(HMIC_ADDR_WIDTH), .AXI_DATA_WIDTH(HMIC_DATA_WIDTH),
          .CPU_MEM_BASE(32'h8000_0000), .HMIC_ADDR_SHIFT(3)
        ) u_native_axi_bridge (
          .clk(clk), .reset(reset), .init_done(ddr_init_done),
          .if_cmd_valid(if_cmd_valid), .if_cmd_ready(if_cmd_ready), .if_cmd_address(if_cmd_address),
          .if_rsp_valid(if_rsp_valid), .if_rsp_ready(if_rsp_ready), .if_rsp_data(if_rsp_data), .if_rsp_error(if_rsp_error),
          .d_read_cmd_valid(d_read_cmd_valid), .d_read_cmd_ready(d_read_cmd_ready), .d_read_cmd_id(d_read_cmd_id), .d_read_cmd_address(d_read_cmd_address),
          .d_read_rsp_valid(d_read_rsp_valid), .d_read_rsp_ready(d_read_rsp_ready), .d_read_rsp_id(d_read_rsp_id), .d_read_rsp_data(d_read_rsp_data), .d_read_rsp_error(d_read_rsp_error),
          .d_write_cmd_valid(d_write_cmd_valid), .d_write_cmd_ready(d_write_cmd_ready), .d_write_cmd_last(d_write_cmd_last), .d_write_cmd_address(d_write_cmd_address), .d_write_cmd_data(d_write_cmd_data), .d_write_cmd_id(d_write_cmd_id),
          .d_write_rsp_valid(d_write_rsp_valid), .d_write_rsp_id(d_write_rsp_id), .d_write_rsp_error(d_write_rsp_error),
          .axi_awaddr(axi_awaddr), .axi_awuser_ap(axi_awuser_ap), .axi_awuser_id(axi_awuser_id), .axi_awlen(axi_awlen), .axi_awready(axi_awready), .axi_awvalid(axi_awvalid),
          .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb), .axi_wready(axi_wready), .axi_wusero_id(axi_wusero_id), .axi_wusero_last(axi_wusero_last),
          .axi_araddr(axi_araddr), .axi_aruser_ap(axi_aruser_ap), .axi_aruser_id(axi_aruser_id), .axi_arlen(axi_arlen), .axi_arready(axi_arready), .axi_arvalid(axi_arvalid), .axi_rdata(axi_rdata), .axi_rid(axi_rid), .axi_rlast(axi_rlast), .axi_rvalid(axi_rvalid)
        );
      end else begin : g_fallback_mem
        pgl50h_mem_fabric u_mem_fabric (
          .clk(clk), .reset(reset), .if_cmd_valid(if_cmd_valid), .if_cmd_ready(if_cmd_ready), .if_cmd_address(if_cmd_address), .if_rsp_valid(if_rsp_valid), .if_rsp_ready(if_rsp_ready), .if_rsp_data(if_rsp_data), .if_rsp_error(if_rsp_error),
          .d_read_cmd_valid(d_read_cmd_valid), .d_read_cmd_ready(d_read_cmd_ready), .d_read_cmd_id(d_read_cmd_id), .d_read_cmd_address(d_read_cmd_address), .d_read_rsp_valid(d_read_rsp_valid), .d_read_rsp_ready(d_read_rsp_ready), .d_read_rsp_id(d_read_rsp_id), .d_read_rsp_data(d_read_rsp_data), .d_read_rsp_error(d_read_rsp_error),
          .d_write_cmd_valid(d_write_cmd_valid), .d_write_cmd_ready(d_write_cmd_ready), .d_write_cmd_last(d_write_cmd_last), .d_write_cmd_address(d_write_cmd_address), .d_write_cmd_data(d_write_cmd_data), .d_write_cmd_id(d_write_cmd_id), .d_write_rsp_valid(d_write_rsp_valid), .d_write_rsp_ready(1'b1), .d_write_rsp_id(d_write_rsp_id), .d_write_rsp_error(d_write_rsp_error)
        );
        assign axi_awaddr = {HMIC_ADDR_WIDTH{1'b0}};
        assign axi_awuser_ap = 1'b0;
        assign axi_awuser_id = 4'h0;
        assign axi_awlen = 4'h0;
        assign axi_awvalid = 1'b0;
        assign axi_wdata = {HMIC_DATA_WIDTH{1'b0}};
        assign axi_wstrb = {(HMIC_DATA_WIDTH/8){1'b0}};
        assign axi_araddr = {HMIC_ADDR_WIDTH{1'b0}};
        assign axi_aruser_ap = 1'b0;
        assign axi_aruser_id = 4'h0;
        assign axi_arlen = 4'h0;
        assign axi_arvalid = 1'b0;
      end

      pgl50h_peripherals u_peripherals (
        .clk(clk), .reset(reset), .cmd_valid(peripheral_cmd_valid), .cmd_write(peripheral_cmd_write), .cmd_addr(peripheral_cmd_address), .cmd_wdata(peripheral_cmd_data), .cmd_wstrb(peripheral_cmd_mask), .cmd_ready(peripheral_cmd_ready), .rsp_valid(peripheral_rsp_valid), .rsp_rdata(peripheral_rsp_data), .rsp_error(peripheral_rsp_error), .keys(keys), .leds(leds), .timer_irq(timer_irq), .mtime_value(mtime), .ai_start(ai_start), .ai_control(ai_control), .ai_src_addr(ai_src_addr), .ai_dst_addr(ai_dst_addr), .ai_length(ai_length), .ai_status_value(ai_status_value)
      );

      pgl50h_ai_accel_stub u_ai_accel (
        .clk(clk), .reset(reset), .start(ai_start), .control(ai_control), .src_addr(ai_src_addr), .dst_addr(ai_dst_addr), .length(ai_length), .status(ai_status_value)
      );
    end
  endgenerate

endmodule
