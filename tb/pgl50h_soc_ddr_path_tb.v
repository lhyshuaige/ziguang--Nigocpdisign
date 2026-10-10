`timescale 1ns/1ps

// SoC-level behavioral DDR path test.
//
// The real NaxRiscvContest starts at 0x8000_0000.  The small program below
// loads a word from 0x8000_0040 through the data cache and stores it to the
// GPIO LED register at the generated core's 0x1000_0000 IO window.  The HMIC model is intentionally attached
// to the generated user-port contract, so this test covers CPU fetch, D-cache
// line refill, native-bus arbitration, address conversion and peripheral I/O.
module pgl50h_soc_ddr_path_tb #(
  parameter integer USE_AXI_FABRIC = 0
);
  localparam integer AW = 28;
  localparam integer DW = 256;

  reg clk;
  reg reset;
  reg ddr_init_done;
  reg [7:0] keys;
  wire [7:0] leds;
  wire timer_irq;
  wire [63:0] mtime;
  wire ai_start;
  wire [31:0] ai_control;
  wire [31:0] ai_src_addr;
  wire [31:0] ai_dst_addr;
  wire [31:0] ai_length;

  wire [AW-1:0] axi_awaddr;
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
  wire [AW-1:0] axi_araddr;
  wire           axi_aruser_ap;
  wire [3:0]     axi_aruser_id;
  wire [3:0]     axi_arlen;
  wire           axi_arready;
  wire           axi_arvalid;
  reg  [DW-1:0]  axi_rdata;
  reg  [3:0]     axi_rid;
  reg            axi_rlast;
  reg            axi_rvalid;

  reg [DW-1:0] mem [0:255];
  reg [AW-1:0] pending_raddr;
  reg          pending_rvalid;
  integer i;
  integer j;
  integer cycles;
  integer ar_count;
  integer found_data_refill;
  reg [AW-1:0] ar_log [0:31];
  integer sim_cycle;
  integer ar_cycle_log [0:31];
  integer cpu_error_count;

  // RV64I instructions, encoded little-endian in the HMIC 256-bit beats:
  //   lui  x2, 0x80000       ; x2 = 0x8000_0000
  //   lw   x3, 64(x2)        ; D-cache line refill at 0x8000_0040
  //   lui  x4, 0x10000       ; x4 = generated core's IO base
  //   sw   x3, 0(x4)         ; LED gets the loaded value
  //   jal  x0, 0             ; stop in a tight loop
  localparam [31:0] INS_LUI_MEM = 32'h8000_0137;
  localparam [31:0] INS_LW_DATA  = 32'h0401_2183;
   localparam [31:0] INS_LUI_GPIO = 32'h1000_0237;
  localparam [31:0] INS_SW_GPIO  = 32'h0032_2023;
  localparam [31:0] INS_LOOP     = 32'h0000_006f;

  assign axi_awready = 1'b1;
  assign axi_wready  = 1'b1;
  assign axi_arready = !pending_rvalid;
  assign axi_wusero_id = axi_awuser_id;
  assign axi_wusero_last = 1'b1;

  always #5 clk = ~clk;

  pgl50h_soc_core #(
    .USE_DDR_AXI(1),
    .USE_AXI_FABRIC(USE_AXI_FABRIC),
    .HMIC_ADDR_WIDTH(AW),
    .HMIC_DATA_WIDTH(DW)
  ) dut (
    .clk(clk),
    .reset(reset),
    .ddr_init_done(ddr_init_done),
    .keys(keys),
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

  always @(posedge clk) begin
    sim_cycle = sim_cycle + 1;
    if (dut.if_rsp_error || dut.d_read_rsp_error || dut.d_write_rsp_error) begin
      cpu_error_count = cpu_error_count + 1;
      $display("CPU memory response error at cycle=%0d if=%b dr=%b dw=%b", sim_cycle,
               dut.if_rsp_error, dut.d_read_rsp_error, dut.d_write_rsp_error);
    end
    if (dut.peripheral_cmd_valid)
      $display("CPU peripheral cmd write=%b addr=%h data=%h", dut.peripheral_cmd_write, dut.peripheral_cmd_address, dut.peripheral_cmd_data);
    axi_rvalid <= 1'b0;

    if (axi_arvalid && axi_arready) begin
      $display("HMIC AR[%0d] addr=%h cycle=%0d", ar_count, axi_araddr, sim_cycle);
      if (ar_count < 32)
        ar_log[ar_count] <= axi_araddr;
      if (ar_count < 32)
        ar_cycle_log[ar_count] = sim_cycle;
      ar_count = ar_count + 1;
      pending_raddr <= axi_araddr;
      pending_rvalid <= 1'b1;
    end

    if (pending_rvalid) begin
      axi_rdata <= mem[pending_raddr[7:0]];
      $display("HMIC R addr=%h data=%h", pending_raddr, mem[pending_raddr[7:0]]);
      axi_rid <= 4'h0;
      axi_rlast <= 1'b1;
      axi_rvalid <= 1'b1;
      pending_rvalid <= 1'b0;
    end

    // The HMIC user port has no WVALID: AW acceptance and WREADY together
    // complete the fixed single-beat write.
    if (axi_awvalid && axi_awready && axi_wready) begin
      $display("HMIC AW addr=%h data=%h strb=%h", axi_awaddr, axi_wdata, axi_wstrb);
      for (j = 0; j < DW/8; j = j + 1)
        if (axi_wstrb[j])
          mem[axi_awaddr[7:0]][j*8 +: 8] <= axi_wdata[j*8 +: 8];
    end
  end

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    ddr_init_done = 1'b0;
    keys = 8'h00;
    pending_rvalid = 1'b0;
    axi_rvalid = 1'b0;
    axi_rdata = {DW{1'b0}};
    axi_rid = 4'h0;
    // The HMIC model is single-beat (ARLEN=0), so RLAST is a stable metadata
    // value even before the first response.  Keeping it asserted avoids a
    // same-edge NBA race with the adapter's response sampler.
    axi_rlast = 1'b1;
    ar_count = 0;
    sim_cycle = 0;
    cpu_error_count = 0;
    for (i = 0; i < 256; i = i + 1)
      mem[i] = {DW{1'b0}};

    // First 64-byte instruction line at HMIC addresses 0 and 4.
    mem[0][31:0]   = INS_LUI_MEM;
    mem[0][63:32]  = INS_LW_DATA;
    mem[0][95:64]  = INS_LUI_GPIO;
    mem[0][127:96] = INS_SW_GPIO;
    mem[0][159:128] = INS_LOOP;

    // 0x8000_0040 maps to HMIC command address 8, lane 0.
    mem[8][31:0] = 32'h0000_005a;

    repeat (4) @(posedge clk);
    ddr_init_done = 1'b1;
    repeat (4) @(posedge clk);
    reset = 1'b0;

    cycles = 0;
    while (leds !== 8'h5a && cycles < 20000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    if (leds !== 8'h5a)
      $fatal(1, "CPU-to-DDR path did not reach GPIO write: leds=%h cycles=%0d ARs=%0d sequence=%h %h %h %h %h %h %h %h", leds, cycles, ar_count, ar_log[0], ar_log[1], ar_log[2], ar_log[3], ar_log[4], ar_log[5], ar_log[6], ar_log[7]);
    if (ar_count < 4)
      $fatal(1, "expected instruction and data line refills, saw only %0d HMIC reads", ar_count);
    if (cpu_error_count != 0)
      $fatal(1, "CPU observed %0d memory response errors", cpu_error_count);
    if (ar_log[0] !== 28'h0 || ar_log[1] !== 28'h4)
      $fatal(1, "instruction line did not start at HMIC 0/4: %h %h", ar_log[0], ar_log[1]);
    found_data_refill = 0;
    for (j = 0; j < ar_count - 1; j = j + 1)
      if ((ar_log[j] === 28'h8) && (ar_log[j+1] === 28'hc))
        found_data_refill = 1;
    if (!found_data_refill)
      $fatal(1, "no 0x8000_0040 D-cache line refill observed in HMIC log (reads=%0d)", ar_count);

    $display("PGL50H CPU-to-DDR SoC path PASS (cycles=%0d, HMIC reads=%0d)", cycles, ar_count);
    $finish;
  end
endmodule
