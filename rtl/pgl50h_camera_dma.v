`timescale 1ns/1ps

// Camera/DMA master, first phase.
//
// Memory mode moves one descriptor of up to four 256-bit beats.  Reads are
// collected in a fixed four-entry FIFO before the registered write burst is
// issued, so source backpressure never combinationally drives write data.
// `stride` is captured as part of the stable CSR contract; contiguous DDR
// transfers use a zero stride today and a later camera-line mode can consume
// the same descriptor without changing the AXI interface.
module pgl50h_camera_dma_legacy (
  input  wire        clk,
  input  wire        reset,
  input  wire        start,
  input  wire [31:0] control,
  input  wire [31:0] src_addr,
  input  wire [31:0] dst_addr,
  input  wire [31:0] length,
  input  wire [31:0] stride,
  output wire [31:0] status,
  output wire        done_irq,
  output wire        error_irq,

  input  wire        pixel_valid,
  output wire        pixel_ready,
  input  wire [31:0] pixel_data,
  input  wire        pixel_sof,
  input  wire        pixel_eol,

  output wire [3:0]   m_awid,
  output wire [31:0]  m_awaddr,
  output wire [3:0]   m_awlen,
  output wire         m_awvalid,
  input  wire         m_awready,
  output wire [255:0] m_wdata,
  output wire [31:0]  m_wstrb,
  output wire         m_wlast,
  output wire         m_wvalid,
  input  wire         m_wready,
  input  wire [3:0]   m_bid,
  input  wire [1:0]   m_bresp,
  input  wire         m_bvalid,
  output wire         m_bready,
  output wire [3:0]   m_arid,
  output wire [31:0]  m_araddr,
  output wire [3:0]   m_arlen,
  output wire         m_arvalid,
  input  wire         m_arready,
  input  wire [3:0]   m_rid,
  input  wire [255:0] m_rdata,
  input  wire [1:0]   m_rresp,
  input  wire         m_rlast,
  input  wire         m_rvalid,
  output wire         m_rready
);

  localparam [3:0] ST_IDLE       = 4'd0;
  localparam [3:0] ST_READ_CMD   = 4'd1;
  localparam [3:0] ST_READ_DATA  = 4'd2;
  localparam [3:0] ST_WRITE_CMD  = 4'd3;
  localparam [3:0] ST_WRITE_DATA = 4'd4;
  localparam [3:0] ST_WRITE_RESP = 4'd5;

  reg [3:0] state;
  reg busy_reg, done_reg, error_reg;
  reg done_irq_reg, error_irq_reg;
  reg [31:0] control_q, src_addr_q, dst_addr_q, length_q, stride_q;
  reg [2:0] burst_beats;
  reg [2:0] read_count;
  reg [2:0] write_count;
  reg [8:0] bytes_remaining;

  reg [255:0] fifo_data [0:3];
  reg [31:0] fifo_strb [0:3];
  reg fifo_last [0:3];
  reg [1:0] fifo_head, fifo_tail;
  reg [2:0] fifo_count;
  integer i;

  function [31:0] byte_mask;
    input [5:0] byte_count;
    begin
      if (byte_count >= 6'd32)
        byte_mask = 32'hffff_ffff;
      else if (byte_count == 0)
        byte_mask = 32'h0000_0000;
      else
        byte_mask = (32'h0000_0001 << byte_count) - 1'b1;
    end
  endfunction

  function [2:0] calc_beats;
    input [31:0] byte_count;
    begin
      if (byte_count == 0)
        calc_beats = 3'd0;
      else if (byte_count <= 32)
        calc_beats = 3'd1;
      else if (byte_count <= 64)
        calc_beats = 3'd2;
      else if (byte_count <= 96)
        calc_beats = 3'd3;
      else
        calc_beats = 3'd4;
    end
  endfunction

  wire invalid_descriptor = (length == 0) || (length > 32'd128) ||
                            (src_addr[4:0] != 0) || (dst_addr[4:0] != 0);
  wire [5:0] current_bytes = (bytes_remaining > 9'd32) ? 6'd32 : bytes_remaining[5:0];

  assign status = {29'h0, error_reg, done_reg, busy_reg};
  assign done_irq = done_irq_reg;
  assign error_irq = error_irq_reg;
  assign pixel_ready = 1'b0;

  assign m_arid = 4'h3;
  assign m_araddr = src_addr_q;
  assign m_arlen = (burst_beats == 0) ? 4'd0 : (burst_beats - 1'b1);
  assign m_arvalid = (state == ST_READ_CMD);
  assign m_rready = (state == ST_READ_DATA) && (fifo_count < 4);

  assign m_awid = 4'h3;
  assign m_awaddr = dst_addr_q;
  assign m_awlen = (burst_beats == 0) ? 4'd0 : (burst_beats - 1'b1);
  assign m_awvalid = (state == ST_WRITE_CMD);
  assign m_wdata = (fifo_count != 0) ? fifo_data[fifo_head] : 256'h0;
  assign m_wstrb = (fifo_count != 0) ? fifo_strb[fifo_head] : 32'h0;
  assign m_wlast = (fifo_count != 0) ? fifo_last[fifo_head] : 1'b0;
  assign m_wvalid = (state == ST_WRITE_DATA) && (fifo_count != 0);
  assign m_bready = (state == ST_WRITE_RESP);

  always @(posedge clk) begin
    if (reset) begin
      state <= ST_IDLE;
      busy_reg <= 1'b0;
      done_reg <= 1'b0;
      error_reg <= 1'b0;
      done_irq_reg <= 1'b0;
      error_irq_reg <= 1'b0;
      control_q <= 32'h0;
      src_addr_q <= 32'h0;
      dst_addr_q <= 32'h0;
      length_q <= 32'h0;
      stride_q <= 32'h0;
      burst_beats <= 3'd0;
      read_count <= 3'd0;
      write_count <= 3'd0;
      bytes_remaining <= 9'd0;
      fifo_head <= 2'd0;
      fifo_tail <= 2'd0;
      fifo_count <= 3'd0;
      for (i = 0; i < 4; i = i + 1) begin
        fifo_data[i] <= 256'h0;
        fifo_strb[i] <= 32'h0;
        fifo_last[i] <= 1'b0;
      end
    end else begin
      done_irq_reg <= 1'b0;
      error_irq_reg <= 1'b0;

      case (state)
        ST_IDLE: begin
          if (start) begin
            control_q <= control;
            src_addr_q <= src_addr;
            dst_addr_q <= dst_addr;
            length_q <= length;
            stride_q <= stride;
            done_reg <= 1'b0;
            error_reg <= 1'b0;
            busy_reg <= 1'b0;
            fifo_head <= 2'd0;
            fifo_tail <= 2'd0;
            fifo_count <= 3'd0;
            if (invalid_descriptor) begin
              error_reg <= 1'b1;
              error_irq_reg <= 1'b1;
              state <= ST_IDLE;
            end else begin
              busy_reg <= 1'b1;
              burst_beats <= calc_beats(length);
              read_count <= 3'd0;
              write_count <= 3'd0;
              bytes_remaining <= length[8:0];
              state <= ST_READ_CMD;
            end
          end
        end

        ST_READ_CMD: begin
          if (m_arvalid && m_arready)
            state <= ST_READ_DATA;
        end

        ST_READ_DATA: begin
          if (m_rvalid && m_rready) begin
            if ((m_rid != 4'h3) || (m_rresp != 2'b00)) begin
              busy_reg <= 1'b0;
              error_reg <= 1'b1;
              error_irq_reg <= 1'b1;
              state <= ST_IDLE;
            end else begin
              fifo_data[fifo_tail] <= m_rdata;
              fifo_strb[fifo_tail] <= byte_mask(current_bytes);
              fifo_last[fifo_tail] <= (read_count + 1'b1 >= burst_beats) || m_rlast;
              fifo_tail <= fifo_tail + 1'b1;
              fifo_count <= fifo_count + 1'b1;
              read_count <= read_count + 1'b1;
              if (bytes_remaining > 9'd32) bytes_remaining <= bytes_remaining - 9'd32;
              else bytes_remaining <= 9'd0;
              if ((read_count + 1'b1 >= burst_beats) || m_rlast)
                state <= ST_WRITE_CMD;
            end
          end
        end

        ST_WRITE_CMD: begin
          if (m_awvalid && m_awready)
            state <= ST_WRITE_DATA;
        end

        ST_WRITE_DATA: begin
          if (m_wvalid && m_wready) begin
            fifo_head <= fifo_head + 1'b1;
            fifo_count <= fifo_count - 1'b1;
            write_count <= write_count + 1'b1;
            if (m_wlast)
              state <= ST_WRITE_RESP;
          end
        end

        ST_WRITE_RESP: begin
          if (m_bvalid && m_bready) begin
            busy_reg <= 1'b0;
            if ((m_bid != 4'h3) || (m_bresp != 2'b00)) begin
              error_reg <= 1'b1;
              error_irq_reg <= 1'b1;
              state <= ST_IDLE;
            end else begin
              done_reg <= 1'b1;
              done_irq_reg <= 1'b1;
              state <= ST_IDLE;
            end
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

  // Keep the reserved camera stream inputs explicit until the camera front
  // end is attached; memory mode is the only active path in this revision.
  wire unused_camera = pixel_valid ^ pixel_data[0] ^ pixel_sof ^ pixel_eol;

endmodule

// Compatibility wrapper.  Mode 00 preserves the original memory-to-memory
// DMA exactly; modes 01/10/11 use the stream-capable extension while keeping
// the same AXI master slot and CSR-visible top-level DMA instance.
module pgl50h_camera_dma (
  input  wire        clk,
  input  wire        reset,
  input  wire        start,
  input  wire [31:0] control,
  input  wire [31:0] src_addr,
  input  wire [31:0] dst_addr,
  input  wire [31:0] length,
  input  wire [31:0] stride,
  input  wire [31:0] src_stride,
  input  wire [31:0] dst_stride,
  input  wire [31:0] image_width,
  input  wire [31:0] image_height,
  input  wire [31:0] output_width,
  input  wire [31:0] output_height,
  output wire [31:0] status,
  output wire        done_irq,
  output wire        error_irq,

  input  wire        pixel_valid,
  output wire        pixel_ready,
  input  wire [31:0] pixel_data,
  input  wire        pixel_sof,
  input  wire        pixel_eol,

  output wire [31:0] m_axis_tdata,
  output wire [3:0]   m_axis_tkeep,
  output wire         m_axis_tvalid,
  input  wire         m_axis_tready,
  output wire         m_axis_tlast,
  output wire         m_axis_tuser,
  input  wire [31:0]  s_axis_tdata,
  input  wire [3:0]   s_axis_tkeep,
  input  wire         s_axis_tvalid,
  output wire         s_axis_tready,
  input  wire         s_axis_tlast,
  input  wire         s_axis_tuser,

  output wire [3:0]   m_awid,
  output wire [31:0]  m_awaddr,
  output wire [3:0]   m_awlen,
  output wire         m_awvalid,
  input  wire         m_awready,
  output wire [255:0] m_wdata,
  output wire [31:0]  m_wstrb,
  output wire         m_wlast,
  output wire         m_wvalid,
  input  wire         m_wready,
  input  wire [3:0]   m_bid,
  input  wire [1:0]   m_bresp,
  input  wire         m_bvalid,
  output wire         m_bready,
  output wire [3:0]   m_arid,
  output wire [31:0]  m_araddr,
  output wire [3:0]   m_arlen,
  output wire         m_arvalid,
  input  wire         m_arready,
  input  wire [3:0]   m_rid,
  input  wire [255:0] m_rdata,
  input  wire [1:0]   m_rresp,
  input  wire         m_rlast,
  input  wire         m_rvalid,
  output wire         m_rready
);
  wire stream_mode = (control[2:1] != 2'b00);

  // Capture the stream descriptor before resolving the legacy stride alias.
  // The pending bit is visible as busy so CSR writes cannot change a
  // descriptor between capture and the stream engine's start edge.
  localparam [1:0] CFG_IDLE = 2'd0;
  localparam [1:0] CFG_RESOLVE = 2'd1;
  localparam [1:0] CFG_ISSUE = 2'd2;
  localparam [1:0] CFG_WAIT = 2'd3;
  reg [1:0] stream_cfg_state;
  reg stream_start_q;
  reg [1:0] stream_mode_q;
  reg [31:0] stream_src_addr_q, stream_dst_addr_q;
  reg [31:0] stream_src_stride_raw_q, stream_legacy_stride_q;
  reg [31:0] stream_src_stride_effective_q, stream_dst_stride_q;
  reg [31:0] stream_src_width_q, stream_src_height_q;
  reg [31:0] stream_dst_width_q, stream_dst_height_q;
  wire stream_cfg_pending = (stream_cfg_state != CFG_IDLE);

  always @(posedge clk) begin
    if (reset) begin
      stream_cfg_state <= CFG_IDLE;
      stream_start_q <= 1'b0;
      stream_mode_q <= 2'b00;
      stream_src_addr_q <= 32'b0;
      stream_dst_addr_q <= 32'b0;
      stream_src_stride_raw_q <= 32'b0;
      stream_legacy_stride_q <= 32'b0;
      stream_src_stride_effective_q <= 32'b0;
      stream_dst_stride_q <= 32'b0;
      stream_src_width_q <= 32'b0;
      stream_src_height_q <= 32'b0;
      stream_dst_width_q <= 32'b0;
      stream_dst_height_q <= 32'b0;
    end else begin
      stream_start_q <= 1'b0;
      case (stream_cfg_state)
        CFG_IDLE: if (start && stream_mode && !stream_status[0]) begin
          stream_mode_q <= control[2:1];
          stream_src_addr_q <= src_addr;
          stream_dst_addr_q <= dst_addr;
          stream_src_stride_raw_q <= src_stride;
          stream_legacy_stride_q <= stride;
          stream_dst_stride_q <= dst_stride;
          stream_src_width_q <= image_width;
          stream_src_height_q <= image_height;
          stream_dst_width_q <= output_width;
          stream_dst_height_q <= output_height;
          stream_cfg_state <= CFG_RESOLVE;
        end
        CFG_RESOLVE: begin
          stream_src_stride_effective_q <=
              (stream_src_stride_raw_q != 0) ? stream_src_stride_raw_q : stream_legacy_stride_q;
          stream_cfg_state <= CFG_ISSUE;
        end
        CFG_ISSUE: begin
          stream_start_q <= 1'b1;
          stream_cfg_state <= CFG_WAIT;
        end
        CFG_WAIT: stream_cfg_state <= CFG_IDLE;
        default: stream_cfg_state <= CFG_IDLE;
      endcase
    end
  end

  wire [31:0] legacy_status;
  wire legacy_done_irq, legacy_error_irq;
  wire [3:0] legacy_awid, legacy_awlen, legacy_bid, legacy_arid, legacy_arlen, legacy_rid;
  wire [31:0] legacy_awaddr, legacy_araddr;
  wire [255:0] legacy_wdata, legacy_rdata;
  wire [31:0] legacy_wstrb;
  wire legacy_awvalid, legacy_awready, legacy_wlast, legacy_wvalid, legacy_wready;
  wire legacy_bvalid, legacy_bready, legacy_arvalid, legacy_arready, legacy_rlast, legacy_rvalid, legacy_rready;
  wire [1:0] legacy_bresp, legacy_rresp;

  wire [31:0] stream_status;
  wire stream_done_irq, stream_error_irq;
  wire [3:0] stream_awid, stream_awlen, stream_bid, stream_arid, stream_arlen, stream_rid;
  wire [31:0] stream_awaddr, stream_araddr;
  wire [255:0] stream_wdata, stream_rdata;
  wire [31:0] stream_wstrb;
  wire stream_awvalid, stream_awready, stream_wlast, stream_wvalid, stream_wready;
  wire stream_bvalid, stream_bready, stream_arvalid, stream_arready, stream_rlast, stream_rvalid, stream_rready;
  wire [1:0] stream_bresp, stream_rresp;

  pgl50h_camera_dma_legacy u_legacy (
    .clk(clk), .reset(reset), .start(start && !stream_mode), .control(control),
    .src_addr(src_addr), .dst_addr(dst_addr), .length(length), .stride(stride),
    .status(legacy_status), .done_irq(legacy_done_irq), .error_irq(legacy_error_irq),
    .pixel_valid(pixel_valid), .pixel_ready(pixel_ready), .pixel_data(pixel_data),
    .pixel_sof(pixel_sof), .pixel_eol(pixel_eol),
    .m_awid(legacy_awid), .m_awaddr(legacy_awaddr), .m_awlen(legacy_awlen), .m_awvalid(legacy_awvalid), .m_awready(legacy_awready),
    .m_wdata(legacy_wdata), .m_wstrb(legacy_wstrb), .m_wlast(legacy_wlast), .m_wvalid(legacy_wvalid), .m_wready(legacy_wready),
    .m_bid(legacy_bid), .m_bresp(legacy_bresp), .m_bvalid(legacy_bvalid), .m_bready(legacy_bready),
    .m_arid(legacy_arid), .m_araddr(legacy_araddr), .m_arlen(legacy_arlen), .m_arvalid(legacy_arvalid), .m_arready(legacy_arready),
    .m_rid(legacy_rid), .m_rdata(legacy_rdata), .m_rresp(legacy_rresp), .m_rlast(legacy_rlast), .m_rvalid(legacy_rvalid), .m_rready(legacy_rready)
  );

  pgl50h_camera_dma_stream u_stream (
    .clk(clk), .reset(reset), .start(stream_start_q), .mode(stream_mode_q),
    .src_addr(stream_src_addr_q), .dst_addr(stream_dst_addr_q),
    .src_stride(stream_src_stride_effective_q), .dst_stride(stream_dst_stride_q),
    .src_width(stream_src_width_q), .src_height(stream_src_height_q),
    .dst_width(stream_dst_width_q), .dst_height(stream_dst_height_q),
    .status(stream_status), .done_irq(stream_done_irq), .error_irq(stream_error_irq),
    .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast), .m_axis_tuser(m_axis_tuser),
    .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast), .s_axis_tuser(s_axis_tuser),
    .m_awid(stream_awid), .m_awaddr(stream_awaddr), .m_awlen(stream_awlen), .m_awvalid(stream_awvalid), .m_awready(stream_awready),
    .m_wdata(stream_wdata), .m_wstrb(stream_wstrb), .m_wlast(stream_wlast), .m_wvalid(stream_wvalid), .m_wready(stream_wready),
    .m_bid(stream_bid), .m_bresp(stream_bresp), .m_bvalid(stream_bvalid), .m_bready(stream_bready),
    .m_arid(stream_arid), .m_araddr(stream_araddr), .m_arlen(stream_arlen), .m_arvalid(stream_arvalid), .m_arready(stream_arready),
    .m_rid(stream_rid), .m_rdata(stream_rdata), .m_rresp(stream_rresp), .m_rlast(stream_rlast), .m_rvalid(stream_rvalid), .m_rready(stream_rready)
  );

  assign status = stream_mode ? (stream_status | {31'b0, stream_cfg_pending}) : legacy_status;
  assign done_irq = stream_mode ? stream_done_irq : legacy_done_irq;
  assign error_irq = stream_mode ? stream_error_irq : legacy_error_irq;
  // The existing DMA stores one 32-bit word per pixel.  Keep all four byte
  // lanes valid until packed-frame support is explicitly enabled.
  assign m_axis_tkeep = 4'b1111;

  assign m_awid = stream_mode ? stream_awid : legacy_awid;
  assign m_awaddr = stream_mode ? stream_awaddr : legacy_awaddr;
  assign m_awlen = stream_mode ? stream_awlen : legacy_awlen;
  assign m_awvalid = stream_mode ? stream_awvalid : legacy_awvalid;
  assign m_wdata = stream_mode ? stream_wdata : legacy_wdata;
  assign m_wstrb = stream_mode ? stream_wstrb : legacy_wstrb;
  assign m_wlast = stream_mode ? stream_wlast : legacy_wlast;
  assign m_wvalid = stream_mode ? stream_wvalid : legacy_wvalid;
  assign m_bready = stream_mode ? stream_bready : legacy_bready;
  assign m_arid = stream_mode ? stream_arid : legacy_arid;
  assign m_araddr = stream_mode ? stream_araddr : legacy_araddr;
  assign m_arlen = stream_mode ? stream_arlen : legacy_arlen;
  assign m_arvalid = stream_mode ? stream_arvalid : legacy_arvalid;
  assign m_rready = stream_mode ? stream_rready : legacy_rready;

  assign legacy_awready = (!stream_mode) ? m_awready : 1'b0;
  assign legacy_wready = (!stream_mode) ? m_wready : 1'b0;
  assign legacy_bid = m_bid;
  assign legacy_bresp = m_bresp;
  assign legacy_bvalid = (!stream_mode) ? m_bvalid : 1'b0;
  assign legacy_arready = (!stream_mode) ? m_arready : 1'b0;
  assign legacy_rid = m_rid;
  assign legacy_rdata = m_rdata;
  assign legacy_rresp = m_rresp;
  assign legacy_rlast = m_rlast;
  assign legacy_rvalid = (!stream_mode) ? m_rvalid : 1'b0;

  assign stream_awready = stream_mode ? m_awready : 1'b0;
  assign stream_wready = stream_mode ? m_wready : 1'b0;
  assign stream_bid = m_bid;
  assign stream_bresp = m_bresp;
  assign stream_bvalid = stream_mode ? m_bvalid : 1'b0;
  assign stream_arready = stream_mode ? m_arready : 1'b0;
  assign stream_rid = m_rid;
  assign stream_rdata = m_rdata;
  assign stream_rresp = m_rresp;
  assign stream_rlast = m_rlast;
  assign stream_rvalid = stream_mode ? m_rvalid : 1'b0;
endmodule
