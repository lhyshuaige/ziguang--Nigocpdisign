`timescale 1ns/1ps

// Horizontal part of a 3x3 window generator.  Window bit ordering is:
// [71:64] top-left, ..., [7:0] bottom-middle, [7:0] bottom-right.
module vision_window_generator #(
  parameter integer PIXEL_WIDTH = 8,
  parameter integer COORD_WIDTH = 12
) (
  input  wire                         clk,
  input  wire                         reset,
  input  wire [PIXEL_WIDTH-1:0]       s_top,
  input  wire [PIXEL_WIDTH-1:0]       s_mid,
  input  wire [PIXEL_WIDTH-1:0]       s_bot,
  input  wire [COORD_WIDTH-1:0]       s_x,
  input  wire [COORD_WIDTH-1:0]       s_y,
  input  wire                         s_valid,
  output wire                         s_ready,
  input  wire                         s_tlast,
  input  wire                         s_tuser,
  output wire [PIXEL_WIDTH*9-1:0]     m_window,
  output wire [COORD_WIDTH-1:0]       m_x,
  output wire [COORD_WIDTH-1:0]       m_y,
  output wire                         m_valid,
  input  wire                         m_ready,
  output wire                         m_tlast,
  output wire                         m_tuser
);
  reg [PIXEL_WIDTH-1:0] top_d1, top_d2;
  reg [PIXEL_WIDTH-1:0] mid_d1, mid_d2;
  reg [PIXEL_WIDTH-1:0] bot_d1, bot_d2;
  reg [PIXEL_WIDTH*9-1:0] window_q;
  reg [COORD_WIDTH-1:0] x_q, y_q;
  reg last_q, user_q, valid_q;
  reg frame_pending;

  wire can_accept = !valid_q || m_ready;
  wire window_enable = s_valid && (s_x >= 2) && (s_y >= 2);
  wire [PIXEL_WIDTH-1:0] tl = (s_x >= 2) ? top_d2 : 0;
  wire [PIXEL_WIDTH-1:0] tm = (s_x >= 1) ? top_d1 : 0;
  wire [PIXEL_WIDTH-1:0] ml = (s_x >= 2) ? mid_d2 : 0;
  wire [PIXEL_WIDTH-1:0] mm = (s_x >= 1) ? mid_d1 : 0;
  wire [PIXEL_WIDTH-1:0] bl = (s_x >= 2) ? bot_d2 : 0;
  wire [PIXEL_WIDTH-1:0] bm = (s_x >= 1) ? bot_d1 : 0;

  assign s_ready = can_accept;
  assign m_window = window_q;
  assign m_x = x_q;
  assign m_y = y_q;
  assign m_valid = valid_q;
  assign m_tlast = last_q;
  assign m_tuser = user_q;

  always @(posedge clk) begin
    if (reset) begin
      top_d1 <= 0; top_d2 <= 0;
      mid_d1 <= 0; mid_d2 <= 0;
      bot_d1 <= 0; bot_d2 <= 0;
      window_q <= 0;
      x_q <= 0; y_q <= 0;
      last_q <= 0; user_q <= 0; valid_q <= 0;
      frame_pending <= 0;
    end else if (can_accept) begin
      valid_q <= window_enable;
      if (s_valid) begin
        if (s_tuser) frame_pending <= 1'b1;
        if (window_enable) begin
          window_q <= {tl, tm, s_top, ml, mm, s_mid, bl, bm, s_bot};
          x_q <= s_x;
          y_q <= s_y;
          last_q <= s_tlast;
          user_q <= frame_pending;
          if (frame_pending) frame_pending <= 1'b0;
        end
        if (s_x == 0) begin
          top_d2 <= 0; top_d1 <= s_top;
          mid_d2 <= 0; mid_d1 <= s_mid;
          bot_d2 <= 0; bot_d1 <= s_bot;
        end else begin
          top_d2 <= top_d1; top_d1 <= s_top;
          mid_d2 <= mid_d1; mid_d1 <= s_mid;
          bot_d2 <= bot_d1; bot_d1 <= s_bot;
        end
      end
    end
  end
endmodule
