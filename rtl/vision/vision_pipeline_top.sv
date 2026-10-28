`timescale 1ns/1ps

// First stream-to-stream vision pipeline:
// RGB2Gray -> vertical line buffer -> 3x3 window -> Gaussian -> Resize.
// DMA and CNN are intentionally outside this block.
module vision_pipeline_top #(
  parameter integer MAX_WIDTH = 2048,
  parameter integer COORD_WIDTH = 12
) (
  input  wire        clk,
  input  wire        reset,
  input  wire        format_rgb565,
  input  wire        resize_enable,
  input  wire [31:0] image_width,
  input  wire [31:0] image_height,
  input  wire [31:0] resize_width,
  input  wire [31:0] resize_height,
    input  wire [31:0] s_tdata,
    input  wire [3:0]  s_tkeep,
    input  wire        s_tvalid,
  output wire        s_tready,
  input  wire        s_tlast,
  input  wire        s_tuser,
    output wire [31:0] m_tdata,
    output wire [3:0]  m_tkeep,
  output wire        m_tvalid,
  input  wire        m_tready,
  output wire        m_tlast,
  output wire        m_tuser,
  output reg  [31:0] pixel_count,
  output reg  [31:0] frame_count,
  output reg  [31:0] stall_count,
  output reg  [31:0] latency_count,
  output wire        resize_config_error,
  output wire        line_width_error
);
  wire [31:0] gray_data;
  wire gray_valid, gray_ready, gray_last, gray_user;
  wire [7:0] lb_top, lb_mid, lb_bot;
  wire [COORD_WIDTH-1:0] lb_x, lb_y;
  wire lb_valid, lb_ready, lb_last, lb_user;
  wire [71:0] window_data;
  wire [COORD_WIDTH-1:0] window_x, window_y;
  wire window_valid, window_ready, window_last, window_user;
  wire [31:0] gaussian_data;
  wire gaussian_valid, gaussian_ready, gaussian_last, gaussian_user;
  reg latency_active;
  reg [31:0] latency_timer;
  reg [31:0] output_line_count;

  // Phase-1 keeps one 32-bit word per pixel for the existing DMA/frame-buffer
  // contract.  The sideband is present at the interface now; packed-byte
  // modes can be propagated through the operators once their memory layout is
  // enabled by software.
  assign m_tkeep = 4'b1111;

  vision_rgb2gray u_rgb2gray (
    .clk(clk), .reset(reset), .format_rgb565(format_rgb565),
    .s_tdata(s_tdata), .s_tvalid(s_tvalid), .s_tready(s_tready),
    .s_tlast(s_tlast), .s_tuser(s_tuser),
    .m_tdata(gray_data), .m_tvalid(gray_valid), .m_tready(gray_ready),
    .m_tlast(gray_last), .m_tuser(gray_user)
  );

  vision_line_buffer #(.PIXEL_WIDTH(8), .MAX_WIDTH(MAX_WIDTH), .COORD_WIDTH(COORD_WIDTH)) u_line_buffer (
    .clk(clk), .reset(reset), .s_pixel(gray_data[7:0]),
    .s_valid(gray_valid), .s_ready(gray_ready), .s_tlast(gray_last), .s_tuser(gray_user),
    .m_top(lb_top), .m_mid(lb_mid), .m_bot(lb_bot), .m_x(lb_x), .m_y(lb_y),
    .m_valid(lb_valid), .m_ready(lb_ready), .m_tlast(lb_last), .m_tuser(lb_user),
    .width_error(line_width_error)
  );

  vision_window_generator #(.PIXEL_WIDTH(8), .COORD_WIDTH(COORD_WIDTH)) u_window_generator (
    .clk(clk), .reset(reset), .s_top(lb_top), .s_mid(lb_mid), .s_bot(lb_bot),
    .s_x(lb_x), .s_y(lb_y), .s_valid(lb_valid), .s_ready(lb_ready),
    .s_tlast(lb_last), .s_tuser(lb_user), .m_window(window_data),
    .m_x(window_x), .m_y(window_y), .m_valid(window_valid), .m_ready(window_ready),
    .m_tlast(window_last), .m_tuser(window_user)
  );

  vision_gaussian_filter u_gaussian (
    .clk(clk), .reset(reset), .s_window(window_data), .s_valid(window_valid),
    .s_ready(window_ready), .s_tlast(window_last), .s_tuser(window_user),
    .m_tdata(gaussian_data), .m_tvalid(gaussian_valid), .m_tready(gaussian_ready),
    .m_tlast(gaussian_last), .m_tuser(gaussian_user)
  );

  wire [31:0] filtered_width = (image_width > 2) ? image_width - 2 : image_width;
  wire [31:0] filtered_height = (image_height > 2) ? image_height - 2 : image_height;
  wire [31:0] expected_output_lines = resize_enable ? resize_height : filtered_height;

  // Phase-1 SoC timing target: keep the combinational nearest-neighbor
  // phase engine to two iterations (up to 2x expansion).  The standalone
  // operator remains parameterized for a future multi-cycle scaler.
  vision_resize_nn #(.MAX_REPEAT(2)) u_resize (
    .clk(clk), .reset(reset), .enable(resize_enable),
    .src_width(filtered_width), .src_height(filtered_height),
    .dst_width(resize_width), .dst_height(resize_height),
    .s_tdata(gaussian_data), .s_tvalid(gaussian_valid), .s_tready(gaussian_ready),
    .s_tlast(gaussian_last), .s_tuser(gaussian_user),
    .m_tdata(m_tdata), .m_tvalid(m_tvalid), .m_tready(m_tready),
    .m_tlast(m_tlast), .m_tuser(m_tuser), .config_error(resize_config_error)
  );

  always @(posedge clk) begin
    if (reset) begin
      pixel_count <= 0;
      frame_count <= 0;
      stall_count <= 0;
      latency_count <= 0;
      latency_active <= 1'b0;
      latency_timer <= 0;
      output_line_count <= 0;
    end else begin
      if (m_tvalid && m_tready) begin
        pixel_count <= pixel_count + 1'b1;
        if (m_tlast) begin
          // VALID_CROP produces image_height-2 output lines.  Count a frame
          // only at the final output line, not at every EOL.
          if ((expected_output_lines != 0) && (output_line_count + 1 >= expected_output_lines)) begin
            frame_count <= frame_count + 1'b1;
            output_line_count <= 0;
          end else begin
            output_line_count <= output_line_count + 1'b1;
          end
        end
      end
      if (s_tvalid && !s_tready) stall_count <= stall_count + 1'b1;
      if (s_tvalid && s_tready && s_tuser) begin
        latency_active <= 1'b1;
        latency_timer <= 0;
      end else if (latency_active) begin
        latency_timer <= latency_timer + 1'b1;
      end
      if (m_tvalid && m_tready && m_tuser && latency_active) begin
        latency_count <= latency_timer;
        latency_active <= 1'b0;
      end
    end
  end
endmodule
