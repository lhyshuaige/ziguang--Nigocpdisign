// Shared postprocess arithmetic. One 33-bit bias adder and one shift network
// per lane are shared by GEMM and convolution. Outputs stay separate because
// PDS maps the INT8 and INT32 saturation widths more efficiently this way.
module ai_postprocess_v1 #(
  parameter integer LANES=8
)(
  input wire [LANES*32-1:0] accum,bias,
  input wire gemm,
  input wire signed [5:0] shift,
  input wire relu,relu6,
  input wire signed [7:0] relu6_max,
  output wire [LANES*8-1:0] result8,
  output wire [LANES*32-1:0] result32
);
  wire [LANES*33-1:0] biased;
  genvar b;
  generate for(b=0;b<LANES;b=b+1)begin:g_bias
    wire signed [31:0] a=accum[b*32+:32], bi=bias[b*32+:32];
    assign biased[b*33+:33]=$signed({a[31],a})+$signed({bi[31],bi});
  end endgenerate
  ai_postprocess_shift_v1 #(.LANES(LANES)) shift_i (
    .biased(biased), .gemm(gemm), .shift(shift), .relu(relu),
    .relu6(relu6), .relu6_max(relu6_max),
    .precomputed_left(1'b0), .precomputed_amount(6'd0),
    .precomputed_relu6_zero(1'b0),
    .result8(result8), .result32(result32)
  );
endmodule

// The original combinational interface above is unchanged (including PSUM).
// The compute core registers the full signed 33-bit Bias sum before invoking
// this same arithmetic. No change to shift width, rounding or saturation.
/* verilator lint_off DECLFILENAME */
module ai_postprocess_shift_v1 #(
  parameter integer LANES=8,
  // Core uses the existing post-sum register boundary to supply these
  // controls.  The PSUM wrapper leaves this disabled and keeps its legacy
  // gemm/shift interface unchanged.
  parameter PRECOMPUTED_CTRL=1'b0,
  // Core only consumes result8 for convolution (arithmetic right shift).
  // Its GEMM path consumes result32. Keep the general interface unchanged
  // by default, and omit the unused left-shift selection from pixel data
  // only when a caller explicitly guarantees that contract.
  parameter RIGHT_ONLY_PIXEL=1'b0,
  // The caller may perform these low right-shift bits before its existing
  // biased-data register. Left shift always retains the original amount.
  parameter integer RIGHT_SHIFT_LOW_BITS=0
)(
  input wire [LANES*33-1:0] biased,
  input wire gemm,
  input wire signed [5:0] shift,
  input wire relu,relu6,
  input wire signed [7:0] relu6_max,
  input wire precomputed_left,
  input wire [5:0] precomputed_amount,
  input wire precomputed_relu6_zero,
  output wire [LANES*8-1:0] result8,
  output wire [LANES*32-1:0] result32
);
  // PRECOMPUTED_CTRL is an elaboration-time constant.  For the Core
  // instance, post_gemm_q and post_shift_q therefore do not enter this
  // combinational network; PSUM retains the original calculation.
  wire left=PRECOMPUTED_CTRL ? precomputed_left : (gemm && shift[5]);
  wire [5:0] amount=PRECOMPUTED_CTRL ? precomputed_amount
                                     : (left ? (~shift+6'd1)
                                             : {1'b0,shift[4:0]});
  wire relu6_zero=PRECOMPUTED_CTRL ? precomputed_relu6_zero
                                   : (!gemm && relu6);
  wire [32:0] overflow_mask=33'h1ffffffff << (5'd31-amount[4:0]);
  genvar lane;
  generate for(lane=0;lane<LANES;lane=lane+1)begin:g_lane
    wire signed [32:0] sum=biased[lane*33+:33];
    // Let the synthesizer infer one signed variable shifter for each
    // direction.  This is bit-equivalent to the explicit reverse/barrel
    // network, while avoiding the reverse bus and six hand-built mux levels
    // on the Legacy postprocess path.  The left shift remains a 33-bit
    // truncating shift; the right shift is arithmetic and sign-filling.
    wire signed [32:0] scaled_left = sum <<< amount;
    wire [5:0] right_amount=amount & (6'h3f << RIGHT_SHIFT_LOW_BITS);
    wire signed [32:0] scaled_right = sum >>> right_amount;
    wire [32:0] scaled = left ? scaled_left : scaled_right;
    wire left_overflow=left && (amount[5] ? (sum!=0)
       : (|((sum^{33{sum[32]}})&overflow_mask)));
    wire overflow32=left?left_overflow:(scaled[32]!=scaled[31]);
    wire [31:0] saturated32=overflow32
       ? (sum[32]?32'h80000000:32'h7fffffff) : scaled[31:0];
    wire [32:0] pixel_scaled=RIGHT_ONLY_PIXEL ? scaled_right : scaled;
    wire fits8=(pixel_scaled[32:7]=={26{pixel_scaled[7]}});
    wire signed [7:0] saturated8=fits8?pixel_scaled[7:0]
       :(pixel_scaled[32]?8'h80:8'h7f);
    wire zero_negative=(relu || relu6_zero) && sum[32];
    wire signed [7:0] activated8=zero_negative?8'sd0:saturated8;
    assign result8[lane*8+:8]=(relu6 && activated8>relu6_max)
       ? relu6_max : activated8;
    assign result32[lane*32+:32]=zero_negative?32'd0:saturated32;
  end endgenerate
endmodule
/* verilator lint_on DECLFILENAME */
