`timescale 1ns/1ps

module pgl50h_soc_tb;
  reg clk_50m;
  reg reset_ext_n;
  reg ddr_init_done;
  wire clk_sys;
  wire pll_locked;
  wire soc_reset;
  wire soc_reset_n;

  reg         p_cmd_valid;
  reg         p_cmd_write;
  reg  [31:0] p_cmd_addr;
  reg  [31:0] p_cmd_wdata;
  reg   [3:0] p_cmd_wstrb;
  wire        p_cmd_ready;
  wire        p_rsp_valid;
  wire [31:0] p_rsp_rdata;
  wire        p_rsp_error;
  reg   [7:0] keys;
  wire  [7:0] leds;
  wire        timer_irq;
  wire [63:0] mtime;
  wire        ai_start;
  wire [31:0] ai_control;
  wire [31:0] ai_src_addr;
  wire [31:0] ai_dst_addr;
  wire [31:0] ai_length;
  wire [31:0] ai_status_value;

  pgl50h_clock_reset dut_clock_reset (
    .clk_50m(clk_50m),
    .reset_ext_n(reset_ext_n),
    .ddr_init_done(ddr_init_done),
    .clk_sys_ext(clk_50m),
    .ext_pll_locked(1'b1),
    .use_external_clk(1'b0),
    .clk_sys(clk_sys),
    .pll_locked(pll_locked),
    .soc_reset(soc_reset),
    .soc_reset_n(soc_reset_n)
  );

  pgl50h_peripherals dut_peripherals (
    .clk(clk_sys),
    .reset(soc_reset),
    .cmd_valid(p_cmd_valid),
    .cmd_write(p_cmd_write),
    .cmd_addr(p_cmd_addr),
    .cmd_wdata(p_cmd_wdata),
    .cmd_wstrb(p_cmd_wstrb),
    .cmd_ready(p_cmd_ready),
    .rsp_valid(p_rsp_valid),
    .rsp_rdata(p_rsp_rdata),
    .rsp_error(p_rsp_error),
    .keys(keys),
    .leds(leds),
    .timer_irq(timer_irq),
    .mtime_value(mtime),
    .ai_start(ai_start),
    .ai_control(ai_control),
    .ai_src_addr(ai_src_addr),
    .ai_dst_addr(ai_dst_addr),
    .ai_length(ai_length),
    .ai_status_value(ai_status_value)
  );

  pgl50h_ai_accel_stub dut_ai (
    .clk(clk_sys),
    .reset(soc_reset),
    .start(ai_start),
    .control(ai_control),
    .src_addr(ai_src_addr),
    .dst_addr(ai_dst_addr),
    .length(ai_length),
    .status(ai_status_value)
  );

  always #10 clk_50m = ~clk_50m;

  task automatic peripheral_write(input [31:0] address, input [31:0] data);
    begin
      @(posedge clk_sys);
      while (!p_cmd_ready) @(posedge clk_sys);
      p_cmd_valid <= 1'b1;
      p_cmd_write <= 1'b1;
      p_cmd_addr <= address;
      p_cmd_wdata <= data;
      p_cmd_wstrb <= 4'hf;
      @(posedge clk_sys);
      p_cmd_valid <= 1'b0;
      p_cmd_write <= 1'b0;
      p_cmd_wstrb <= 4'h0;
      while (!p_rsp_valid) @(posedge clk_sys);
    end
  endtask

  task automatic peripheral_read(input [31:0] address, output [31:0] data);
    begin
      @(posedge clk_sys);
      while (!p_cmd_ready) @(posedge clk_sys);
      p_cmd_valid <= 1'b1;
      p_cmd_write <= 1'b0;
      p_cmd_addr <= address;
      p_cmd_wdata <= 32'h0;
      p_cmd_wstrb <= 4'h0;
      @(posedge clk_sys);
      p_cmd_valid <= 1'b0;
      while (!p_rsp_valid) @(posedge clk_sys);
      data = p_rsp_rdata;
    end
  endtask

  reg [31:0] read_data;
  initial begin
    clk_50m = 1'b0;
    reset_ext_n = 1'b0;
    ddr_init_done = 1'b0;
    p_cmd_valid = 1'b0;
    p_cmd_write = 1'b0;
    p_cmd_addr = 32'h0;
    p_cmd_wdata = 32'h0;
    p_cmd_wstrb = 4'h0;
    keys = 8'h5a;

    repeat (3) @(posedge clk_sys);
    if (!soc_reset || soc_reset_n) $fatal(1, "reset must be asserted before DDR init");

    reset_ext_n = 1'b1;
    repeat (2) @(posedge clk_sys);
    if (!soc_reset) $fatal(1, "reset released before DDR init");

    ddr_init_done = 1'b1;
    repeat (3) @(posedge clk_sys);
    if (soc_reset || !soc_reset_n || !pll_locked) $fatal(1, "reset did not release after DDR init");

    peripheral_write(32'h4000_0000, 32'h0000_00a5);
    if (leds !== 8'ha5) $fatal(1, "LED write/readback failed: %h", leds);

    peripheral_read(32'h4000_0004, read_data);
    if (read_data !== 32'h0000_005a) $fatal(1, "key read failed: %h", read_data);

    peripheral_write(32'h4001_0000, 32'h0000_0001);
    repeat (2) @(posedge clk_sys);
    peripheral_read(32'h4001_0004, read_data);
    if (!read_data[0]) $fatal(1, "AI accelerator did not enter busy state: %h", read_data);
    repeat (20) @(posedge clk_sys);
    peripheral_read(32'h4001_0004, read_data);
    if (read_data[0] || !read_data[1]) $fatal(1, "AI accelerator did not complete: %h", read_data);

    $display("PGL50H SoC clock/peripheral smoke test PASS");
    $finish;
  end
endmodule
