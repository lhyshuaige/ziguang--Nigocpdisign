`timescale 1ns/1ps

// Generic vertical line buffer for a one-pixel-per-cycle raster stream.
// It emits the pixel at the same x coordinate from the previous two rows.
// Horizontal history belongs to window_generator, keeping this block reusable.
module vision_line_buffer #(
  parameter integer PIXEL_WIDTH = 8,
  parameter integer MAX_WIDTH   = 2048,
  parameter integer COORD_WIDTH = 12
) (
  input  wire                         clk,
  input  wire                         reset,
  input  wire [PIXEL_WIDTH-1:0]       s_pixel,
  input  wire                         s_valid,
  output wire                         s_ready,
  input  wire                         s_tlast,
  input  wire                         s_tuser,
  output wire [PIXEL_WIDTH-1:0]       m_top,
  output wire [PIXEL_WIDTH-1:0]       m_mid,
  output wire [PIXEL_WIDTH-1:0]       m_bot,
  output wire [COORD_WIDTH-1:0]       m_x,
  output wire [COORD_WIDTH-1:0]       m_y,
  output wire                         m_valid,
  input  wire                         m_ready,
  output wire                         m_tlast,
  output wire                         m_tuser,
  output reg                          width_error
);
  localparam integer INDEX_WIDTH = (MAX_WIDTH <= 2) ? 1 : $clog2(MAX_WIDTH);
  localparam [COORD_WIDTH-1:0] MAX_WIDTH_COORD = MAX_WIDTH;
  localparam [COORD_WIDTH-1:0] LAST_WIDTH_COORD = MAX_WIDTH-1;
  reg [PIXEL_WIDTH-1:0] line1 [0:MAX_WIDTH-1];
  reg [PIXEL_WIDTH-1:0] line2 [0:MAX_WIDTH-1];
  reg [COORD_WIDTH-1:0] x_count, y_count;
  reg [PIXEL_WIDTH-1:0] top_q, mid_q, bot_q;
  reg [COORD_WIDTH-1:0] x_q, y_q;
  reg last_q, user_q, valid_q;

  wire [COORD_WIDTH-1:0] in_x = s_tuser ? {COORD_WIDTH{1'b0}} : x_count;
  wire [COORD_WIDTH-1:0] in_y = s_tuser ? {COORD_WIDTH{1'b0}} : y_count;
  wire [INDEX_WIDTH-1:0] in_index = in_x[INDEX_WIDTH-1:0];
  wire x_in_range = in_x < MAX_WIDTH_COORD;
  wire [PIXEL_WIDTH-1:0] tap_top = (in_y >= 2 && x_in_range) ? line2[in_index] : {PIXEL_WIDTH{1'b0}};
  wire [PIXEL_WIDTH-1:0] tap_mid = (in_y >= 1 && x_in_range) ? line1[in_index] : {PIXEL_WIDTH{1'b0}};

  assign s_ready = !valid_q || m_ready;
  assign m_top   = top_q;
  assign m_mid   = mid_q;
  assign m_bot   = bot_q;
  assign m_x     = x_q;
  assign m_y     = y_q;
  assign m_valid = valid_q;
  assign m_tlast = last_q;
  assign m_tuser = user_q;

  always @(posedge clk) begin
    if (reset) begin
      x_count   <= 0;
      y_count   <= 0;
      top_q     <= 0;
      mid_q     <= 0;
      bot_q     <= 0;
      x_q       <= 0;
      y_q       <= 0;
      last_q    <= 0;
      user_q    <= 0;
      valid_q   <= 0;
      width_error <= 1'b0;
      // The line memories are intentionally not reset.  At SOF, y_count is
      // zero, so the first two lines force zero taps; by the time y_count is
      // two every address used by the current frame has been overwritten.
      // This avoids unrolling a MAX_WIDTH reset loop into thousands of flops
      // and keeps the arrays inferable as distributed/embedded RAM.
    end else if (s_ready) begin
      valid_q <= s_valid;
      if (s_valid) begin
        if (!x_in_range) width_error <= 1'b1;
        top_q  <= tap_top;
        mid_q  <= tap_mid;
        bot_q  <= s_pixel;
        x_q    <= in_x;
        y_q    <= in_y;
        last_q <= s_tlast;
        user_q <= s_tuser;

        if (x_in_range) begin
          line2[in_index] <= line1[in_index];
          line1[in_index] <= s_pixel;
        end

        if (s_tlast) begin
          x_count <= 0;
          y_count <= in_y + 1'b1;
        end else begin
          if (in_x == LAST_WIDTH_COORD) width_error <= 1'b1;
          x_count <= in_x + 1'b1;
          y_count <= in_y;
        end
      end
    end
  end
endmodule
