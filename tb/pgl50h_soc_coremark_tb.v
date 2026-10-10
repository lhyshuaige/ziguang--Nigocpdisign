`timescale 1ns/1ps

// Full SoC CoreMark harness.
//
// The CPU is instantiated through pgl50h_soc_core with USE_AXI_FABRIC=1.
// The PDS HMIC user port is replaced only at this simulation boundary by a
// cycle-accurate 32-bit-word backing store: AXI/HMIC still sees the same
// 256-bit reads and writes as the board design, while the DDR3 PHY is not
// required on a host without the vendor memory model.
module pgl50h_soc_coremark_tb (
  input  wire       clk,
  input  wire       reset,
  input  wire       ddr_init_done,
  output wire [7:0] leds,
  output reg        putc_valid,
  output reg  [7:0] putc_data,
  output reg [31:0] cycle_count,
  output reg [31:0] hmic_read_count,
  output reg [31:0] hmic_write_count
);
  localparam integer AW = 28;
  localparam integer DW = 256;
  localparam integer RAM_WORDS = 65536; // 256 KiB / 32-bit word

  wire        timer_irq;
  wire [63:0] mtime;
  wire        ai_start;
  wire [31:0] ai_control;
  wire [31:0] ai_src_addr;
  wire [31:0] ai_dst_addr;
  wire [31:0] ai_length;

  wire [AW-1:0]  axi_awaddr;
  wire           axi_awuser_ap;
  wire [3:0]     axi_awuser_id;
  wire [3:0]     axi_awlen;
  wire           axi_awready;
  wire           axi_awvalid;
  wire [DW-1:0]  axi_wdata;
  wire [DW/8-1:0] axi_wstrb;
  wire           axi_wready;
  wire [3:0]     axi_wusero_id;
  wire           axi_wusero_last;
  wire [AW-1:0]  axi_araddr;
  wire           axi_aruser_ap;
  wire [3:0]     axi_aruser_id;
  wire [3:0]     axi_arlen;
  wire           axi_arready;
  wire           axi_arvalid;
  reg  [DW-1:0]  axi_rdata;
  reg  [3:0]     axi_rid;
  reg            axi_rlast;
  reg            axi_rvalid;

  reg [31:0] memory [0:RAM_WORDS-1];
  integer init_index;
  integer read_base;
  integer read_index;
  integer write_base;
  integer write_index;
  integer byte_index;

  pgl50h_soc_core #(
    .USE_DDR_AXI(0),
    .USE_AXI_FABRIC(1),
    .HMIC_ADDR_WIDTH(AW),
    .HMIC_DATA_WIDTH(DW)
  ) dut (
    .clk(clk),
    .reset(reset),
    .ddr_init_done(ddr_init_done),
    .ddr_clk(clk),
    .keys(8'h00),
    .leds(leds),
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

  // HMIC's fixed contract has no independent WVALID/B or RREADY signals.
  // The adapter therefore completes a write when AW and W are both accepted,
  // and samples a held read response on the following clock.
  assign axi_awready     = 1'b1;
  assign axi_wready      = 1'b1;
  assign axi_wusero_id   = axi_awuser_id;
  assign axi_wusero_last = 1'b1;
  assign axi_arready     = !axi_rvalid;

  initial begin
    for (init_index = 0; init_index < RAM_WORDS; init_index = init_index + 1)
      memory[init_index] = 32'h0000_0000;
    $readmemh("coremark.memh", memory);
  end

  always @(posedge clk) begin
    if (reset) begin
      axi_rdata       <= {DW{1'b0}};
      axi_rid         <= 4'h0;
      axi_rlast       <= 1'b1;
      axi_rvalid      <= 1'b0;
      cycle_count     <= 32'h0;
      hmic_read_count <= 32'h0;
      hmic_write_count <= 32'h0;
      putc_valid      <= 1'b0;
      putc_data       <= 8'h00;
    end else begin
      cycle_count <= cycle_count + 32'd1;
      putc_valid  <= 1'b0;
      axi_rvalid  <= 1'b0;

      if (axi_arvalid && axi_arready) begin
        // HMIC addresses are 64-bit-word addresses.  One 256-bit beat
        // therefore starts at two 32-bit words per HMIC address unit.
        read_base = axi_araddr * 2;
        for (read_index = 0; read_index < 8; read_index = read_index + 1) begin
          if ((read_base + read_index) < RAM_WORDS)
            axi_rdata[read_index*32 +: 32] <= memory[read_base + read_index];
          else
            axi_rdata[read_index*32 +: 32] <= 32'h0000_0000;
        end
        axi_rid         <= axi_aruser_id;
        axi_rlast       <= 1'b1;
        axi_rvalid      <= 1'b1;
        hmic_read_count <= hmic_read_count + 32'd1;
      end

      if (axi_awvalid && axi_awready && axi_wready) begin
        write_base = axi_awaddr * 2;
        for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1) begin
          write_index = write_base + (byte_index >> 2);
          if (axi_wstrb[byte_index] && (write_index < RAM_WORDS))
            memory[write_index][(byte_index & 3)*8 +: 8] <= axi_wdata[byte_index*8 +: 8];
        end
        hmic_write_count <= hmic_write_count + 32'd1;
      end

      // Observe the software console at the SoC CSR boundary.  0x10000000
      // is also the architectural GPIO/LED write register, so no extra UART
      // device is inserted into the datapath for this benchmark.
      if (dut.peripheral_cmd_valid && dut.peripheral_cmd_ready &&
          dut.peripheral_cmd_write &&
          (dut.peripheral_cmd_address == 32'h1000_0000)) begin
        putc_valid <= 1'b1;
        putc_data  <= dut.peripheral_cmd_data[7:0];
      end
    end
  end
endmodule
