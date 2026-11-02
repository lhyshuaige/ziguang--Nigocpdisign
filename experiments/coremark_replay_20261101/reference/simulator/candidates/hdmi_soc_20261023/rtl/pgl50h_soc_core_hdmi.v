// CPU-centric SoC layer.
//
// USE_AXI_FABRIC=0 keeps the proven legacy native bridge/fallback paths.
// USE_AXI_FABRIC=1 enables the complete contest skeleton: CPU I/D adapters,
// four-master AXI fabric, AXI4-to-HMIC boundary, CSR fabric, INT8 engine,
// camera/DMA master, and sticky interrupt aggregation.
module pgl50h_soc_core #(
  parameter integer USE_HDMI = 1,
  parameter integer HDMI_H_ACT=1280,HDMI_H_FP=110,HDMI_H_SYNC=40,HDMI_H_BP=220,
  parameter integer HDMI_V_ACT=720,HDMI_V_FP=5,HDMI_V_SYNC=5,HDMI_V_BP=20,
  parameter integer HDMI_FIFO_DEPTH=2048,HDMI_PREFILL=32,HDMI_REQUIRE_TX_INIT=1,
  parameter integer USE_DDR_AXI    = 0,
  parameter integer USE_AXI_FABRIC = 0,
  parameter integer HMIC_ADDR_WIDTH = 28,
  parameter integer HMIC_DATA_WIDTH = 256
) (
  input  wire        clk,
  input  wire        reset,
  input  wire        ddr_init_done,
  input  wire        ddr_clk,
  input wire hdmi_pixel_clk,hdmi_pixel_reset,hdmi_pll_locked,
  input wire hdmi_scl_i,hdmi_sda_i,hdmi_int_n,
  output wire [23:0] hdmi_rgb,
  output wire hdmi_hs,hdmi_vs,hdmi_de,hdmi_scl_low,hdmi_sda_low,hdmi_reset_n,
  input  wire  [7:0] keys,
  // Optional camera pins.  The board top may leave these unconnected until
  // the OV7670 IO-bank constraints are enabled; the default input selector
  // remains DDR replay.
  input  wire        cam_pclk,
  input  wire        cam_vsync,
  input  wire        cam_href,
  input  wire  [7:0] cam_data,
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
  wire hdmi_irq;
  wire        cpu_external_irq = external_irq | axi_fabric_irq | hdmi_irq;

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
      wire [31:0] dma_src_stride, dma_dst_stride, dma_image_width, dma_image_height;
      wire [31:0] dma_output_width, dma_output_height;
      wire [31:0] ai_channels_cfg, ai_scale_cfg;
      wire ai_done_irq, ai_error_irq, dma_done_irq, dma_error_irq;
      wire [31:0] qspi_control_unused, qspi_txdata_unused;
      wire        pixel_ready_unused;
      wire [31:0] vision_dma_m_tdata, vision_dma_s_tdata;
      wire [3:0]  vision_dma_m_tkeep, vision_dma_s_tkeep;
      wire        vision_dma_m_tvalid, vision_dma_m_tready, vision_dma_m_tlast, vision_dma_m_tuser;
      wire        vision_dma_s_tvalid, vision_dma_s_tready, vision_dma_s_tlast, vision_dma_s_tuser;
      wire [31:0] camera_m_tdata;
      wire [3:0]  camera_m_tkeep;
      wire        camera_m_tvalid, camera_m_tready, camera_m_tlast, camera_m_tuser;
      wire        camera_frame_active, camera_line_active;
      wire        camera_fifo_overflow, camera_fifo_empty, camera_fifo_full;
      wire [31:0] camera_fifo_level;
      wire        camera_partial_pixel_error;
      wire [31:0] vision_input_tdata;
      wire [3:0]  vision_input_tkeep;
      wire        vision_input_tvalid, vision_input_tready, vision_input_tlast, vision_input_tuser;
      wire        vision_input_active_sel, vision_input_switch_pending, vision_input_frame_active;
      wire [31:0] vision_pixel_count, vision_frame_count, vision_stall_count, vision_latency_count;
      wire        vision_resize_error, vision_width_error;
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

// Inserted inside g_axi_fabric by prepare_hdmi_soc.py. This keeps the selected
// SoC snapshot intact while producing a real HDMI-enabled hardware top.
      wire legacy_csr_valid,legacy_csr_ready,legacy_csr_rsp_valid,legacy_csr_error;
      wire [31:0] legacy_csr_rdata;
      wire hdmi_dma_requested,hdmi_dma_owned,hdmi_dma_claimed;
      wire hdmi_stream_ready,replay_stream_ready;
      wire hdmi_fetch_valid,hdmi_fetch_ready,hdmi_fetch_abort,hdmi_fetch_idle,hdmi_fetch_done,hdmi_fetch_error;
      wire [31:0] hdmi_fetch_base,hdmi_fetch_stride;
      wire [15:0] hdmi_fetch_width,hdmi_fetch_height;
      wire hdmi_job_start,hdmi_dma_reset;
      wire [31:0] hdmi_dma_base,hdmi_dma_stride;
      wire [15:0] hdmi_dma_width,hdmi_dma_height;
      wire [31:0] dma_csr_status={dma_status_value[31:1],dma_status_value[0]|hdmi_dma_claimed};
      wire dma_engine_reset=reset|(hdmi_dma_owned&&hdmi_dma_reset);
      wire dma_engine_start=(hdmi_dma_owned?hdmi_job_start:dma_start)&&ddr_init_done;
      wire [31:0] dma_engine_control=hdmi_dma_owned?32'h2:dma_control;
      wire [31:0] dma_engine_src=hdmi_dma_owned?hdmi_dma_base:dma_src_addr;
      wire [31:0] dma_engine_src_stride=hdmi_dma_owned?hdmi_dma_stride:dma_src_stride;
      wire [31:0] dma_engine_width=hdmi_dma_owned?{16'd0,hdmi_dma_width}:dma_image_width;
      wire [31:0] dma_engine_height=hdmi_dma_owned?{16'd0,hdmi_dma_height}:dma_image_height;
      wire vision_reset=reset|hdmi_dma_owned;
      wire camera_owner_reset;
      // Ownership is a sys_clk signal. Assert camera reset asynchronously and
      // release it only after two real Camera PCLK edges.
      hdmi_reset_sync u_camera_owner_reset (
        .clk(cam_pclk),.reset_request(vision_reset),.reset(camera_owner_reset));
      assign vision_dma_m_tready=hdmi_dma_owned?hdmi_stream_ready:replay_stream_ready;
      if(USE_HDMI!=0) begin:g_hdmi
        wire hc_valid,hc_ready,hc_rsp_valid,hc_error;
        wire oc_valid,oc_ready,oc_rsp_valid,oc_error;
        wire [31:0] hc_rdata,oc_rdata;
        wire [31:0] frames_unused,underflows_unused,protocols_unused;
        hdmi_soc_csr_router u_csr_router (
          .clk(clk),.reset(reset),.cmd_valid(peripheral_cmd_valid),.cmd_write(peripheral_cmd_write),
          .cmd_addr(peripheral_cmd_address),.cmd_wdata(peripheral_cmd_data),.cmd_wstrb(peripheral_cmd_mask),
          .cmd_ready(peripheral_cmd_ready),.rsp_valid(peripheral_rsp_valid),.rsp_error(peripheral_rsp_error),.rsp_rdata(peripheral_rsp_data),
          .legacy_valid(legacy_csr_valid),.legacy_ready(legacy_csr_ready),.legacy_rsp_valid(legacy_csr_rsp_valid),
          .legacy_error(legacy_csr_error),.legacy_rdata(legacy_csr_rdata),
          .hdmi_valid(hc_valid),.hdmi_ready(hc_ready),.hdmi_rsp_valid(hc_rsp_valid),.hdmi_error(hc_error),.hdmi_rdata(hc_rdata),
          .owner_valid(oc_valid),.owner_ready(oc_ready),.owner_rsp_valid(oc_rsp_valid),.owner_error(oc_error),.owner_rdata(oc_rdata));
        hdmi_dma_owner u_owner (
          .clk(clk),.reset(reset),.ddr_ready(ddr_init_done),.csr_valid(oc_valid),.csr_write(peripheral_cmd_write),
          .csr_addr(peripheral_cmd_address[11:0]),.csr_wdata(peripheral_cmd_data),.csr_wstrb(peripheral_cmd_mask),
          .csr_ready(oc_ready),.csr_rsp_valid(oc_rsp_valid),.csr_error(oc_error),.csr_rdata(oc_rdata),
          .requested(hdmi_dma_requested),.owned(hdmi_dma_owned),.claimed(hdmi_dma_claimed),
          .cpu_start(dma_start),.dma_busy(dma_status_value[0]),.dma_axis_valid(vision_dma_m_tvalid),.job_idle(hdmi_fetch_idle),
          .arvalid(m3_arvalid),.arready(m3_arready),.rvalid(m3_rvalid),.rready(m3_rready),.rlast(m3_rlast),
          .awvalid(m3_awvalid),.awready(m3_awready),.wvalid(m3_wvalid),.bvalid(m3_bvalid),.bready(m3_bready));
        hdmi_dma_job_adapter u_jobs (
          .clk(clk),.reset(reset),.fetch_valid(hdmi_fetch_valid&&hdmi_dma_owned&&hdmi_dma_requested&&ddr_init_done),
          .fetch_abort(hdmi_fetch_abort||!hdmi_dma_requested),.fetch_ready(hdmi_fetch_ready),.fetch_idle(hdmi_fetch_idle),
          .fetch_base(hdmi_fetch_base),.fetch_stride(hdmi_fetch_stride),.fetch_width(hdmi_fetch_width),.fetch_height(hdmi_fetch_height),
          .fetch_done(hdmi_fetch_done),.fetch_error(hdmi_fetch_error),.dma_start(hdmi_job_start),.dma_local_reset(hdmi_dma_reset),
          .dma_base(hdmi_dma_base),.dma_stride(hdmi_dma_stride),.dma_width(hdmi_dma_width),.dma_height(hdmi_dma_height),
          .dma_status(dma_status_value),.dma_done_irq(dma_done_irq),.dma_error_irq(dma_error_irq),.dma_axis_valid(vision_dma_m_tvalid),
          .dma_arvalid(m3_arvalid),.dma_arready(m3_arready),.dma_rvalid(m3_rvalid),.dma_rready(m3_rready),.dma_rlast(m3_rlast));
        hdmi_output_subsystem #(.H_ACT(HDMI_H_ACT),.H_FP(HDMI_H_FP),.H_SYNC(HDMI_H_SYNC),.H_BP(HDMI_H_BP),
          .V_ACT(HDMI_V_ACT),.V_FP(HDMI_V_FP),.V_SYNC(HDMI_V_SYNC),.V_BP(HDMI_V_BP),
          .FIFO_DEPTH(HDMI_FIFO_DEPTH),.PREFILL_PIXELS(HDMI_PREFILL),.RESET_CONTROL(5),
          .REQUIRE_TX_INIT(HDMI_REQUIRE_TX_INIT)) u_output (
          .sys_clk(clk),.sys_reset(reset),.pixel_clk(hdmi_pixel_clk),.pixel_reset(hdmi_pixel_reset),.pll_locked(hdmi_pll_locked),
          .s_axis_tdata(vision_dma_m_tdata),.s_axis_tkeep(vision_dma_m_tkeep),
          .s_axis_tvalid(vision_dma_m_tvalid&&hdmi_dma_owned),.s_axis_tready(hdmi_stream_ready),
          .s_axis_tuser(vision_dma_m_tuser),.s_axis_tlast(vision_dma_m_tlast),
          .fetch_valid(hdmi_fetch_valid),.fetch_ready(hdmi_fetch_ready&&hdmi_dma_owned&&hdmi_dma_requested&&ddr_init_done),
          .fetch_base(hdmi_fetch_base),.fetch_stride(hdmi_fetch_stride),.fetch_width(hdmi_fetch_width),.fetch_height(hdmi_fetch_height),
          .fetch_abort(hdmi_fetch_abort),.fetch_idle(!hdmi_dma_owned||hdmi_fetch_idle),
          .fetch_done(hdmi_fetch_done&&hdmi_dma_owned),.fetch_error(hdmi_fetch_error&&hdmi_dma_owned),
          .csr_valid(hc_valid),.csr_write(peripheral_cmd_write),.csr_addr(peripheral_cmd_address[11:0]),
          .csr_wdata(peripheral_cmd_data),.csr_wstrb(peripheral_cmd_mask),.csr_ready(hc_ready),
          .csr_rsp_valid(hc_rsp_valid),.csr_error(hc_error),.csr_rdata(hc_rdata),.irq(hdmi_irq),
          .tx_scl_i(hdmi_scl_i),.tx_sda_i(hdmi_sda_i),.tx_int_n(hdmi_int_n),
          .tx_scl_drive_low(hdmi_scl_low),.tx_sda_drive_low(hdmi_sda_low),.tx_reset_n(hdmi_reset_n),
          .rgb(hdmi_rgb),.hs(hdmi_hs),.vs(hdmi_vs),.de(hdmi_de),
          .displayed_frames(frames_unused),.underflow_frames(underflows_unused),.protocol_errors(protocols_unused));
      end else begin:g_no_hdmi
        assign legacy_csr_valid=peripheral_cmd_valid;
        assign peripheral_cmd_ready=legacy_csr_ready;
        assign peripheral_rsp_valid=legacy_csr_rsp_valid;
        assign peripheral_rsp_error=legacy_csr_error;
        assign peripheral_rsp_data=legacy_csr_rdata;
        assign hdmi_dma_requested=0;assign hdmi_dma_owned=0;assign hdmi_dma_claimed=0;
        assign hdmi_stream_ready=0;assign hdmi_job_start=0;assign hdmi_dma_reset=0;
        assign hdmi_dma_base=0;assign hdmi_dma_stride=0;assign hdmi_dma_width=0;assign hdmi_dma_height=0;
        assign hdmi_irq=0;assign hdmi_rgb=0;assign hdmi_hs=0;assign hdmi_vs=0;assign hdmi_de=0;
        assign hdmi_scl_low=0;assign hdmi_sda_low=0;assign hdmi_reset_n=0;
      end

      pgl50h_csr_fabric u_csr_fabric (
        .clk(clk), .reset(reset),
        .cmd_valid(legacy_csr_valid), .cmd_write(peripheral_cmd_write),
        .cmd_addr(peripheral_cmd_address), .cmd_wdata(peripheral_cmd_data),
        .cmd_wstrb(peripheral_cmd_mask), .cmd_ready(legacy_csr_ready),
        .rsp_valid(legacy_csr_rsp_valid), .rsp_rdata(legacy_csr_rdata),
        .rsp_error(legacy_csr_error), .keys(keys), .leds(leds),
        .timer_irq(timer_irq), .mtime_value(mtime), .ai_status(ai_status_value),
        .ai_start(ai_start), .ai_control(ai_control), .ai_src_addr(ai_src_addr),
        .ai_dst_addr(ai_dst_addr), .ai_length(ai_length), .ai_channels(ai_channels_cfg), .ai_scale(ai_scale_cfg),
        .dma_status(dma_csr_status), .dma_start(dma_start), .dma_control(dma_control),
        .dma_src_addr(dma_src_addr), .dma_dst_addr(dma_dst_addr), .dma_length(dma_length),
        .dma_stride(dma_stride), .dma_src_stride(dma_src_stride), .dma_dst_stride(dma_dst_stride),
        .dma_image_width(dma_image_width), .dma_image_height(dma_image_height),
        .dma_output_width(dma_output_width), .dma_output_height(dma_output_height),
        .qspi_status(32'h0), .qspi_rxdata(32'h0),
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
        .clk(clk), .reset(dma_engine_reset), .start(dma_engine_start), .control(dma_engine_control),
        .src_addr(dma_engine_src), .dst_addr(dma_dst_addr), .length(dma_length), .stride(hdmi_dma_owned?32'd0:dma_stride),
        .src_stride(dma_engine_src_stride), .dst_stride(dma_dst_stride),
        .image_width(dma_engine_width), .image_height(dma_engine_height),
        .output_width(dma_output_width), .output_height(dma_output_height),
        .status(dma_status_value), .done_irq(dma_done_irq), .error_irq(dma_error_irq),
        .pixel_valid(1'b0), .pixel_ready(pixel_ready_unused), .pixel_data(32'h0), .pixel_sof(1'b0), .pixel_eol(1'b0),
        .m_axis_tdata(vision_dma_m_tdata), .m_axis_tkeep(vision_dma_m_tkeep),
        .m_axis_tvalid(vision_dma_m_tvalid), .m_axis_tready(vision_dma_m_tready),
        .m_axis_tlast(vision_dma_m_tlast), .m_axis_tuser(vision_dma_m_tuser),
        .s_axis_tdata(vision_dma_s_tdata), .s_axis_tkeep(vision_dma_s_tkeep),
        .s_axis_tvalid(vision_dma_s_tvalid && !hdmi_dma_owned), .s_axis_tready(vision_dma_s_tready),
        .s_axis_tlast(vision_dma_s_tlast), .s_axis_tuser(vision_dma_s_tuser),
        .m_awid(m3_awid), .m_awaddr(m3_awaddr), .m_awlen(m3_awlen), .m_awvalid(m3_awvalid), .m_awready(m3_awready),
        .m_wdata(m3_wdata), .m_wstrb(m3_wstrb), .m_wlast(m3_wlast), .m_wvalid(m3_wvalid), .m_wready(m3_wready),
        .m_bid(m3_bid), .m_bresp(m3_bresp), .m_bvalid(m3_bvalid), .m_bready(m3_bready),
        .m_arid(m3_arid), .m_araddr(m3_araddr), .m_arlen(m3_arlen), .m_arvalid(m3_arvalid), .m_arready(m3_arready),
        .m_rid(m3_rid), .m_rdata(m3_rdata), .m_rresp(m3_rresp), .m_rlast(m3_rlast), .m_rvalid(m3_rvalid), .m_rready(m3_rready)
      );

      camera_rx_subsystem #(.DATA_WIDTH(8), .FIFO_DEPTH(2048),
                            .WORD_COMPAT_TKEEP(1)) u_camera_rx_subsystem (
        .cam_pclk(cam_pclk), .cam_reset(camera_owner_reset), .cam_enable(dma_control[5] && !hdmi_dma_owned),
        .cam_vsync(cam_vsync), .cam_href(cam_href), .cam_data(cam_data),
        .soc_clk(clk), .soc_reset(vision_reset),
        .m_axis_tdata(camera_m_tdata), .m_axis_tkeep(camera_m_tkeep),
        .m_axis_tvalid(camera_m_tvalid), .m_axis_tready(camera_m_tready),
        .m_axis_tuser(camera_m_tuser), .m_axis_tlast(camera_m_tlast),
        .cam_frame_active(camera_frame_active), .cam_line_active(camera_line_active),
        .fifo_overflow(camera_fifo_overflow), .fifo_empty(camera_fifo_empty),
        .fifo_full(camera_fifo_full), .fifo_level(camera_fifo_level),
        .partial_pixel_error(camera_partial_pixel_error)
      );

      // Camera and DDR replay share the same Vision input.  DMA control bit 5
      // is reserved for the source select; the mux commits it only at a frame
      // boundary.  The default value is zero, preserving DDR replay.
      vision_input_mux u_vision_input_mux (
        .clk(clk), .reset(vision_reset), .input_sel_req(dma_control[5]),
        .switch_request(1'b1), .frame_height(dma_image_height),
        .camera_tdata(camera_m_tdata), .camera_tkeep(camera_m_tkeep),
        .camera_tvalid(camera_m_tvalid), .camera_tready(camera_m_tready),
        .camera_tuser(camera_m_tuser), .camera_tlast(camera_m_tlast),
        .replay_tdata(vision_dma_m_tdata), .replay_tkeep(vision_dma_m_tkeep),
        .replay_tvalid(vision_dma_m_tvalid && !hdmi_dma_owned), .replay_tready(replay_stream_ready),
        .replay_tuser(vision_dma_m_tuser), .replay_tlast(vision_dma_m_tlast),
        .m_tdata(vision_input_tdata), .m_tkeep(vision_input_tkeep),
        .m_tvalid(vision_input_tvalid), .m_tready(vision_input_tready),
        .m_tuser(vision_input_tuser), .m_tlast(vision_input_tlast),
        .active_sel(vision_input_active_sel),
        .switch_pending(vision_input_switch_pending),
        .frame_active(vision_input_frame_active)
      );

      // The DMA and pipeline stay in the 100 MHz AXI clock domain for the
      // first DDR integration.  The DMA stream ports remain the future CDC
      // boundary if Vision moves to a faster clock later.
      vision_pipeline_top u_vision_pipeline (
        .clk(clk), .reset(vision_reset), .format_rgb565(dma_control[3]),
        .resize_enable(dma_control[4]), .image_width(dma_image_width),
        .image_height(dma_image_height), .resize_width(dma_output_width),
        .resize_height(dma_output_height),
        .s_tdata(vision_input_tdata), .s_tkeep(vision_input_tkeep),
        .s_tvalid(vision_input_tvalid), .s_tready(vision_input_tready),
        .s_tlast(vision_input_tlast), .s_tuser(vision_input_tuser),
        .m_tdata(vision_dma_s_tdata), .m_tkeep(vision_dma_s_tkeep),
        .m_tvalid(vision_dma_s_tvalid), .m_tready(vision_dma_s_tready),
        .m_tlast(vision_dma_s_tlast), .m_tuser(vision_dma_s_tuser),
        .pixel_count(vision_pixel_count), .frame_count(vision_frame_count),
        .stall_count(vision_stall_count), .latency_count(vision_latency_count),
        .resize_config_error(vision_resize_error), .line_width_error(vision_width_error)
      );

      pgl50h_interrupt_aggregator u_irq_aggregator (
        .clk(clk), .reset(reset), .timer_irq(timer_irq), .ai_done_irq(ai_done_irq),
        .ai_error_irq(ai_error_irq), .dma_done_irq(dma_done_irq && !hdmi_dma_owned), .dma_error_irq(dma_error_irq && !hdmi_dma_owned),
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
      assign hdmi_irq=0;assign hdmi_rgb=0;assign hdmi_hs=0;assign hdmi_vs=0;assign hdmi_de=0;
      assign hdmi_scl_low=0;assign hdmi_sda_low=0;assign hdmi_reset_n=0;
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
