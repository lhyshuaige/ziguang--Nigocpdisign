`timescale 1ns/1ps

// First-phase INT8 accelerator.
//
// A descriptor treats the source as interleaved signed INT8 pairs
// (a0,b0,a1,b1, ...).  The engine computes sum(ai*bi) over LENGTH bytes,
// applies SCALE as signed Q8.8, and writes the signed 32-bit result in the low
// word of one 256-bit AXI beat.  This deliberately small kernel keeps the
// interface stable for a later parallel MAC implementation while making the
// complete CPU/AXI/IRQ data path executable now.
module pgl50h_ai_engine (
  input  wire        clk,
  input  wire        reset,
  input  wire        start,
  input  wire [31:0] control,
  input  wire [31:0] src_addr,
  input  wire [31:0] dst_addr,
  input  wire [31:0] length,
  input  wire [31:0] channels,
  input  wire [31:0] scale,
  output wire [31:0] status,
  output wire        done_irq,
  output wire        error_irq,

  output wire [3:0]  m_awid,
  output wire [31:0] m_awaddr,
  output wire [3:0]  m_awlen,
  output wire        m_awvalid,
  input  wire        m_awready,
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

  localparam [3:0] ST_IDLE      = 4'd0;
  localparam [3:0] ST_READ_CMD  = 4'd1;
  localparam [3:0] ST_READ_DATA = 4'd2;
  localparam [3:0] ST_WRITE_CMD = 4'd3;
  localparam [3:0] ST_WRITE_DATA = 4'd4;
  localparam [3:0] ST_WRITE_RESP = 4'd5;
  // Keep the AXI read handshake separate from the arithmetic pipeline.  The
  // original implementation evaluated the entire 16x INT8 dot product,
  // saturating accumulator and Q8.8 scale in the read-data cycle.  These
  // states insert explicit register boundaries without changing the bus
  // protocol or the descriptor-visible result.
  localparam [3:0] ST_DOT_CALC   = 4'd6;
  localparam [3:0] ST_ACCUM      = 4'd7;
  localparam [3:0] ST_SCALE      = 4'd8;

  reg [3:0] state;
  reg busy_reg;
  reg done_reg;
  reg error_reg;
  reg done_irq_reg;
  reg error_irq_reg;
  reg [31:0] control_q;
  reg [31:0] src_addr_q;
  reg [31:0] dst_addr_q;
  reg [31:0] length_q;
  reg [31:0] channels_q;
  reg [31:0] scale_q;
  reg [2:0] read_beats_total;
  reg [2:0] read_beat_index;
  reg [8:0] bytes_remaining;
  reg signed [31:0] accum_reg;
  reg signed [31:0] result_reg;
  reg [255:0] read_data_reg;
  reg [5:0] read_valid_bytes_reg;
  reg read_last_reg;
  reg signed [31:0] beat_dot_reg;

  reg signed [31:0] next_accum_tmp;

  function signed [31:0] dot_beat;
    input [255:0] beat;
    input integer valid_bytes;
    integer n;
    reg signed [7:0] va;
    reg signed [7:0] vb;
    reg signed [15:0] prod;
    reg signed [31:0] sum;
    begin
      sum = 32'sd0;
      for (n = 0; n < 16; n = n + 1) begin
        if ((n * 2 + 1) < valid_bytes) begin
          va = beat[(n * 2) * 8 +: 8];
          vb = beat[(n * 2 + 1) * 8 +: 8];
          prod = va * vb;
          sum = sum + {{16{prod[15]}}, prod};
        end
      end
      dot_beat = sum;
    end
  endfunction

  function signed [31:0] sat_add32;
    input signed [31:0] a;
    input signed [31:0] b;
    reg signed [32:0] sum;
    begin
      sum = a + b;
      if (!a[31] && !b[31] && sum[31])
        sat_add32 = 32'sh7fff_ffff;
      else if (a[31] && b[31] && !sum[31])
        sat_add32 = 32'sh8000_0000;
      else
        sat_add32 = sum[31:0];
    end
  endfunction

  function signed [31:0] apply_scale;
    input signed [31:0] value;
    input [31:0] scale_value;
    reg signed [63:0] product;
    reg signed [63:0] shifted;
    begin
      // SCALE is a signed Q8.8 multiplier.  In particular, zero is a valid
      // scale (it produces zero), while the reset value 0x0100 represents
      // unity.  Keep the multiply wide until the arithmetic shift so signed
      // negative activations and saturation are deterministic.
      product = value * $signed(scale_value[15:0]);
      shifted = product >>> 8;
      if (shifted > 64'sh0000_0000_7fff_ffff)
        apply_scale = 32'sh7fff_ffff;
      else if (shifted < 64'shffff_ffff_8000_0000)
        apply_scale = 32'sh8000_0000;
      else
        apply_scale = shifted[31:0];
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

  wire invalid_descriptor = (length == 0) || (length[0] != 1'b0) ||
                            (length > 32'd128) || (src_addr[4:0] != 0) ||
                            (dst_addr[4:0] != 0);

  assign status = {29'h0, error_reg, done_reg, busy_reg};
  assign done_irq = done_irq_reg;
  assign error_irq = error_irq_reg;

  assign m_arid = 4'h2;
  assign m_araddr = src_addr_q;
  assign m_arlen = (read_beats_total == 0) ? 4'd0 : (read_beats_total - 1'b1);
  assign m_arvalid = (state == ST_READ_CMD);
  assign m_rready = (state == ST_READ_DATA);

  assign m_awid = 4'h2;
  assign m_awaddr = dst_addr_q;
  assign m_awlen = 4'd0;
  assign m_awvalid = (state == ST_WRITE_CMD);
  assign m_wdata = {{224{1'b0}}, result_reg[31:0]};
  assign m_wstrb = 32'h0000_000f;
  assign m_wlast = 1'b1;
  assign m_wvalid = (state == ST_WRITE_DATA);
  assign m_bready = (state == ST_WRITE_RESP);

  always @(posedge clk) begin
    if (reset) begin
      state           <= ST_IDLE;
      busy_reg        <= 1'b0;
      done_reg        <= 1'b0;
      error_reg       <= 1'b0;
      done_irq_reg    <= 1'b0;
      error_irq_reg   <= 1'b0;
      control_q       <= 32'h0;
      src_addr_q      <= 32'h0;
      dst_addr_q      <= 32'h0;
      length_q        <= 32'h0;
      channels_q      <= 32'h0;
      scale_q         <= 32'h0000_0100;
      read_beats_total <= 3'd0;
      read_beat_index <= 3'd0;
      bytes_remaining <= 9'd0;
      accum_reg       <= 32'sd0;
      result_reg      <= 32'sd0;
      read_data_reg   <= 256'd0;
      read_valid_bytes_reg <= 6'd0;
      read_last_reg   <= 1'b0;
      beat_dot_reg    <= 32'sd0;
    end else begin
      done_irq_reg  <= 1'b0;
      error_irq_reg <= 1'b0;

      case (state)
        ST_IDLE: begin
          if (start) begin
            control_q  <= control;
            src_addr_q <= src_addr;
            dst_addr_q <= dst_addr;
            length_q   <= length;
            channels_q <= channels;
            scale_q    <= scale;
            done_reg   <= 1'b0;
            error_reg  <= 1'b0;
            busy_reg   <= 1'b0;
            if (invalid_descriptor) begin
              error_reg     <= 1'b1;
              error_irq_reg <= 1'b1;
              state         <= ST_IDLE;
            end else begin
              busy_reg         <= 1'b1;
              accum_reg        <= 32'sd0;
              read_beat_index  <= 3'd0;
              read_beats_total <= calc_beats(length);
              bytes_remaining  <= length[8:0];
              state            <= ST_READ_CMD;
            end
          end
        end

        ST_READ_CMD: begin
          if (m_arvalid && m_arready)
            state <= ST_READ_DATA;
        end

        ST_READ_DATA: begin
          if (m_rvalid && m_rready) begin
            if ((m_rid != 4'h2) || (m_rresp != 2'b00)) begin
              busy_reg      <= 1'b0;
              error_reg     <= 1'b1;
              error_irq_reg <= 1'b1;
              state         <= ST_IDLE;
            end else begin
              // Capture the AXI beat first.  This is the critical timing
              // boundary between the memory fabric and the AI arithmetic.
              read_data_reg <= m_rdata;
              read_valid_bytes_reg <= (bytes_remaining > 9'd32) ? 6'd32 :
                                     bytes_remaining[5:0];
              read_last_reg <= ((read_beat_index + 1'b1 >= read_beats_total) ||
                                m_rlast);
              state <= ST_DOT_CALC;
            end
          end
        end

        ST_DOT_CALC: begin
          // The 16 signed byte products and their reduction are now launched
          // from a local register rather than directly from AXI fabric data.
          beat_dot_reg <= dot_beat(read_data_reg, {26'd0, read_valid_bytes_reg});
          state <= ST_ACCUM;
        end

        ST_ACCUM: begin
          // A second boundary isolates saturating accumulation from the dot
          // product tree.  The old value is retained until this state exits,
          // so the last beat is included before scaling.
          next_accum_tmp = sat_add32(accum_reg, beat_dot_reg);
          accum_reg <= next_accum_tmp;
          if (read_last_reg) begin
            state <= ST_SCALE;
          end else begin
            read_beat_index <= read_beat_index + 1'b1;
            bytes_remaining <= bytes_remaining - 9'd32;
            // The read command already described the complete burst.  Keep
            // accepting the remaining R beats instead of issuing a second AR
            // (which would restart the backing memory at beat zero).
            state <= ST_READ_DATA;
          end
        end

        ST_SCALE: begin
          // Scale in its own cycle so the wide signed multiply does not share
          // a cycle with the dot-product or accumulation logic.
          result_reg <= apply_scale(accum_reg, scale_q);
          state <= ST_WRITE_CMD;
        end

        ST_WRITE_CMD: begin
          if (m_awvalid && m_awready)
            state <= ST_WRITE_DATA;
        end

        ST_WRITE_DATA: begin
          if (m_wvalid && m_wready)
            state <= ST_WRITE_RESP;
        end

        ST_WRITE_RESP: begin
          if (m_bvalid && m_bready) begin
            busy_reg <= 1'b0;
            if ((m_bid != 4'h2) || (m_bresp != 2'b00)) begin
              error_reg     <= 1'b1;
              error_irq_reg <= 1'b1;
              state         <= ST_IDLE;
            end else begin
              done_reg    <= 1'b1;
              done_irq_reg <= 1'b1;
              state       <= ST_IDLE;
            end
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
