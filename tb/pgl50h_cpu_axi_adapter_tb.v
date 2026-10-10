`timescale 1ns/1ps

// Red/green contract test for the CPU native-bus -> internal AXI4 adapter.
// The testbench intentionally instantiates pgl50h_cpu_axi_adapter before the
// implementation exists so the first compile is expected to fail.
module pgl50h_cpu_axi_adapter_tb;
  localparam integer DW = 256;
  localparam integer SW = DW / 8;

  reg clk;
  reg reset;
  reg init_done;

  reg        if_cmd_valid;
  wire       if_cmd_ready;
  reg [31:0] if_cmd_address;
  wire       if_rsp_valid;
  reg        if_rsp_ready;
  wire [63:0] if_rsp_data;
  wire       if_rsp_error;

  reg        d_read_cmd_valid;
  wire       d_read_cmd_ready;
  reg [0:0]  d_read_cmd_id;
  reg [31:0] d_read_cmd_address;
  wire       d_read_rsp_valid;
  reg        d_read_rsp_ready;
  wire [0:0] d_read_rsp_id;
  wire [63:0] d_read_rsp_data;
  wire       d_read_rsp_error;

  reg        d_write_cmd_valid;
  wire       d_write_cmd_ready;
  reg        d_write_cmd_last;
  reg [31:0] d_write_cmd_address;
  reg [63:0] d_write_cmd_data;
  reg [0:0]  d_write_cmd_id;
  wire       d_write_rsp_valid;
  wire [0:0] d_write_rsp_id;
  wire       d_write_rsp_error;

  wire [3:0] if_axi_arid;
  wire [31:0] if_axi_araddr;
  wire [3:0] if_axi_arlen;
  wire if_axi_arvalid;
  reg  if_axi_arready;
  reg [3:0] if_axi_rid;
  reg [DW-1:0] if_axi_rdata;
  reg [1:0] if_axi_rresp;
  reg if_axi_rlast;
  reg if_axi_rvalid;
  wire if_axi_rready;

  wire [3:0] d_axi_arid;
  wire [31:0] d_axi_araddr;
  wire [3:0] d_axi_arlen;
  wire d_axi_arvalid;
  reg  d_axi_arready;
  reg [3:0] d_axi_rid;
  reg [DW-1:0] d_axi_rdata;
  reg [1:0] d_axi_rresp;
  reg d_axi_rlast;
  reg d_axi_rvalid;
  wire d_axi_rready;

  wire [3:0] d_axi_awid;
  wire [31:0] d_axi_awaddr;
  wire [3:0] d_axi_awlen;
  wire d_axi_awvalid;
  reg  d_axi_awready;
  wire [DW-1:0] d_axi_wdata;
  wire [SW-1:0] d_axi_wstrb;
  wire d_axi_wlast;
  wire d_axi_wvalid;
  reg  d_axi_wready;
  reg [3:0] d_axi_bid;
  reg [1:0] d_axi_bresp;
  reg d_axi_bvalid;
  wire d_axi_bready;

  integer if_words;
  integer d_words;
  integer ar_seen;
  reg [DW-1:0] beat0;
  reg [DW-1:0] beat1;

  always #5 clk = ~clk;

  pgl50h_cpu_axi_adapter dut (
    .clk(clk), .reset(reset), .init_done(init_done),
    .if_cmd_valid(if_cmd_valid), .if_cmd_ready(if_cmd_ready),
    .if_cmd_address(if_cmd_address), .if_rsp_valid(if_rsp_valid),
    .if_rsp_ready(if_rsp_ready), .if_rsp_data(if_rsp_data),
    .if_rsp_error(if_rsp_error),
    .d_read_cmd_valid(d_read_cmd_valid), .d_read_cmd_ready(d_read_cmd_ready),
    .d_read_cmd_id(d_read_cmd_id), .d_read_cmd_address(d_read_cmd_address),
    .d_read_rsp_valid(d_read_rsp_valid), .d_read_rsp_ready(d_read_rsp_ready),
    .d_read_rsp_id(d_read_rsp_id), .d_read_rsp_data(d_read_rsp_data),
    .d_read_rsp_error(d_read_rsp_error),
    .d_write_cmd_valid(d_write_cmd_valid), .d_write_cmd_ready(d_write_cmd_ready),
    .d_write_cmd_last(d_write_cmd_last), .d_write_cmd_address(d_write_cmd_address),
    .d_write_cmd_data(d_write_cmd_data), .d_write_cmd_id(d_write_cmd_id),
    .d_write_rsp_valid(d_write_rsp_valid), .d_write_rsp_id(d_write_rsp_id),
    .d_write_rsp_error(d_write_rsp_error),
    .if_axi_arid(if_axi_arid), .if_axi_araddr(if_axi_araddr),
    .if_axi_arlen(if_axi_arlen), .if_axi_arvalid(if_axi_arvalid),
    .if_axi_arready(if_axi_arready), .if_axi_rid(if_axi_rid),
    .if_axi_rdata(if_axi_rdata), .if_axi_rlast(if_axi_rlast),
    .if_axi_rresp(if_axi_rresp),
    .if_axi_rvalid(if_axi_rvalid), .if_axi_rready(if_axi_rready),
    .d_axi_arid(d_axi_arid), .d_axi_araddr(d_axi_araddr),
    .d_axi_arlen(d_axi_arlen), .d_axi_arvalid(d_axi_arvalid),
    .d_axi_arready(d_axi_arready), .d_axi_rid(d_axi_rid),
    .d_axi_rdata(d_axi_rdata), .d_axi_rlast(d_axi_rlast),
    .d_axi_rresp(d_axi_rresp),
    .d_axi_rvalid(d_axi_rvalid), .d_axi_rready(d_axi_rready),
    .d_axi_awid(d_axi_awid), .d_axi_awaddr(d_axi_awaddr),
    .d_axi_awlen(d_axi_awlen), .d_axi_awvalid(d_axi_awvalid),
    .d_axi_awready(d_axi_awready), .d_axi_wdata(d_axi_wdata),
    .d_axi_wstrb(d_axi_wstrb), .d_axi_wlast(d_axi_wlast),
    .d_axi_wvalid(d_axi_wvalid), .d_axi_wready(d_axi_wready),
    .d_axi_bid(d_axi_bid), .d_axi_bresp(d_axi_bresp),
    .d_axi_bvalid(d_axi_bvalid), .d_axi_bready(d_axi_bready)
  );

  task automatic issue_if_line(input [31:0] request_address,
                               input [31:0] expected_axi_address);
    begin
      while (!if_cmd_ready) @(posedge clk);
      if_cmd_address <= request_address;
      if_cmd_valid <= 1'b1;
      @(posedge clk);
      if_cmd_valid <= 1'b0;
      while (!if_axi_arvalid) @(posedge clk);
      if (if_axi_araddr !== expected_axi_address || if_axi_arlen !== 4'd1)
        $fatal(1, "IF AXI request mismatch addr=%h len=%0d", if_axi_araddr, if_axi_arlen);
      if_axi_arready <= 1'b1;
      @(posedge clk);
      if_axi_arready <= 1'b0;
      if_words = 0;
      if_rsp_ready <= 1'b0;
      if_axi_rdata <= beat0;
      if_axi_rlast <= 1'b0;
      if_axi_rvalid <= 1'b1;
      @(posedge clk);
      if_axi_rvalid <= 1'b0;
      while (if_words < 4) begin
        @(posedge clk);
        if (if_rsp_valid && !if_rsp_ready) if_rsp_ready <= 1'b1;
        if (if_rsp_valid && if_rsp_ready) begin
          if (if_rsp_data !== beat0[if_words*64 +: 64])
            $fatal(1, "IF beat0 word %0d mismatch", if_words);
          if_words = if_words + 1;
        end
      end
      // The second 256-bit beat is the second beat of the same AXI burst.
      if (if_axi_arvalid)
        $fatal(1, "unexpected second IF AXI address phase");
      if_axi_rdata <= beat1;
      if_axi_rlast <= 1'b1;
      if_axi_rvalid <= 1'b1;
      @(posedge clk);
      if_axi_rvalid <= 1'b0;
      while (if_words < 8) begin
        @(posedge clk);
        if (if_rsp_valid && if_rsp_ready) begin
          if (if_rsp_data !== beat1[(if_words-4)*64 +: 64])
            $fatal(1, "IF beat1 word %0d mismatch", if_words-4);
          if_words = if_words + 1;
        end
      end
    end
  endtask

  task automatic issue_d_read;
    begin
      while (!d_read_cmd_ready) @(posedge clk);
      d_read_cmd_address <= 32'h8000_0040;
      d_read_cmd_id <= 1'b1;
      d_read_cmd_valid <= 1'b1;
      @(posedge clk);
      d_read_cmd_valid <= 1'b0;
      while (!d_axi_arvalid) @(posedge clk);
      if (d_axi_araddr !== 32'h8000_0040 || d_axi_arlen !== 4'd1)
        $fatal(1, "D AXI request mismatch addr=%h len=%0d", d_axi_araddr, d_axi_arlen);
      d_axi_arready <= 1'b1;
      @(posedge clk);
      d_axi_arready <= 1'b0;
      d_words = 0;
      d_axi_rdata <= beat0;
      d_axi_rlast <= 1'b0;
      d_axi_rvalid <= 1'b1;
      @(posedge clk);
      d_axi_rvalid <= 1'b0;
      while (d_words < 4) begin
        @(posedge clk);
        if (d_read_rsp_valid && d_read_rsp_ready) begin
          if (d_read_rsp_id !== 1'b1 || d_read_rsp_data !== beat0[d_words*64 +: 64])
            $fatal(1, "D beat0 mismatch at word %0d", d_words);
          d_words = d_words + 1;
        end
      end
      // The second 256-bit beat is the second beat of the same AXI burst.
      if (d_axi_arvalid)
        $fatal(1, "unexpected second D AXI address phase");
      d_axi_rdata <= beat1;
      d_axi_rlast <= 1'b1;
      d_axi_rvalid <= 1'b1;
      @(posedge clk);
      d_axi_rvalid <= 1'b0;
      while (d_words < 8) begin
        @(posedge clk);
        if (d_read_rsp_valid && d_read_rsp_ready) begin
          if (d_read_rsp_data !== beat1[(d_words-4)*64 +: 64])
            $fatal(1, "D beat1 mismatch at word %0d", d_words-4);
          d_words = d_words + 1;
        end
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    init_done = 1'b0;
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
    d_write_cmd_id = 1'b1;
    if_axi_arready = 1'b0;
    if_axi_rid = 4'h0;
    if_axi_rdata = {DW{1'b0}};
    if_axi_rresp = 2'b00;
    if_axi_rlast = 1'b0;
    if_axi_rvalid = 1'b0;
    d_axi_arready = 1'b0;
    d_axi_rid = 4'h1;
    d_axi_rdata = {DW{1'b0}};
    d_axi_rresp = 2'b00;
    d_axi_rlast = 1'b0;
    d_axi_rvalid = 1'b0;
    d_axi_awready = 1'b0;
    d_axi_wready = 1'b0;
    d_axi_bid = 4'h1;
    d_axi_bresp = 2'b00;
    d_axi_bvalid = 1'b0;
    beat0 = {64'h0000_0007,64'h0000_0006,64'h0000_0005,64'h0000_0004};
    beat1 = {64'h0000_0003,64'h0000_0002,64'h0000_0001,64'h0000_0000};

    repeat (2) @(posedge clk);
    reset = 1'b0;
    if_cmd_valid = 1'b1;
    if_cmd_address = 32'h8000_0040;
    @(posedge clk);
    if (if_cmd_ready !== 1'b0)
      $fatal(1, "IF accepted before init_done");
    if_cmd_valid = 1'b0;
    init_done = 1'b1;

    issue_if_line(32'h8000_0040, 32'h8000_0040);
    // The generated contest core can issue a DDR-relative fetch address after
    // the reset-vector transaction; the adapter must keep it in the physical
    // CPU DDR window before handing it to AXI.
    issue_if_line(32'h0000_0000, 32'h8000_0000);
    issue_d_read();

    while (!d_write_cmd_ready) @(posedge clk);
    d_write_cmd_address <= 32'h8000_0048;
    d_write_cmd_data <= 64'hdead_beef_cafe_babe;
    d_write_cmd_valid <= 1'b1;
    @(posedge clk);
    d_write_cmd_valid <= 1'b0;
    while (!d_axi_awvalid || !d_axi_wvalid) @(posedge clk);
    if (d_axi_awaddr !== 32'h8000_0040 || d_axi_awlen !== 4'd0)
      $fatal(1, "D write address mismatch: %h", d_axi_awaddr);
    if (d_axi_wstrb !== 32'h0000_ff00 || d_axi_wdata[127:64] !== 64'hdead_beef_cafe_babe)
      $fatal(1, "D write lane mismatch strobe=%h data=%h", d_axi_wstrb, d_axi_wdata);
    d_axi_awready <= 1'b1;
    d_axi_wready <= 1'b1;
    @(posedge clk);
    d_axi_awready <= 1'b0;
    d_axi_wready <= 1'b0;
    d_axi_bvalid <= 1'b1;
    @(posedge clk);
    d_axi_bvalid <= 1'b0;
    while (!d_write_rsp_valid) @(posedge clk);
    if (d_write_rsp_id !== 1'b1 || d_write_rsp_error)
      $fatal(1, "D write response mismatch");

    $display("PGL50H CPU AXI adapter contract PASS");
    $finish;
  end
endmodule
