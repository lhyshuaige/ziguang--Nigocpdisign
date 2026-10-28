`timescale 1ns/1ps

// OV7670/parallel-DVP camera input subsystem.  This block is a stream source;
// it does not instantiate or alter the existing AXI DMA.
module camera_rx_subsystem #(
  parameter integer DATA_WIDTH = 8,
  parameter integer FIFO_DEPTH = 2048,
  parameter integer PCLK_FALLING = 0,
  parameter integer WORD_COMPAT_TKEEP = 1
) (
  input  wire                    cam_pclk,
  input  wire                    cam_reset,
  input  wire                    cam_enable,
  input  wire                    cam_vsync,
  input  wire                    cam_href,
  input  wire [DATA_WIDTH-1:0]   cam_data,
  input  wire                    soc_clk,
  input  wire                    soc_reset,
  output wire [31:0]             m_axis_tdata,
  output wire [3:0]              m_axis_tkeep,
  output wire                    m_axis_tvalid,
  input  wire                    m_axis_tready,
  output wire                    m_axis_tuser,
  output wire                    m_axis_tlast,
  output wire                    cam_frame_active,
  output wire                    cam_line_active,
  output wire                    fifo_overflow,
  output wire                    fifo_empty,
  output wire                    fifo_full,
  output wire [31:0]             fifo_level,
  output wire                    partial_pixel_error
);
  wire [31:0] pixel_data;
  wire [3:0] pixel_keep;
  wire pixel_valid, pixel_sof, pixel_eol;
  wire [37:0] fifo_wr_payload = {pixel_eol, pixel_sof, pixel_keep, pixel_data};
  wire [37:0] fifo_rd_payload;
  wire fifo_rd_valid, fifo_rd_ready;
  wire fifo_wr_ready;
  wire [3:0] fifo_keep = fifo_rd_payload[35:32];

  camera_rx_dvp #(
    .DATA_WIDTH(DATA_WIDTH), .PCLK_FALLING(PCLK_FALLING),
    .WORD_COMPAT_TKEEP(WORD_COMPAT_TKEEP)
  ) u_dvp (
    .cam_pclk(cam_pclk), .cam_reset(cam_reset), .enable(cam_enable),
    .cam_vsync(cam_vsync), .cam_href(cam_href), .cam_data(cam_data),
    .pixel_data(pixel_data), .pixel_keep(pixel_keep), .pixel_valid(pixel_valid),
    .pixel_sof(pixel_sof), .pixel_eol(pixel_eol),
    .frame_active(cam_frame_active), .line_active(cam_line_active),
    .partial_pixel_error(partial_pixel_error)
  );

  camera_async_fifo #(.PAYLOAD_WIDTH(38), .DEPTH(FIFO_DEPTH)) u_fifo (
    .wr_clk(cam_pclk), .wr_reset(cam_reset), .wr_payload(fifo_wr_payload),
    .wr_valid(pixel_valid), .wr_ready(fifo_wr_ready), .wr_overflow(fifo_overflow),
    .rd_clk(soc_clk), .rd_reset(soc_reset), .rd_payload(fifo_rd_payload),
    .rd_valid(fifo_rd_valid), .rd_ready(fifo_rd_ready), .rd_level(fifo_level),
    .rd_empty(fifo_empty), .wr_full(fifo_full)
  );

  camera_stream_adapter #(.DATA_WIDTH(32)) u_stream_adapter (
    .clk(soc_clk), .reset(soc_reset),
    .s_data(fifo_rd_payload[31:0]), .s_keep(fifo_keep),
    .s_sof(fifo_rd_payload[36]), .s_eol(fifo_rd_payload[37]),
    .s_valid(fifo_rd_valid), .s_ready(fifo_rd_ready),
    .m_tdata(m_axis_tdata), .m_tkeep(m_axis_tkeep), .m_tuser(m_axis_tuser),
    .m_tlast(m_axis_tlast), .m_tvalid(m_axis_tvalid), .m_tready(m_axis_tready)
  );
endmodule
