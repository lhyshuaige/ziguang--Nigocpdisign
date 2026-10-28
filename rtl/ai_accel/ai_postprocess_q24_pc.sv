// Shared scalar per-output-channel Q24 requantization stage.
//
// The arithmetic contract is frozen to the validated host reference:
//   ((int64(accum) + bias) * multiplier + 2^23) >>> 24
// followed by activation and signed INT8 saturation.
//
// This implementation keeps one shared arithmetic unit, but separates the
// long combinational path into three elastic stages:
//   S1: accumulate + bias and capture quantization sideband
//   S2: signed/unsigned Q24 multiplication
//   S3: rounding, activation and INT8 saturation
// Each stage has valid/ready flow control, so a single unit can accept a new
// channel every cycle when the output is draining and can hold all metadata
// consistently during backpressure.
module ai_postprocess_q24_pc #(
  parameter integer CHANNEL_BITS = 16,
  // MobileNet Q24 multipliers are non-negative and bounded by 10,036,957;
  // the production adapter uses an unsigned 24-bit representation.  The
  // standalone unit keeps the original signed 32-bit interface by default.
  parameter integer MULTIPLIER_BITS = 32,
  parameter integer MULTIPLIER_UNSIGNED = 0
)(
  input  wire                         clk,
  input  wire                         rst_n,
  input  wire                         in_valid,
  output wire                         in_ready,
  input  wire signed [31:0]           in_accum,
  input  wire [CHANNEL_BITS-1:0]      in_channel,
  input  wire signed [31:0]           in_bias,
  input  wire signed [MULTIPLIER_BITS-1:0] in_multiplier_q24,
  input  wire                         in_relu,
  input  wire                         in_relu6,
  input  wire signed [7:0]            in_relu6_max,
  output wire                         out_valid,
  input  wire                         out_ready,
  output wire [CHANNEL_BITS-1:0]      out_channel,
  output wire signed [7:0]            out_value
);
  localparam integer SUM_BITS = 33;
  localparam integer ARITH_BITS = 33 + MULTIPLIER_BITS;
  localparam integer SCALED_BITS = (MULTIPLIER_UNSIGNED == 1) ? 33 : ARITH_BITS;
  localparam signed [ARITH_BITS-1:0] ROUND_CONST = 8388608;

  // Elastic pipeline valid bits. A stage may be overwritten when it is empty
  // or when the next stage consumes its current item in this cycle.
  reg s1_valid, s2_valid, s3_valid;
  wire s3_ready = ~s3_valid | out_ready;
  wire s2_ready = ~s2_valid | s3_ready;
  wire s1_ready = ~s1_valid | s2_ready;
  assign in_ready = s1_ready;
  assign out_valid = s3_valid;

  // S1: 33-bit sum plus all metadata.
  reg signed [SUM_BITS-1:0] sum_s1;
  reg signed [MULTIPLIER_BITS-1:0] multiplier_s1;
  reg [CHANNEL_BITS-1:0] channel_s1;
  reg relu_s1, relu6_s1;
  reg signed [7:0] relu6_max_s1;

  // S2: product and sideband captured together. Production multipliers are
  // zero extended; the standalone signed variant is sign extended.
  reg signed [ARITH_BITS-1:0] product_s2;
  reg [CHANNEL_BITS-1:0] channel_s2;
  reg relu_s2, relu6_s2;
  reg signed [7:0] relu6_max_s2;

  // S3/output slot.
  reg [CHANNEL_BITS-1:0] channel_q;
  reg signed [7:0] value_q;
  assign out_channel = channel_q;
  assign out_value = value_q;

  // S1 -> S2 multiplication cone. Explicit extension prevents Verilog
  // expression sizing from truncating the 33-bit accumulated sum.
  reg signed [ARITH_BITS-1:0] sum_s1_ext;
  reg signed [ARITH_BITS-1:0] multiplier_s1_ext;
  reg signed [ARITH_BITS-1:0] product_next;

  // S2 -> S3 rounding/activation cone.
  // The low 24 bits carry the rounding residue and are intentionally
  // discarded by the following Q24 shift.
  /* verilator lint_off UNUSEDSIGNAL */
  reg signed [ARITH_BITS-1:0] rounded_next;
  /* verilator lint_on UNUSEDSIGNAL */
  reg signed [SCALED_BITS-1:0] scaled_next;
  reg signed [SCALED_BITS-1:0] activated_next;
  reg signed [SCALED_BITS-1:0] relu6_max_next;
  reg signed [7:0] value_next;

  always @* begin
    sum_s1_ext = $signed({{(ARITH_BITS-SUM_BITS){sum_s1[SUM_BITS-1]}}, sum_s1});
    if (MULTIPLIER_UNSIGNED == 1)
      multiplier_s1_ext = $signed({{(ARITH_BITS-MULTIPLIER_BITS){1'b0}}, multiplier_s1});
    else
      multiplier_s1_ext = $signed({{(ARITH_BITS-MULTIPLIER_BITS){multiplier_s1[MULTIPLIER_BITS-1]}}, multiplier_s1});
    product_next = sum_s1_ext * multiplier_s1_ext;

    rounded_next = product_s2 + ROUND_CONST;
    scaled_next = $signed({{(SCALED_BITS-(ARITH_BITS-24)){rounded_next[ARITH_BITS-1]}},
                            rounded_next[ARITH_BITS-1:24]});
    activated_next = scaled_next;
    if (relu_s2 && (activated_next < 0))
      activated_next = 0;
    relu6_max_next = $signed({{(SCALED_BITS-8){relu6_max_s2[7]}}, relu6_max_s2});
    if (relu6_s2 && (activated_next > relu6_max_next))
      activated_next = relu6_max_next;
    if (activated_next > 127)
      value_next = 8'sh7f;
    else if (activated_next < -128)
      value_next = -8'sd128;
    else
      value_next = activated_next[7:0];
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_valid <= 1'b0;
      s2_valid <= 1'b0;
      s3_valid <= 1'b0;
      sum_s1 <= {SUM_BITS{1'b0}};
      multiplier_s1 <= {MULTIPLIER_BITS{1'b0}};
      channel_s1 <= {CHANNEL_BITS{1'b0}};
      relu_s1 <= 1'b0;
      relu6_s1 <= 1'b0;
      relu6_max_s1 <= 8'sd0;
      product_s2 <= {ARITH_BITS{1'b0}};
      channel_s2 <= {CHANNEL_BITS{1'b0}};
      relu_s2 <= 1'b0;
      relu6_s2 <= 1'b0;
      relu6_max_s2 <= 8'sd0;
      channel_q <= {CHANNEL_BITS{1'b0}};
      value_q <= 8'sd0;
    end else begin
      // S3/output slot: consume when ready, otherwise hold data and metadata.
      if (s3_ready) begin
        s3_valid <= s2_valid;
        if (s2_valid) begin
          channel_q <= channel_s2;
          value_q <= value_next;
        end
      end

      // S2 product register. This is independent of S3 arithmetic, allowing
      // multiplier and activation cones to occupy separate cycles.
      if (s2_ready) begin
        s2_valid <= s1_valid;
        if (s1_valid) begin
          product_s2 <= product_next;
          channel_s2 <= channel_s1;
          relu_s2 <= relu_s1;
          relu6_s2 <= relu6_s1;
          relu6_max_s2 <= relu6_max_s1;
        end
      end

      // S1 input register. Explicit 33-bit operands preserve the exact
      // two's-complement sum used by the previous monolithic implementation.
      if (s1_ready) begin
        s1_valid <= in_valid;
        if (in_valid) begin
          sum_s1 <= $signed({in_accum[31], in_accum}) +
                    $signed({in_bias[31], in_bias});
          multiplier_s1 <= in_multiplier_q24;
          channel_s1 <= in_channel;
          relu_s1 <= in_relu;
          relu6_s1 <= in_relu6;
          relu6_max_s1 <= in_relu6_max;
        end
      end
    end
  end
endmodule
