`timescale 1ns/1ps

module div_radix4_tb;
  reg          clk = 1'b0;
  reg          reset = 1'b1;
  reg          io_flush = 1'b0;
  reg          io_cmd_valid = 1'b0;
  wire         io_cmd_ready;
  reg  [31:0]  io_cmd_payload_a = 32'd0;
  reg  [31:0]  io_cmd_payload_b = 32'd0;
  wire         io_rsp_valid;
  reg          io_rsp_ready = 1'b1;
  wire [34:0]  io_rsp_payload_result;
  wire [32:0]  io_rsp_payload_remain;

  integer tests = 0;
  integer failures = 0;
  integer seed = 32'h4d3c2b1a;

  always #5 clk = ~clk;

  DivRadix4 dut (
    .io_flush(io_flush),
    .io_cmd_valid(io_cmd_valid),
    .io_cmd_ready(io_cmd_ready),
    .io_cmd_payload_a(io_cmd_payload_a),
    .io_cmd_payload_b(io_cmd_payload_b),
    .io_rsp_valid(io_rsp_valid),
    .io_rsp_ready(io_rsp_ready),
    .io_rsp_payload_result(io_rsp_payload_result),
    .io_rsp_payload_remain(io_rsp_payload_remain),
    .clk(clk),
    .reset(reset)
  );

  task automatic run_case(input [31:0] dividend, input [31:0] divisor);
    reg [31:0] expected_q;
    reg [31:0] expected_r;
    integer timeout;
    begin
      expected_q = (divisor == 0) ? 32'hffffffff : (dividend / divisor);
      expected_r = (divisor == 0) ? dividend : (dividend % divisor);

      while (!io_cmd_ready) @(posedge clk);
      @(negedge clk);
      io_cmd_payload_a = dividend;
      io_cmd_payload_b = divisor;
      io_cmd_valid = 1'b1;
      @(negedge clk);
      io_cmd_valid = 1'b0;

      timeout = 0;
      while (!io_rsp_valid && timeout < 40) begin
        @(negedge clk);
        timeout = timeout + 1;
      end

      tests = tests + 1;
      if (timeout == 40) begin
        $display("FAIL timeout a=%08x b=%08x", dividend, divisor);
        failures = failures + 1;
      end else if ((io_rsp_payload_result[31:0] !== expected_q) ||
                   (io_rsp_payload_remain[31:0] !== expected_r)) begin
        $display("FAIL a=%08x b=%08x q=%08x/%08x r=%08x/%08x",
                 dividend, divisor,
                 io_rsp_payload_result[31:0], expected_q,
                 io_rsp_payload_remain[31:0], expected_r);
        failures = failures + 1;
      end
      @(negedge clk);
    end
  endtask

  integer i;
  reg [31:0] random_a;
  reg [31:0] random_b;
  initial begin
    repeat (4) @(posedge clk);
    reset = 1'b0;

    run_case(32'h00000000, 32'h00000000);
    run_case(32'h00000001, 32'h00000000);
    run_case(32'hffffffff, 32'h00000000);
    run_case(32'h00000000, 32'h00000001);
    run_case(32'h00000001, 32'h00000001);
    run_case(32'hffffffff, 32'h00000001);
    run_case(32'hffffffff, 32'hffffffff);
    run_case(32'h80000000, 32'h00000003);
    run_case(32'h12345678, 32'h00001234);
    run_case(32'hdeadbeef, 32'h00010001);

    for (i = 0; i < 200; i = i + 1) begin
      random_a = $urandom(seed);
      random_b = $urandom(seed);
      run_case(random_a, random_b);
    end

    // A flushed command must not later produce a response.
    while (!io_cmd_ready) @(posedge clk);
    @(negedge clk);
    io_cmd_payload_a = 32'habcdef01;
    io_cmd_payload_b = 32'h00000123;
    io_cmd_valid = 1'b1;
    @(negedge clk);
    io_cmd_valid = 1'b0;
    repeat (2) @(negedge clk);
    io_flush = 1'b1;
    @(negedge clk);
    io_flush = 1'b0;
    repeat (20) begin
      @(negedge clk);
      if (io_rsp_valid) begin
        $display("FAIL flushed command produced a response");
        failures = failures + 1;
      end
    end
    run_case(32'habcdef01, 32'h00000123);

    if (failures == 0)
      $display("DIV_RADIX4_PASS tests=%0d", tests);
    else
      $fatal(1, "DIV_RADIX4_FAIL tests=%0d failures=%0d", tests, failures);
    $finish;
  end
endmodule
