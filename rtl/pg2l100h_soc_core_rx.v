// Logos2 x32 HMIC: native addresses are 32-bit words.
// CPU-centric SoC layer.
//
// USE_AXI_FABRIC=0 keeps the proven legacy native bridge/fallback paths.
// USE_AXI_FABRIC=1 enables the complete contest skeleton: CPU I/D adapters,
// four-master AXI fabric, AXI4-to-HMIC boundary, CSR fabric, INT8 engine,
// camera/DMA master, and sticky interrupt aggregation.
module pg2l100h_soc_core_rx #(
  parameter integer USE_BOOT_ROM   = 0,
  parameter BOOT_ROM_FILE = "firmware/bootloader/boot64.hex",
  parameter integer USE_DDR_AXI    = 0,
  parameter integer USE_AXI_FABRIC = 0,
  parameter integer HMIC_ADDR_WIDTH = 28,
  parameter integer HMIC_DATA_WIDTH = 256
) (
input wire rx_busy,
input wire rx_dma_claim,
output wire rx_dma_grant,
input wire rx_dma_start,
input wire [31:0] rx_dma_base,
input wire [31:0] rx_dma_stride,
input wire [15:0] rx_dma_width,
input wire [15:0] rx_dma_height,
output wire [31:0] rx_dma_status,
output wire rx_dma_done,
output wire rx_dma_error,
output wire rx_dma_awvalid,
output wire rx_dma_awready,
output wire rx_dma_wvalid,
output wire rx_dma_bvalid,
output wire rx_dma_bready,
input wire [31:0] rx_dma_tdata,
input wire [3:0] rx_dma_tkeep,
input wire rx_dma_tvalid,
output wire rx_dma_tready,
input wire rx_dma_tlast,
input wire rx_dma_tuser,
  input wire [31:0] flash_status,flash_rxdata,
  output wire [31:0] flash_control,flash_txdata,
  input  wire        clk,
  input  wire        reset,
  output wire [12:0] eth_axil_awaddr,
  output wire eth_axil_awvalid,
  input wire eth_axil_awready,
  output wire [31:0] eth_axil_wdata,
  output wire [3:0] eth_axil_wstrb,
  output wire eth_axil_wvalid,
  input wire eth_axil_wready,
  input wire [1:0] eth_axil_bresp,
  input wire eth_axil_bvalid,
  output wire eth_axil_bready,
  output wire [12:0] eth_axil_araddr,
  output wire eth_axil_arvalid,
  input wire eth_axil_arready,
  input wire [31:0] eth_axil_rdata,
  input wire [1:0] eth_axil_rresp,
  input wire eth_axil_rvalid,
  output wire eth_axil_rready,
  input wire eth_job_valid,
  input wire eth_job_abort,
  input wire eth_network_ready,
  input wire [31:0] eth_job_base,
  input wire [31:0] eth_job_stride,
  input wire [15:0] eth_job_width,
  input wire [15:0] eth_job_height,
  output wire eth_job_ready,
  output wire eth_job_owner,
  output wire eth_job_done,
  output wire eth_job_error,
  output wire eth_image_start_valid,
  input wire eth_image_start_ready,
  input wire eth_image_done,
  input wire eth_image_error,
  output wire eth_image_abort,
  output wire [31:0] eth_image_tdata,
  output wire [3:0] eth_image_tkeep,
  output wire eth_image_tvalid,
  input wire eth_image_tready,
  output wire eth_image_tlast,
  output wire eth_image_tuser,
  input  wire        ddr_init_done,
  input  wire        ddr_clk,
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
      wire [31:0] dma_src_stride, dma_dst_stride, dma_image_width, dma_image_height;
      wire [31:0] dma_output_width, dma_output_height;
      wire [31:0] ai_channels_cfg, ai_scale_cfg;
      wire ai_done_irq, ai_error_irq, dma_done_irq, dma_error_irq;

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

      wire mem_if_cmd_ready,mem_if_rsp_valid,mem_if_rsp_error;
      wire [63:0] mem_if_rsp_data;
      wire mem_d_cmd_ready,mem_d_rsp_valid,mem_d_rsp_error,mem_d_rsp_id;
      wire [63:0] mem_d_rsp_data;
      wire rom_i_ready,rom_i_valid,rom_d_ready,rom_d_valid,rom_d_id;
      wire [63:0] rom_i_data,rom_d_data;
      wire rom_i_select=(USE_BOOT_ROM!=0) &&
        ((if_cmd_address[31:15]==17'h10000)||(if_cmd_address[31:15]==0));
      wire rom_d_select=(USE_BOOT_ROM!=0) &&
        ((d_read_cmd_address[31:15]==17'h10000)||(d_read_cmd_address[31:15]==0));
      reg i_pending,d_pending,i_owner,d_owner;
      reg [2:0] i_response_word,d_response_word;
      // Remember the selected target until all eight native response words
      // have transferred. A changed next command must not redirect a response.
      assign if_cmd_ready=!i_pending && (rom_i_select?rom_i_ready:mem_if_cmd_ready);
      assign d_read_cmd_ready=!d_pending && (rom_d_select?rom_d_ready:mem_d_cmd_ready);
      assign if_rsp_valid=i_pending && (i_owner?rom_i_valid:mem_if_rsp_valid);
      assign if_rsp_data=i_owner?rom_i_data:mem_if_rsp_data;
      assign if_rsp_error=!i_owner && mem_if_rsp_error;
      assign d_read_rsp_valid=d_pending && (d_owner?rom_d_valid:mem_d_rsp_valid);
      assign d_read_rsp_data=d_owner?rom_d_data:mem_d_rsp_data;
      assign d_read_rsp_id=d_owner?rom_d_id:mem_d_rsp_id;
      assign d_read_rsp_error=!d_owner && mem_d_rsp_error;
      always @(posedge clk) begin
        if(reset) begin i_pending<=0;d_pending<=0;i_owner<=0;d_owner<=0;i_response_word<=0;d_response_word<=0;end
        else begin
          if(if_cmd_valid && if_cmd_ready) begin i_pending<=1;i_owner<=rom_i_select;i_response_word<=0;end
          if(d_read_cmd_valid && d_read_cmd_ready) begin d_pending<=1;d_owner<=rom_d_select;d_response_word<=0;end
          if(if_rsp_valid && if_rsp_ready) begin
            i_response_word<=i_response_word+1'b1;if(i_response_word==7)i_pending<=0;
          end
          if(d_read_rsp_valid && d_read_rsp_ready) begin
            d_response_word<=d_response_word+1'b1;if(d_response_word==7)d_pending<=0;
          end
        end
      end
      if(USE_BOOT_ROM!=0) begin : g_boot_rom
        cpu_boot_rom #(.INIT_FILE(BOOT_ROM_FILE)) boot (
          .clk(clk),.reset(reset),
          .i_cmd_valid(if_cmd_valid && !i_pending && rom_i_select),.i_cmd_ready(rom_i_ready),.i_cmd_address(if_cmd_address),
          .i_rsp_valid(rom_i_valid),.i_rsp_ready(if_rsp_ready && i_pending && i_owner),.i_rsp_data(rom_i_data),
          .d_cmd_valid(d_read_cmd_valid && !d_pending && rom_d_select),.d_cmd_ready(rom_d_ready),.d_cmd_address(d_read_cmd_address),
          .d_cmd_id(d_read_cmd_id),.d_rsp_valid(rom_d_valid),.d_rsp_ready(d_read_rsp_ready && d_pending && d_owner),
          .d_rsp_data(rom_d_data),.d_rsp_id(rom_d_id));
      end else begin : g_no_boot_rom
        assign rom_i_ready=0;assign rom_i_valid=0;assign rom_i_data=0;
        assign rom_d_ready=0;assign rom_d_valid=0;assign rom_d_data=0;assign rom_d_id=0;
      end

      pgl50h_cpu_axi_adapter #(
        .ADDR_WIDTH(32), .DATA_WIDTH(256), .ID_WIDTH(4), .CPU_MEM_BASE(32'h8000_0000)
      ) u_cpu_axi_adapter (
        .clk(clk), .reset(reset), .init_done(ddr_init_done),
        .if_cmd_valid(if_cmd_valid && !i_pending && !rom_i_select), .if_cmd_ready(mem_if_cmd_ready),
        .if_cmd_address(if_cmd_address), .if_rsp_valid(mem_if_rsp_valid),
        .if_rsp_ready(if_rsp_ready && i_pending && !i_owner), .if_rsp_data(mem_if_rsp_data), .if_rsp_error(mem_if_rsp_error),
        .d_read_cmd_valid(d_read_cmd_valid && !d_pending && !rom_d_select), .d_read_cmd_ready(mem_d_cmd_ready),
        .d_read_cmd_id(d_read_cmd_id), .d_read_cmd_address(d_read_cmd_address),
        .d_read_rsp_valid(mem_d_rsp_valid), .d_read_rsp_ready(d_read_rsp_ready && d_pending && !d_owner),
        .d_read_rsp_id(mem_d_rsp_id), .d_read_rsp_data(mem_d_rsp_data), .d_read_rsp_error(mem_d_rsp_error),
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


      wire legacy_cmd_ready,legacy_rsp_valid,legacy_rsp_error;
      wire [31:0] legacy_rsp_rdata,eth_rsp_rdata;
      wire eth_cmd_ready,eth_rsp_valid,eth_rsp_error;
      reg peripheral_busy,peripheral_eth,peripheral_ai;
      wire ai_select=((peripheral_cmd_address[31:16]==16'h1001) ||
                      (peripheral_cmd_address[31:16]==16'h4001)) && peripheral_cmd_address[15:12]==0;
      wire ai_cmd_ready,ai_rsp_valid,ai_rsp_error;
      wire [31:0] ai_rsp_rdata;
      wire ai_csr_valid,ai_csr_write,ai_csr_ready,ai_csr_error;
      wire [7:0] ai_csr_addr;
      wire [31:0] ai_csr_wdata,ai_csr_rdata;
      wire ai_busy_native;
      wire [7:0] ai_awlen_native,ai_arlen_native;
      wire [2:0] ai_awsize_native,ai_arsize_native;
      wire [1:0] ai_awburst_native,ai_arburst_native;
      wire ethernet_select=((peripheral_cmd_address[31:16]==16'h1002) ||
                            (peripheral_cmd_address[31:16]==16'h4002)) &&
                            peripheral_cmd_address[15:13]==0;
      wire legacy_cmd_valid=peripheral_cmd_valid && !peripheral_busy && !ethernet_select && !ai_select;
      assign peripheral_cmd_ready=!reset && !peripheral_busy && (ai_select?ai_cmd_ready:(ethernet_select?eth_cmd_ready:legacy_cmd_ready));
      assign peripheral_rsp_valid=peripheral_busy && (peripheral_ai?ai_rsp_valid:(peripheral_eth?eth_rsp_valid:legacy_rsp_valid));
      assign peripheral_rsp_data=peripheral_ai?ai_rsp_rdata:(peripheral_eth?eth_rsp_rdata:legacy_rsp_rdata);
      assign peripheral_rsp_error=peripheral_ai?ai_rsp_error:(peripheral_eth?eth_rsp_error:legacy_rsp_error);
      always @(posedge clk)begin
        if(reset)begin peripheral_busy<=0;peripheral_eth<=0;peripheral_ai<=0;end
        else begin
          if(peripheral_cmd_valid && peripheral_cmd_ready)begin peripheral_busy<=1;peripheral_eth<=ethernet_select;peripheral_ai<=ai_select;end
          if(peripheral_rsp_valid)peripheral_busy<=0;
        end
      end
      ethernet_cmd_axil u_ethernet_csr_bridge(
        .clk(clk),.reset(reset),.cmd_valid(peripheral_cmd_valid && !peripheral_busy && ethernet_select),
        .cmd_write(peripheral_cmd_write),.cmd_addr(peripheral_cmd_address[12:0]),
        .cmd_wdata(peripheral_cmd_data),.cmd_wstrb(peripheral_cmd_mask),.cmd_ready(eth_cmd_ready),
        .rsp_valid(eth_rsp_valid),.rsp_rdata(eth_rsp_rdata),.rsp_error(eth_rsp_error),
        .m_awaddr(eth_axil_awaddr),
        .m_awvalid(eth_axil_awvalid),
        .m_awready(eth_axil_awready),
        .m_wdata(eth_axil_wdata),
        .m_wstrb(eth_axil_wstrb),
        .m_wvalid(eth_axil_wvalid),
        .m_wready(eth_axil_wready),
        .m_bresp(eth_axil_bresp),
        .m_bvalid(eth_axil_bvalid),
        .m_bready(eth_axil_bready),
        .m_araddr(eth_axil_araddr),
        .m_arvalid(eth_axil_arvalid),
        .m_arready(eth_axil_arready),
        .m_rdata(eth_axil_rdata),
        .m_rresp(eth_axil_rresp),
        .m_rvalid(eth_axil_rvalid),
        .m_rready(eth_axil_rready));
      wire eth_dma_start,eth_dma_reset,eth_dma_sink_ready;
      wire [31:0] eth_dma_base,eth_dma_stride;
      wire [15:0] eth_dma_width,eth_dma_height;
      wire vision_replay_ready;
      wire [31:0] dma_status_for_csr=dma_status_value | {31'b0,(eth_job_owner || rx_busy)};
      wire cpu_dma_write=legacy_cmd_valid && legacy_cmd_ready && peripheral_cmd_write &&
          ((peripheral_cmd_address[31:16]==16'h1001) || (peripheral_cmd_address[31:16]==16'h4001)) &&
          peripheral_cmd_address[15:12]==4'h1;
      ethernet_soc_dma_link u_ethernet_dma_link(
        .clk(clk),.reset(reset),.network_ready(eth_network_ready),.cpu_start(dma_start || cpu_dma_write || rx_dma_claim),
        .job_valid(eth_job_valid),.job_abort(eth_job_abort),.job_base(eth_job_base),.job_stride(eth_job_stride),
        .job_width(eth_job_width),.job_height(eth_job_height),.job_ready(eth_job_ready),.owner(eth_job_owner),
        .job_done(eth_job_done),.job_error(eth_job_error),
        .image_start_valid(eth_image_start_valid),.image_start_ready(eth_image_start_ready),
        .image_done(eth_image_done),.image_error(eth_image_error),.image_abort(eth_image_abort),
        .dma_start(eth_dma_start),.dma_local_reset(eth_dma_reset),.dma_base(eth_dma_base),.dma_stride(eth_dma_stride),
        .dma_width(eth_dma_width),.dma_height(eth_dma_height),.dma_status(dma_status_value),
        .dma_done_irq(dma_done_irq),.dma_error_irq(dma_error_irq),
        .dma_tdata(vision_dma_m_tdata),.dma_tkeep(vision_dma_m_tkeep),.dma_tvalid(vision_dma_m_tvalid),
        .dma_tready(eth_dma_sink_ready),.dma_tlast(vision_dma_m_tlast),.dma_tuser(vision_dma_m_tuser),
        .image_tdata(eth_image_tdata),.image_tkeep(eth_image_tkeep),.image_tvalid(eth_image_tvalid),
        .image_tready(eth_image_tready),.image_tlast(eth_image_tlast),.image_tuser(eth_image_tuser),
        .dma_arvalid(m3_arvalid),.dma_arready(m3_arready),.dma_rvalid(m3_rvalid),.dma_rready(m3_rready),.dma_rlast(m3_rlast));
      assign vision_dma_m_tready=eth_job_owner?eth_dma_sink_ready:vision_replay_ready;

      pgl50h_csr_fabric u_csr_fabric (
        .clk(clk), .reset(reset),
        .cmd_valid(legacy_cmd_valid), .cmd_write(peripheral_cmd_write),
        .cmd_addr(peripheral_cmd_address), .cmd_wdata(peripheral_cmd_data),
        .cmd_wstrb(peripheral_cmd_mask), .cmd_ready(legacy_cmd_ready),
        .rsp_valid(legacy_rsp_valid), .rsp_rdata(legacy_rsp_rdata),
        .rsp_error(legacy_rsp_error), .keys(keys), .leds(leds),
        .timer_irq(timer_irq), .mtime_value(mtime), .ai_status(ai_status_value),
        .ai_start(ai_start), .ai_control(ai_control), .ai_src_addr(ai_src_addr),
        .ai_dst_addr(ai_dst_addr), .ai_length(ai_length), .ai_channels(ai_channels_cfg), .ai_scale(ai_scale_cfg),
        .dma_status(dma_status_for_csr), .dma_start(dma_start), .dma_control(dma_control),
        .dma_src_addr(dma_src_addr), .dma_dst_addr(dma_dst_addr), .dma_length(dma_length),
        .dma_stride(dma_stride), .dma_src_stride(dma_src_stride), .dma_dst_stride(dma_dst_stride),
        .dma_image_width(dma_image_width), .dma_image_height(dma_image_height),
        .dma_output_width(dma_output_width), .dma_output_height(dma_output_height),
        .qspi_status(flash_status), .qspi_rxdata(flash_rxdata),
        .qspi_control(flash_control), .qspi_txdata(flash_txdata), .irq_enable(irq_enable), .irq_clear(irq_clear),
        .irq_pending(irq_pending)
      );

      ai_native_csr_bridge u_ai_csr_bridge (
        .clk(clk),.reset(reset),.ddr_ready(ddr_init_done),
        .cmd_valid(peripheral_cmd_valid && !peripheral_busy && ai_select),
        .cmd_write(peripheral_cmd_write),.cmd_addr(peripheral_cmd_address[11:0]),
        .cmd_wdata(peripheral_cmd_data),.cmd_wstrb(peripheral_cmd_mask),.cmd_ready(ai_cmd_ready),
        .rsp_valid(ai_rsp_valid),.rsp_error(ai_rsp_error),.rsp_rdata(ai_rsp_rdata),
        .csr_valid(ai_csr_valid),.csr_write(ai_csr_write),.csr_addr(ai_csr_addr),.csr_wdata(ai_csr_wdata),
        .csr_ready(ai_csr_ready),.csr_error(ai_csr_error),.csr_rdata(ai_csr_rdata));
      assign ai_status_value={29'd0,1'b0,ai_done_irq,ai_busy_native};
      // Unified ABI: completion IRQ covers successful and failed descriptors.
      // Firmware reads error sticky at +0x84; the old separate error IRQ is reserved.
      assign ai_error_irq=1'b0;
      // The frozen executor only emits INCR/32-byte bursts of at most 16 beats.
      assign m2_awlen=ai_awlen_native[3:0];
      assign m2_arlen=ai_arlen_native[3:0];
      ai_accelerator_top u_ai_engine (
        .clk(clk),.rst_n(!reset),.csr_valid(ai_csr_valid),.csr_write(ai_csr_write),
        .csr_addr(ai_csr_addr),.csr_wdata(ai_csr_wdata),.csr_ready(ai_csr_ready),
        .csr_error(ai_csr_error),.csr_rdata(ai_csr_rdata),.irq(ai_done_irq),.busy(ai_busy_native),
        .m_awid(m2_awid),.m_awaddr(m2_awaddr),.m_awlen(ai_awlen_native),
        .m_awsize(ai_awsize_native),.m_awburst(ai_awburst_native),.m_awvalid(m2_awvalid),.m_awready(m2_awready),
        .m_wdata(m2_wdata),.m_wstrb(m2_wstrb),.m_wlast(m2_wlast),.m_wvalid(m2_wvalid),.m_wready(m2_wready),
        .m_bid(m2_bid),.m_bresp(m2_bresp),.m_bvalid(m2_bvalid),.m_bready(m2_bready),
        .m_arid(m2_arid),.m_araddr(m2_araddr),.m_arlen(ai_arlen_native),
        .m_arsize(ai_arsize_native),.m_arburst(ai_arburst_native),.m_arvalid(m2_arvalid),.m_arready(m2_arready),
        .m_rid(m2_rid),.m_rdata(m2_rdata),.m_rresp(m2_rresp),.m_rlast(m2_rlast),.m_rvalid(m2_rvalid),.m_rready(m2_rready)
      );

      // RX owns the existing DMA exclusively from ARM through all B responses.
      wire shared_dma_ingress_ready;
      assign rx_dma_grant=rx_busy || (rx_dma_claim && ddr_init_done && !eth_job_owner &&
          !dma_status_value[0] && !dma_start && !cpu_dma_write && !m3_awvalid && !m3_wvalid && !m3_arvalid);
      assign rx_dma_tready=rx_busy && shared_dma_ingress_ready;
      assign vision_dma_s_tready=!rx_busy && shared_dma_ingress_ready;
      assign rx_dma_status=dma_status_value;
      assign rx_dma_done=dma_done_irq;assign rx_dma_error=dma_error_irq;
      assign rx_dma_awvalid=m3_awvalid;assign rx_dma_awready=m3_awready;
      assign rx_dma_wvalid=m3_wvalid;assign rx_dma_bvalid=m3_bvalid;assign rx_dma_bready=m3_bready;
      pgl50h_camera_dma u_camera_dma (
        .clk(clk), .reset(reset || eth_dma_reset), .start((rx_busy?rx_dma_start:(eth_job_owner?eth_dma_start:dma_start)) && ddr_init_done), .control(rx_busy?32'h4:(eth_job_owner?32'h2:dma_control)),
        .src_addr(eth_job_owner?eth_dma_base:dma_src_addr), .dst_addr(rx_busy?rx_dma_base:dma_dst_addr), .length(dma_length), .stride(eth_job_owner?32'b0:dma_stride),
        .src_stride(eth_job_owner?eth_dma_stride:dma_src_stride), .dst_stride(rx_busy?rx_dma_stride:dma_dst_stride),
        .image_width(eth_job_owner?{16'b0,eth_dma_width}:dma_image_width), .image_height(eth_job_owner?{16'b0,eth_dma_height}:dma_image_height),
        .output_width(rx_busy?{16'd0,rx_dma_width}:dma_output_width), .output_height(rx_busy?{16'd0,rx_dma_height}:dma_output_height),
        .status(dma_status_value), .done_irq(dma_done_irq), .error_irq(dma_error_irq),
        .pixel_valid(1'b0), .pixel_ready(pixel_ready_unused), .pixel_data(32'h0), .pixel_sof(1'b0), .pixel_eol(1'b0),
        .m_axis_tdata(vision_dma_m_tdata), .m_axis_tkeep(vision_dma_m_tkeep),
        .m_axis_tvalid(vision_dma_m_tvalid), .m_axis_tready(vision_dma_m_tready),
        .m_axis_tlast(vision_dma_m_tlast), .m_axis_tuser(vision_dma_m_tuser),
        .s_axis_tdata(rx_busy?rx_dma_tdata:vision_dma_s_tdata), .s_axis_tkeep(rx_busy?rx_dma_tkeep:vision_dma_s_tkeep),
        .s_axis_tvalid(rx_busy?rx_dma_tvalid:vision_dma_s_tvalid), .s_axis_tready(shared_dma_ingress_ready),
        .s_axis_tlast(rx_busy?rx_dma_tlast:vision_dma_s_tlast), .s_axis_tuser(rx_busy?rx_dma_tuser:vision_dma_s_tuser),
        .m_awid(m3_awid), .m_awaddr(m3_awaddr), .m_awlen(m3_awlen), .m_awvalid(m3_awvalid), .m_awready(m3_awready),
        .m_wdata(m3_wdata), .m_wstrb(m3_wstrb), .m_wlast(m3_wlast), .m_wvalid(m3_wvalid), .m_wready(m3_wready),
        .m_bid(m3_bid), .m_bresp(m3_bresp), .m_bvalid(m3_bvalid), .m_bready(m3_bready),
        .m_arid(m3_arid), .m_araddr(m3_araddr), .m_arlen(m3_arlen), .m_arvalid(m3_arvalid), .m_arready(m3_arready),
        .m_rid(m3_rid), .m_rdata(m3_rdata), .m_rresp(m3_rresp), .m_rlast(m3_rlast), .m_rvalid(m3_rvalid), .m_rready(m3_rready)
      );

      camera_rx_subsystem #(.DATA_WIDTH(8), .FIFO_DEPTH(2048),
                            .WORD_COMPAT_TKEEP(1)) u_camera_rx_subsystem (
        .cam_pclk(cam_pclk), .cam_reset(reset), .cam_enable(dma_control[5]),
        .cam_vsync(cam_vsync), .cam_href(cam_href), .cam_data(cam_data),
        .soc_clk(clk), .soc_reset(reset),
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
        .clk(clk), .reset(reset), .input_sel_req(dma_control[5]),
        .switch_request(1'b1), .frame_height(dma_image_height),
        .camera_tdata(camera_m_tdata), .camera_tkeep(camera_m_tkeep),
        .camera_tvalid(camera_m_tvalid), .camera_tready(camera_m_tready),
        .camera_tuser(camera_m_tuser), .camera_tlast(camera_m_tlast),
        .replay_tdata(vision_dma_m_tdata), .replay_tkeep(vision_dma_m_tkeep),
        .replay_tvalid(vision_dma_m_tvalid && !eth_job_owner), .replay_tready(vision_replay_ready),
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
        .clk(clk), .reset(reset), .format_rgb565(dma_control[3]),
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
        .AXI_DATA_WIDTH(256), .ID_WIDTH(4), .CPU_MEM_BASE(32'h8000_0000), .HMIC_ADDR_SHIFT(2)
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
      assign rx_dma_grant=1'b0;
      assign rx_dma_status=1'b0;
      assign rx_dma_done=1'b0;
      assign rx_dma_error=1'b0;
      assign rx_dma_awvalid=1'b0;
      assign rx_dma_awready=1'b0;
      assign rx_dma_wvalid=1'b0;
      assign rx_dma_bvalid=1'b0;
      assign rx_dma_bready=1'b0;
      assign rx_dma_tready=1'b0;

      assign eth_axil_awaddr=13'b0;
      assign eth_axil_awvalid=1'b0;
      assign eth_axil_wdata=32'b0;
      assign eth_axil_wstrb=4'b0;
      assign eth_axil_wvalid=1'b0;
      assign eth_axil_bready=1'b0;
      assign eth_axil_araddr=13'b0;
      assign eth_axil_arvalid=1'b0;
      assign eth_axil_rready=1'b0;
      assign eth_job_ready=1'b0;
      assign eth_job_owner=1'b0;
      assign eth_job_done=1'b0;
      assign eth_job_error=1'b0;
      assign eth_image_start_valid=1'b0;
      assign eth_image_abort=1'b0;
      assign eth_image_tdata=32'b0;
      assign eth_image_tkeep=4'b0;
      assign eth_image_tvalid=1'b0;
      assign eth_image_tlast=1'b0;
      assign eth_image_tuser=1'b0;
      assign axi_fabric_irq = 1'b0;

      if (USE_DDR_AXI != 0) begin : g_ddr_axi
        pgl50h_native_axi_bridge #(
          .AXI_ADDR_WIDTH(HMIC_ADDR_WIDTH), .AXI_DATA_WIDTH(HMIC_DATA_WIDTH),
          .CPU_MEM_BASE(32'h8000_0000), .HMIC_ADDR_SHIFT(2)
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
