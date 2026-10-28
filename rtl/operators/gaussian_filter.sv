`timescale 1ns/1ps

// Fixed 3x3 integer Gaussian filter, kernel [1 2 1; 2 4 2; 1 2 1].
// The input window is ordered row-major, 8 bits per pixel.
module vision_gaussian_filter (
  input  wire                   clk,
  input  wire                   reset,
  input  wire [71:0]            s_window,
  input  wire                   s_valid,
  output wire                   s_ready,
  input  wire                   s_tlast,
  input  wire                   s_tuser,
  output wire [31:0]            m_tdata,
  output wire                   m_tvalid,
  input  wire                   m_tready,
  output wire                   m_tlast,
  output wire                   m_tuser
);
  reg [31:0] data_q;
  reg last_q, user_q, valid_q;
  integer sum;
  integer result;
  reg [7:0] p0,p1,p2,p3,p4,p5,p6,p7,p8;

  assign s_ready = !valid_q || m_tready;
  assign m_tdata = data_q;
  assign m_tvalid = valid_q;
  assign m_tlast = last_q;
  assign m_tuser = user_q;

  always @* begin
    p0=s_window[71:64]; p1=s_window[63:56]; p2=s_window[55:48];
    p3=s_window[47:40]; p4=s_window[39:32]; p5=s_window[31:24];
    p6=s_window[23:16]; p7=s_window[15:8];  p8=s_window[7:0];
    sum = {24'd0,p0} + ({24'd0,p1}<<1) + {24'd0,p2} +
          ({24'd0,p3}<<1) + ({24'd0,p4}<<2) + ({24'd0,p5}<<1) +
          {24'd0,p6} + ({24'd0,p7}<<1) + {24'd0,p8};
    result = (sum + 8) >> 4;
    if (result > 255) result = 255;
  end

  always @(posedge clk) begin
    if (reset) begin
      data_q <= 0; last_q <= 0; user_q <= 0; valid_q <= 0;
    end else if (s_ready) begin
      valid_q <= s_valid;
      if (s_valid) begin
        data_q <= {24'd0, result[7:0]};
        last_q <= s_tlast;
        user_q <= s_tuser;
      end
    end
  end
endmodule
