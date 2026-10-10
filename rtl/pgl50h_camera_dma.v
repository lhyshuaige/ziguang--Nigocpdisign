`timescale 1ns/1ps

// Camera/DMA master, first phase.
//
// Memory mode moves one descriptor of up to four 256-bit beats.  Reads are
// collected in a fixed four-entry FIFO before the registered write burst is
// issued, so source backpressure never combinationally drives write data.
// `stride` is captured as part of the stable CSR contract; contiguous DDR
// transfers use a zero stride today and a later camera-line mode can consume
// the same descriptor without changing the AXI interface.
module pgl50h_camera_dma (
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
