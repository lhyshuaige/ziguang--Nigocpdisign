`timescale 1ns/1ps

module pgl50h_mem_fabric_tb;
  reg clk;
  reg reset;
  reg if_cmd_valid;
  reg [31:0] if_cmd_address;
  wire if_cmd_ready;
  wire if_rsp_valid;
  wire [63:0] if_rsp_data;
  reg if_rsp_ready;
  reg d_read_cmd_valid;
  reg [0:0] d_read_cmd_id;
  reg [31:0] d_read_cmd_address;
  wire d_read_cmd_ready;
  wire d_read_rsp_valid;
  wire [0:0] d_read_rsp_id;
  wire [63:0] d_read_rsp_data;
  reg d_read_rsp_ready;
  reg d_write_cmd_valid;
  reg d_write_cmd_last;
  reg [31:0] d_write_cmd_address;
  reg [63:0] d_write_cmd_data;
  reg [0:0] d_write_cmd_id;
  wire d_write_cmd_ready;
  wire d_write_rsp_valid;
  wire [0:0] d_write_rsp_id;
  reg d_write_rsp_ready;

  pgl50h_mem_fabric dut (
    .clk(clk), .reset(reset),
    .if_cmd_valid(if_cmd_valid), .if_cmd_ready(if_cmd_ready),
    .if_cmd_address(if_cmd_address), .if_rsp_valid(if_rsp_valid),
    .if_rsp_ready(if_rsp_ready), .if_rsp_data(if_rsp_data), .if_rsp_error(),
    .d_read_cmd_valid(d_read_cmd_valid), .d_read_cmd_ready(d_read_cmd_ready),
    .d_read_cmd_id(d_read_cmd_id), .d_read_cmd_address(d_read_cmd_address),
    .d_read_rsp_valid(d_read_rsp_valid), .d_read_rsp_ready(d_read_rsp_ready),
    .d_read_rsp_id(d_read_rsp_id), .d_read_rsp_data(d_read_rsp_data), .d_read_rsp_error(),
    .d_write_cmd_valid(d_write_cmd_valid), .d_write_cmd_ready(d_write_cmd_ready),
    .d_write_cmd_last(d_write_cmd_last), .d_write_cmd_address(d_write_cmd_address),
    .d_write_cmd_data(d_write_cmd_data), .d_write_cmd_id(d_write_cmd_id),
    .d_write_rsp_valid(d_write_rsp_valid), .d_write_rsp_ready(d_write_rsp_ready),
    .d_write_rsp_id(d_write_rsp_id), .d_write_rsp_error()
  );

  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    if_cmd_valid = 1'b0;
    if_cmd_address = 32'h0;
    if_rsp_ready = 1'b1;
    d_read_cmd_valid = 1'b0;
    d_read_cmd_id = 1'b0;
    d_read_cmd_address = 32'h0;
    d_read_rsp_ready = 1'b1;
    d_write_cmd_valid = 1'b0;
    d_write_cmd_last = 1'b1;
    d_write_cmd_address = 32'h0;
    d_write_cmd_data = 64'h0;
    d_write_cmd_id = 1'b0;
    d_write_rsp_ready = 1'b1;

    repeat (2) @(posedge clk);
    reset = 1'b0;

    @(posedge clk);
    if_cmd_valid <= 1'b1;
    if_cmd_address <= 32'h8000_0000;
    @(posedge clk);
    if_cmd_valid <= 1'b0;
    while (!if_rsp_valid) @(posedge clk);
    if (if_rsp_data !== 64'h0) $fatal(1, "unexpected reset memory contents");

    @(posedge clk);
    d_write_cmd_valid <= 1'b1;
    d_write_cmd_address <= 32'h8000_0008;
    d_write_cmd_data <= 64'h1122_3344_5566_7788;
    @(posedge clk);
    d_write_cmd_valid <= 1'b0;
    while (!d_write_rsp_valid) @(posedge clk);

    @(posedge clk);
    d_read_cmd_valid <= 1'b1;
    d_read_cmd_address <= 32'h8000_0008;
    @(posedge clk);
    d_read_cmd_valid <= 1'b0;
    while (!d_read_rsp_valid) @(posedge clk);
    if (d_read_rsp_data !== 64'h1122_3344_5566_7788)
      $fatal(1, "fallback memory readback failed: %h", d_read_rsp_data);

    $display("PGL50H memory fabric smoke test PASS");
    $finish;
  end
endmodule
