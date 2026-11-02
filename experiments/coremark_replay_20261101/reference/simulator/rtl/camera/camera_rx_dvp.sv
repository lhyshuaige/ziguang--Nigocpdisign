`timescale 1ns/1ps

// Parameterized parallel-camera receiver.
//
// The DVP timing layer and the RGB565 byte assembler intentionally live in
// this module for the first camera revision.  The byte assembler is kept as a
// separate state region so DATA_WIDTH and the byte order can be extended for
// OV5640 DVP without changing the CDC boundary.
module camera_rx_dvp #(
  parameter integer DATA_WIDTH = 8,
  parameter integer PCLK_FALLING = 0,
  parameter integer VSYNC_ACTIVE = 1,
  parameter integer HREF_ACTIVE = 1,
  parameter integer BYTE_HIGH_FIRST = 1,
  parameter integer WORD_COMPAT_TKEEP = 1
) (
  input  wire                    cam_pclk,
  input  wire                    cam_reset,
  input  wire                    enable,
  input  wire                    cam_vsync,
  input  wire                    cam_href,
  input  wire [DATA_WIDTH-1:0]   cam_data,
  output wire [31:0]             pixel_data,
  output wire [3:0]              pixel_keep,
  output wire                    pixel_valid,
  output wire                    pixel_sof,
  output wire                    pixel_eol,
  output wire                    frame_active,
  output wire                    line_active,
  output wire                    partial_pixel_error
);

  // Keep the edge-selectable implementation in a small child.  This avoids
  // fabric-generated inverted clocks while retaining a portable parameter.
  camera_rx_dvp_capture #(
    .DATA_WIDTH(DATA_WIDTH),
    .PCLK_FALLING(PCLK_FALLING),
    .VSYNC_ACTIVE(VSYNC_ACTIVE),
    .HREF_ACTIVE(HREF_ACTIVE),
    .BYTE_HIGH_FIRST(BYTE_HIGH_FIRST),
    .WORD_COMPAT_TKEEP(WORD_COMPAT_TKEEP)
  ) u_capture (
    .cam_pclk(cam_pclk), .cam_reset(cam_reset), .enable(enable),
    .cam_vsync(cam_vsync), .cam_href(cam_href), .cam_data(cam_data),
    .pixel_data(pixel_data), .pixel_keep(pixel_keep),
    .pixel_valid(pixel_valid), .pixel_sof(pixel_sof), .pixel_eol(pixel_eol),
    .frame_active(frame_active), .line_active(line_active),
    .partial_pixel_error(partial_pixel_error)
  );
endmodule

module camera_rx_dvp_capture #(
  parameter integer DATA_WIDTH = 8,
  parameter integer PCLK_FALLING = 0,
  parameter integer VSYNC_ACTIVE = 1,
  parameter integer HREF_ACTIVE = 1,
  parameter integer BYTE_HIGH_FIRST = 1,
  parameter integer WORD_COMPAT_TKEEP = 1
) (
  input  wire                    cam_pclk,
  input  wire                    cam_reset,
  input  wire                    enable,
  input  wire                    cam_vsync,
  input  wire                    cam_href,
  input  wire [DATA_WIDTH-1:0]   cam_data,
  output reg  [31:0]             pixel_data,
  output reg  [3:0]              pixel_keep,
  output reg                     pixel_valid,
  output reg                     pixel_sof,
  output reg                     pixel_eol,
  output reg                     frame_active,
  output wire                    line_active,
  output reg                     partial_pixel_error
);
  // Keep these typed as integer constants for compatibility with the PDS
  // Verilog front-end used by the board synthesis flow.
  localparam integer VSYNC_ACTIVE_BIT = (VSYNC_ACTIVE != 0);
  localparam integer HREF_ACTIVE_BIT = (HREF_ACTIVE != 0);
  localparam integer BYTE_HIGH_FIRST_BIT = (BYTE_HIGH_FIRST != 0);
  localparam integer WORD_COMPAT_TKEEP_BIT = (WORD_COMPAT_TKEEP != 0);
  localparam [3:0] DEFAULT_KEEP = WORD_COMPAT_TKEEP_BIT ? 4'b1111 : 4'b0011;
  reg [DATA_WIDTH-1:0] byte_first_q;
  reg                   byte_phase_q;
  reg [31:0]            pending_pixel_q;
  reg                   pending_valid_q;
  reg                   pending_sof_q;
  reg                   sof_pending_q;
  reg                   frame_seen_q;

  wire vsync_active = (cam_vsync == VSYNC_ACTIVE_BIT);
  wire href_active  = (cam_href  == HREF_ACTIVE_BIT);
  assign line_active = href_active && enable && !vsync_active;

  wire [15:0] rgb565_word = BYTE_HIGH_FIRST_BIT
                           ? {byte_first_q[7:0], cam_data[7:0]}
                           : {cam_data[7:0], byte_first_q[7:0]};

  // A pending pixel gives the receiver one PCLK to observe HREF falling.
  // Therefore EOL is attached to the last complete pixel rather than to a
  // separate blanking-cycle beat.
  generate
    if (PCLK_FALLING == 0) begin : g_posedge
      always @(posedge cam_pclk) begin
        if (cam_reset) begin
          byte_first_q       <= {DATA_WIDTH{1'b0}};
          byte_phase_q       <= 1'b0;
          pending_pixel_q    <= 32'h0;
          pending_valid_q    <= 1'b0;
          pending_sof_q      <= 1'b0;
          sof_pending_q      <= 1'b1;
          frame_seen_q       <= 1'b0;
          pixel_data         <= 32'h0;
          pixel_keep         <= DEFAULT_KEEP;
          pixel_valid        <= 1'b0;
          pixel_sof          <= 1'b0;
          pixel_eol          <= 1'b0;
          frame_active       <= 1'b0;
          partial_pixel_error<= 1'b0;
        end else begin
          pixel_valid <= 1'b0;
          pixel_sof   <= 1'b0;
          pixel_eol   <= 1'b0;

          if (pending_valid_q) begin
            pixel_data  <= pending_pixel_q;
            pixel_keep  <= DEFAULT_KEEP;
            pixel_valid <= enable;
            pixel_sof   <= pending_sof_q && enable;
            pixel_eol   <= (!href_active || vsync_active) && enable;
            pending_valid_q <= 1'b0;
          end

          if (!enable) begin
            byte_phase_q    <= 1'b0;
            pending_valid_q <= 1'b0;
            sof_pending_q   <= 1'b1;
            frame_seen_q    <= 1'b0;
            frame_active    <= 1'b0;
          end else if (vsync_active) begin
            byte_phase_q  <= 1'b0;
            sof_pending_q <= 1'b1;
            frame_seen_q  <= 1'b1;
            frame_active  <= 1'b0;
            if (pending_valid_q) pending_valid_q <= 1'b0;
          end else if (href_active) begin
            frame_active <= frame_seen_q | sof_pending_q;
            if (!byte_phase_q) begin
              byte_first_q <= cam_data;
              byte_phase_q <= 1'b1;
            end else begin
              pending_pixel_q <= {16'h0000, rgb565_word};
              pending_valid_q <= 1'b1;
              pending_sof_q   <= sof_pending_q;
              sof_pending_q   <= 1'b0;
              frame_seen_q    <= 1'b1;
              byte_phase_q    <= 1'b0;
            end
          end else begin
            if (byte_phase_q) partial_pixel_error <= 1'b1;
            byte_phase_q <= 1'b0;
            frame_active <= 1'b0;
          end
        end
      end
    end else begin : g_negedge
      always @(negedge cam_pclk) begin
        if (cam_reset) begin
          byte_first_q       <= {DATA_WIDTH{1'b0}};
          byte_phase_q       <= 1'b0;
          pending_pixel_q    <= 32'h0;
          pending_valid_q    <= 1'b0;
          pending_sof_q      <= 1'b0;
          sof_pending_q      <= 1'b1;
          frame_seen_q       <= 1'b0;
          pixel_data         <= 32'h0;
          pixel_keep         <= DEFAULT_KEEP;
          pixel_valid        <= 1'b0;
          pixel_sof          <= 1'b0;
          pixel_eol          <= 1'b0;
          frame_active       <= 1'b0;
          partial_pixel_error<= 1'b0;
        end else begin
          pixel_valid <= 1'b0;
          pixel_sof   <= 1'b0;
          pixel_eol   <= 1'b0;
          if (pending_valid_q) begin
            pixel_data  <= pending_pixel_q;
            pixel_keep  <= DEFAULT_KEEP;
            pixel_valid <= enable;
            pixel_sof   <= pending_sof_q && enable;
            pixel_eol   <= (!href_active || vsync_active) && enable;
            pending_valid_q <= 1'b0;
          end
          if (!enable) begin
            byte_phase_q <= 1'b0; pending_valid_q <= 1'b0;
            sof_pending_q <= 1'b1; frame_seen_q <= 1'b0; frame_active <= 1'b0;
          end else if (vsync_active) begin
            byte_phase_q <= 1'b0; sof_pending_q <= 1'b1;
            frame_seen_q <= 1'b1; frame_active <= 1'b0;
            if (pending_valid_q) pending_valid_q <= 1'b0;
          end else if (href_active) begin
            frame_active <= frame_seen_q | sof_pending_q;
            if (!byte_phase_q) begin byte_first_q <= cam_data; byte_phase_q <= 1'b1; end
            else begin
              pending_pixel_q <= {16'h0000, rgb565_word};
              pending_valid_q <= 1'b1; pending_sof_q <= sof_pending_q;
              sof_pending_q <= 1'b0; frame_seen_q <= 1'b1; byte_phase_q <= 1'b0;
            end
          end else begin
            if (byte_phase_q) partial_pixel_error <= 1'b1;
            byte_phase_q <= 1'b0; frame_active <= 1'b0;
          end
        end
      end
    end
  endgenerate
endmodule
