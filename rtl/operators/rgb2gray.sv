`timescale 1ns/1ps

// RGB888/RGB565 to 8-bit gray AXI4-Stream stage.
// RGB888 input is {8'h00, R, G, B}; RGB565 input uses data[15:0].
module vision_rgb2gray (
  input  wire        clk,
  input  wire        reset,
  input  wire        format_rgb565,
  input  wire [31:0] s_tdata,
  input  wire        s_tvalid,
  output wire        s_tready,
  input  wire        s_tlast,
  input  wire        s_tuser,
  output wire [31:0] m_tdata,
  output wire        m_tvalid,
  input  wire        m_tready,
  output wire        m_tlast,
  output wire        m_tuser
);
  reg [31:0] data_q;
  reg last_q, user_q, valid_q;
  reg [7:0] r, g, b;
  reg [17:0] gray_sum;

  assign s_tready = !valid_q || m_tready;
  assign m_tdata  = data_q;
  assign m_tvalid = valid_q;
  assign m_tlast  = last_q;
  assign m_tuser  = user_q;

  always @* begin
    if (format_rgb565) begin
      r = {s_tdata[15:11], s_tdata[15:13]};
      g = {s_tdata[10:5],  s_tdata[10:9]};
      b = {s_tdata[4:0],   s_tdata[4:2]};
    end else begin
      r = s_tdata[23:16];
      g = s_tdata[15:8];
      b = s_tdata[7:0];
    end
    gray_sum = r * 8'd77 + g * 8'd150 + b * 8'd29 + 18'd128;
  end

  always @(posedge clk) begin
    if (reset) begin
      data_q  <= 32'd0;
      last_q  <= 1'b0;
      user_q  <= 1'b0;
      valid_q <= 1'b0;
    end else if (s_tready) begin
      valid_q <= s_tvalid;
      if (s_tvalid) begin
        data_q <= {24'd0, gray_sum[15:8]};
        last_q <= s_tlast;
        user_q <= s_tuser;
      end
    end
  end
endmodule
