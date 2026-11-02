`timescale 1ns/1ps

// Dual-clock FIFO for camera pixels and all associated video sideband.
// DEPTH must be a power of two.  Overflow is sticky until reset so software
// can diagnose a frame that was not fully absorbed by the camera path.
module camera_async_fifo #(
  parameter integer PAYLOAD_WIDTH = 38,
  parameter integer DEPTH = 2048
) (
  input  wire                         wr_clk,
  input  wire                         wr_reset,
  input  wire [PAYLOAD_WIDTH-1:0]     wr_payload,
  input  wire                         wr_valid,
  output wire                         wr_ready,
  output wire                         wr_overflow,
  input  wire                         rd_clk,
  input  wire                         rd_reset,
  output wire [PAYLOAD_WIDTH-1:0]     rd_payload,
  output wire                         rd_valid,
  input  wire                         rd_ready,
  output wire [31:0]                  rd_level,
  output wire                         rd_empty,
  output wire                         wr_full
);
  localparam integer ADDR_WIDTH = $clog2(DEPTH);
  reg [PAYLOAD_WIDTH-1:0] mem [0:DEPTH-1];
  reg [ADDR_WIDTH:0] wr_bin_q, wr_gray_q;
  reg [ADDR_WIDTH:0] rd_bin_q, rd_gray_q;
  reg                 wr_full_q;
  reg [ADDR_WIDTH:0] rd_gray_w1_q, rd_gray_w2_q;
  reg [ADDR_WIDTH:0] wr_gray_r1_q, wr_gray_r2_q;
  reg overflow_q;
  reg [PAYLOAD_WIDTH-1:0] rd_payload_q;
  reg rd_valid_q;

  wire [ADDR_WIDTH:0] wr_bin_next = wr_bin_q + ((wr_valid && !wr_full_q) ? {{ADDR_WIDTH{1'b0}},1'b1} : {(ADDR_WIDTH+1){1'b0}});
  wire [ADDR_WIDTH:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
  wire full_next = (wr_gray_next == {~rd_gray_w2_q[ADDR_WIDTH:ADDR_WIDTH-1],
                                      rd_gray_w2_q[ADDR_WIDTH-2:0]});

  assign wr_full = wr_full_q;
  assign wr_ready = !wr_full_q;
  assign wr_overflow = overflow_q;
  assign rd_empty = (rd_gray_q == wr_gray_r2_q) && !rd_valid_q;
  assign rd_valid = rd_valid_q;
  assign rd_payload = rd_payload_q;
  function [ADDR_WIDTH:0] gray_to_bin;
    input [ADDR_WIDTH:0] gray;
    integer i;
    begin
      gray_to_bin[ADDR_WIDTH] = gray[ADDR_WIDTH];
      for (i = ADDR_WIDTH-1; i >= 0; i = i-1)
        gray_to_bin[i] = gray_to_bin[i+1] ^ gray[i];
    end
  endfunction
  wire [ADDR_WIDTH:0] wr_bin_r = gray_to_bin(wr_gray_r2_q);
  wire [ADDR_WIDTH:0] rd_bin_r = rd_bin_q;
  assign rd_level = {{(32-ADDR_WIDTH-1){1'b0}}, (wr_bin_r - rd_bin_r)};

  always @(posedge wr_clk) begin
    if (wr_reset) begin
      wr_bin_q <= 0; wr_gray_q <= 0; wr_full_q <= 1'b0; overflow_q <= 1'b0;
      rd_gray_w1_q <= 0; rd_gray_w2_q <= 0;
    end else begin
      rd_gray_w1_q <= rd_gray_q;
      rd_gray_w2_q <= rd_gray_w1_q;
      wr_full_q <= full_next;
      if (wr_valid && wr_full_q) overflow_q <= 1'b1;
      if (wr_valid && !wr_full_q) begin
        mem[wr_bin_q[ADDR_WIDTH-1:0]] <= wr_payload;
        wr_bin_q <= wr_bin_next;
        wr_gray_q <= wr_gray_next;
      end
    end
  end

  always @(posedge rd_clk) begin
    if (rd_reset) begin
      rd_bin_q <= 0; rd_gray_q <= 0;
      wr_gray_r1_q <= 0; wr_gray_r2_q <= 0;
      rd_payload_q <= 0; rd_valid_q <= 1'b0;
    end else begin
      wr_gray_r1_q <= wr_gray_q;
      wr_gray_r2_q <= wr_gray_r1_q;

      if (rd_valid_q && rd_ready) rd_valid_q <= 1'b0;
      if ((!rd_valid_q || rd_ready) && (rd_gray_q != wr_gray_r2_q)) begin
        rd_payload_q <= mem[rd_bin_q[ADDR_WIDTH-1:0]];
        rd_bin_q <= rd_bin_q + 1'b1;
        rd_gray_q <= ((rd_bin_q + 1'b1) >> 1) ^ (rd_bin_q + 1'b1);
        rd_valid_q <= 1'b1;
      end
    end
  end
endmodule
