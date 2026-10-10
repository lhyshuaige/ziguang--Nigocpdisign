`timescale 1ns/1ps

// Behavioural contract test for the CPU-native -> PGL50H HMIC user-port
// bridge.  The HMIC model stores one 256-bit beat per 8-byte command address.
module pgl50h_native_axi_bridge_tb;
  localparam integer AW = 28;
  localparam integer DW = 256;

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
  wire [0:0] d_read_rsp_id;
  wire [63:0] d_read_rsp_data;
  wire       d_read_rsp_error;
  reg        d_read_rsp_ready;

  reg        d_write_cmd_valid;
  wire       d_write_cmd_ready;
  reg        d_write_cmd_last;
  reg [31:0] d_write_cmd_address;
  reg [63:0] d_write_cmd_data;
  reg [0:0]  d_write_cmd_id;
  wire       d_write_rsp_valid;
  wire [0:0] d_write_rsp_id;
  wire       d_write_rsp_error;

  wire [AW-1:0] h_awaddr;
  wire           h_awuser_ap;
  wire [3:0]     h_awuser_id;
  wire [3:0]     h_awlen;
  wire           h_awready;
  wire           h_awvalid;
  wire [DW-1:0] h_wdata;
  wire [31:0]   h_wstrb;
  wire           h_wready;
  wire [3:0]     h_wusero_id;
  wire           h_wusero_last;
  wire [AW-1:0] h_araddr;
  wire           h_aruser_ap;
  wire [3:0]     h_aruser_id;
  wire [3:0]     h_arlen;
  wire           h_arready;
  wire           h_arvalid;
  reg [DW-1:0]   h_rdata;
  reg [3:0]      h_rid;
  reg            h_rlast;
  reg            h_rvalid;

  reg [DW-1:0] mem [0:255];
  reg [AW-1:0] pending_raddr;
  reg          pending_rvalid;
  integer i;
  integer if_words;
  integer d_words;
  integer ar_count;
  reg [63:0] expected;

  assign h_awready = 1'b1;
  assign h_wready  = 1'b1;
  assign h_arready = !pending_rvalid;
  assign h_wusero_id = h_awuser_id;
  assign h_wusero_last = 1'b1;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    h_rvalid <= 1'b0;
    if (h_arvalid && h_arready) begin
      if ((ar_count % 2) == 0 && h_araddr !== 28'h0000_008)
        $fatal(1, "unexpected HMIC read address at beat %0d: %h", ar_count, h_araddr);
      if ((ar_count % 2) == 1 && h_araddr !== 28'h0000_00c)
        $fatal(1, "unexpected HMIC read address at beat %0d: %h", ar_count, h_araddr);
      ar_count = ar_count + 1;
      pending_raddr <= h_araddr;
      pending_rvalid <= 1'b1;
    end
    if (pending_rvalid) begin
      h_rdata <= mem[pending_raddr[7:0]];
      h_rid <= 4'h0;
      h_rlast <= 1'b1;
      h_rvalid <= 1'b1;
      pending_rvalid <= 1'b0;
    end
    if (h_awvalid && h_awready && h_wvalid_for_tb && h_wready)
      mem[h_awaddr[7:0]] <= h_wdata;
  end

  // HMIC W has no valid signal in the controller's user-port contract.  The
  // bridge presents W immediately after AW, so the model treats W as valid
  // whenever the AW channel is being accepted.
  wire h_wvalid_for_tb = h_awvalid;

  pgl50h_native_axi_bridge #(
    .AXI_ADDR_WIDTH(AW),
    .AXI_DATA_WIDTH(DW),
    .CPU_MEM_BASE(32'h8000_0000),
    .HMIC_ADDR_SHIFT(3)
  ) dut (
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
    .axi_awaddr(h_awaddr), .axi_awuser_ap(h_awuser_ap),
    .axi_awuser_id(h_awuser_id), .axi_awlen(h_awlen),
    .axi_awready(h_awready), .axi_awvalid(h_awvalid),
    .axi_wdata(h_wdata), .axi_wstrb(h_wstrb), .axi_wready(h_wready),
    .axi_wusero_id(h_wusero_id), .axi_wusero_last(h_wusero_last),
    .axi_araddr(h_araddr), .axi_aruser_ap(h_aruser_ap),
    .axi_aruser_id(h_aruser_id), .axi_arlen(h_arlen),
    .axi_arready(h_arready), .axi_arvalid(h_arvalid),
    .axi_rdata(h_rdata), .axi_rid(h_rid), .axi_rlast(h_rlast),
    .axi_rvalid(h_rvalid)
  );

  task automatic issue_if_line(input [31:0] address);
    begin
      @(posedge clk);
      while (!if_cmd_ready) @(posedge clk);
      if_cmd_address <= address;
      if_cmd_valid <= 1'b1;
      @(posedge clk);
      if_cmd_valid <= 1'b0;
      if_words = 0;
      while (if_words < 8) begin
        @(posedge clk);
        if (if_rsp_valid) begin
          expected = mem[((address - 32'h8000_0000) >> 3) + ((if_words / 4) * 4)][((if_words % 4) * 64) +: 64];
          if (if_rsp_data !== expected)
            $fatal(1, "IF word %0d mismatch: got %h expected %h", if_words, if_rsp_data, expected);
          if_words = if_words + 1;
        end
      end
    end
  endtask

  task automatic issue_d_line(input [31:0] address, input [0:0] id);
    begin
      if ((address & 32'h0000_003f) !== 32'h0)
        $fatal(1, "D-cache refill address is not line aligned: %h", address);
      @(posedge clk);
      while (!d_read_cmd_ready) @(posedge clk);
      d_read_cmd_address <= address;
      d_read_cmd_id      <= id;
      d_read_cmd_valid   <= 1'b1;
      @(posedge clk);
      d_read_cmd_valid   <= 1'b0;
      d_words = 0;
      while (d_words < 8) begin
        @(posedge clk);
        if (d_read_rsp_valid) begin
          expected = mem[((address - 32'h8000_0000) >> 3) + ((d_words / 4) * 4)][((d_words % 4) * 64) +: 64];
          if (d_read_rsp_id !== id)
            $fatal(1, "D-read ID mismatch at word %0d: got %b expected %b", d_words, d_read_rsp_id, id);
          if (d_read_rsp_data !== expected)
            $fatal(1, "D-read data mismatch at word %0d: got %h expected %h", d_words, d_read_rsp_data, expected);
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
    d_write_cmd_id = 1'b0;
    pending_rvalid = 1'b0;
    ar_count = 0;
    h_rvalid = 1'b0;
    h_rdata = {DW{1'b0}};
    h_rid = 4'h0;
    h_rlast = 1'b0;
    for (i = 0; i < 256; i = i + 1) mem[i] = {4{64'h0}};
    mem[8'h08] = {64'h8000_0007,64'h8000_0006,64'h8000_0005,64'h8000_0004};
    mem[8'h0c] = {64'h8000_0003,64'h8000_0002,64'h8000_0001,64'h8000_0000};

    repeat (2) @(posedge clk);
    reset = 1'b0;

    // No CPU memory request may be accepted before DDR initialization.
    if_cmd_valid = 1'b1;
    if_cmd_address = 32'h8000_0040;
    @(posedge clk);
    if (if_cmd_ready !== 1'b0)
      $fatal(1, "IF request accepted before init_done");
    if_cmd_valid = 1'b0;

    init_done = 1'b1;
    issue_if_line(32'h8000_0040);

    // The generated NaxRiscv data-cache contract is also a 64-byte,
    // line-aligned refill with eight streamed 64-bit responses.
    issue_d_line(32'h8000_0040, 1'b1);

    @(posedge clk);
    while (!d_write_cmd_ready) @(posedge clk);
    d_write_cmd_address <= 32'h8000_0048;
    d_write_cmd_data <= 64'hdead_beef_cafe_babe;
    d_write_cmd_valid <= 1'b1;
    @(posedge clk);
    d_write_cmd_valid <= 1'b0;
    while (!d_write_rsp_valid) @(posedge clk);
    if (h_awaddr !== 28'h0000_008)
      $fatal(1, "unexpected HMIC write address: %h", h_awaddr);
    if (h_wstrb !== 32'h0000_ff00)
      $fatal(1, "unexpected HMIC write strobe: %h", h_wstrb);
    if (mem[8'h08][127:64] !== 64'hdead_beef_cafe_babe)
      $fatal(1, "write lane mapping failed: %h", mem[8'h08]);
    if (ar_count !== 4)
      $fatal(1, "expected four HMIC read commands, got %0d", ar_count);

    $display("PGL50H native AXI bridge contract PASS");
    $finish;
  end
endmodule
