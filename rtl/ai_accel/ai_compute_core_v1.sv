// Unified compute core.  One 8-lane INT8 MAC datapath is selected by cfg_mode:
// DW3x3, fused DW3x3->PW1x1, regular 3x3, PW1x1, or packed GEMM/1x1.
// The GEMM mode is the Phase 1C record consumer; convolution modes use the
// line-buffer/window frontend below.  The legacy ai_conv8_v2 compatibility
// wrapper is defined at the end of this file.
module ai_compute_core_v1 #(
  parameter integer LANES = 8,
  parameter integer MAX_WIDTH = 32,
  parameter integer MAX_HEIGHT = 32,
  parameter integer MAX_K = 256
) (
  input  wire                     clk,
  input  wire                     rst_n,
  input  wire                     weight_valid,
  output wire                     weight_ready,
  input  wire [6:0]               weight_addr,
  input  wire [LANES*8-1:0]       weight_data,
  input  wire                     cfg_valid,
  output wire                     cfg_ready,
  input  wire [2:0]               cfg_mode,
  input  wire [15:0]              cfg_k,
  input  wire [5:0]               cfg_width,
  input  wire [5:0]               cfg_height,
  input  wire                     cfg_pad_same,
  input  wire                     cfg_stride2,
  input  wire [3:0]               cfg_in_channels,
  input  wire [3:0]               cfg_out_channels,
  input  wire [LANES*32-1:0]      cfg_stage0_bias,
  input  wire [LANES*32-1:0]      cfg_stage1_bias,
  input  wire [4:0]               cfg_stage0_shift,
  input  wire [4:0]               cfg_stage1_shift,
  input  wire signed [5:0]        cfg_gemm_shift,
  input  wire                     cfg_stage0_relu,
  input  wire                     cfg_stage1_relu,
  input  wire                     cfg_stage0_relu6,
  input  wire                     cfg_stage1_relu6,
  input  wire signed [7:0]        cfg_stage0_relu6_max,
  input  wire signed [7:0]        cfg_stage1_relu6_max,
  input  wire                     in_valid,
  output wire                     in_ready,
  // Convolution modes use the low LANES*8 bits as a pixel.  GEMM mode uses
  // the full token: byte 0 is the activation and bytes 1..LANES are weights.
  input  wire [LANES*9-1:0]       in_token,
  output wire                     out_valid,
  input  wire                     out_ready,
  output wire [LANES*8-1:0]       out_pixel,
  // One output transaction for all modes. The legacy pixel output is a view.
  output wire [LANES*32-1:0]      out_data,
  // Raw INT32 accumulator before bias/shift/activation. Phase 3 channel
  // tiling uses this value for cross-input-channel partial sums; existing
  // clients may leave the port unconnected.
  output wire [LANES*32-1:0]      out_accum,
  output reg  [5:0]               out_x,
  output reg  [5:0]               out_y,
  output reg                      done,
  output reg                      error,
  output wire                     busy,
  output reg  [63:0]              perf_mac_count,
  output reg  [63:0]              perf_busy_cycles,
  output reg  [63:0]              perf_input_stall_cycles,
  output reg  [63:0]              perf_output_stall_cycles
);
  localparam integer PIX_BITS=LANES*8;
  localparam integer WEIGHT_DEPTH=9*LANES;
  localparam [5:0] MAX_WIDTH_U=MAX_WIDTH[5:0], MAX_HEIGHT_U=MAX_HEIGHT[5:0];
  localparam [3:0] LANES_U=LANES[3:0];
  localparam [6:0] WEIGHT_DEPTH_U=WEIGHT_DEPTH[6:0];
  localparam [15:0] MAX_K_U=MAX_K[15:0];
  localparam [2:0] MODE_DW=0, MODE_FUSED=1, MODE_REGULAR=2,
                   MODE_PW=3, MODE_GEMM=4;
  localparam [3:0] C_IDLE=0, C_DW=1, C_QUANT=2, C_PW=3,
                   C_REGULAR=4, C_OUT=5, C_GEMM=6, C_DW_QUANT=7, C_FUSED_FIRST=8;
  reg [3:0] state_q;
  reg frame_active_q, line_complete_q;
  reg [2:0] mode_q;
  // Quantization configuration is selected at frame setup (and at the
  // DW-to-PW boundary for fused mode).  Keeping this selector in a register
  // removes state_q from the Legacy postprocess data path.
  reg quant_stage0_q;
  reg [3:0] in_channels_q, out_channels_q;
  reg [15:0] gemm_k_q, gemm_index_q;
  // Timing-8: isolate input RAM/bank/token selection from the shared MAC.
  // GEMM always consumes this entry in one cycle; simultaneous consume and
  // refill preserve one token/cycle. gemm_index_q counts accepted inputs,
  // while the final tag travels with the buffered token to MAC completion.
  wire [LANES*9-1:0] gemm_token_q = {mac_b_q,mac_a_q[7:0]};
  reg gemm_token_valid_q, gemm_token_last_q;
  reg [LANES*32-1:0] stage0_bias_q, stage1_bias_q;
  reg [4:0] stage0_shift_q, stage1_shift_q;
  reg signed [5:0] gemm_shift_q;
  reg stage0_relu_q, stage1_relu_q, stage0_relu6_q, stage1_relu6_q;
  reg signed [7:0] stage0_max_q, stage1_max_q;
  reg [PIX_BITS*9-1:0] window_q;
  // Timing-21: preselect each DW pixel at the existing window/tap boundary.
  // The current MAC consumes this register while the next tap is selected;
  // all nine products retain their original consumption cycles.
  reg [PIX_BITS-1:0] mac_a_q /* synthesis syn_preserve=1 syn_keep=1 */;
  wire [PIX_BITS-1:0] dw_operand_q=mac_a_q;
  reg [PIX_BITS-1:0] dw_pixel_q;
  // Timing-14: select the next scalar operand while the current MAC runs.
  // The first operand uses the existing window/fused-result accept boundary;
  // no extra state, bubble, or change to accumulator feedback is introduced.
  wire [7:0] conv_scalar_q=mac_a_q[7:0];
  reg [LANES*32-1:0] result_q, result_raw_q;
  reg result_valid_q, result_gemm_q;
  // Elastic Bias stage. Raw INT32 and coordinates travel with the biased
  // value; neither PSUM nor Q24 sees an accumulator from the next pixel.
  reg post_valid_q, post_internal_q;
  wire post_gemm_q=g_post_group[0].gemm_q;
  wire post_left_q=g_post_group[0].left_q;
  wire post_relu6_zero_q=g_post_group[0].relu6_zero_q;
  // Timing-16A: four independent two-lane shift-control banks.  All banks
  // use the existing elastic post-sum boundary, including backpressure.
  wire [5:0] post_amount_next = (mode_q == MODE_GEMM)
       ? (gemm_shift_q[5] ? (~gemm_shift_q + 6'd1)
                          : {1'b0,gemm_shift_q[4:0]})
       : {1'b0,quant_shift};
  // Retiming, not an extra stage: arithmetic right shifts compose exactly.
  // Keep left-shift data untouched, including its original overflow/sign.
  wire [1:0] post_right_low_next = ((mode_q==MODE_GEMM) && gemm_shift_q[5])
                                 ? 2'd0 : post_amount_next[1:0];
  function automatic [32:0] legacy_bias_right_low;
    input [31:0] a,bi;
    input [1:0] amount_low;
    reg signed [32:0] sum;
    begin
      sum=$signed({a[31],a})+$signed({bi[31],bi});
      legacy_bias_right_low=sum >>> amount_low;
    end
  endfunction
  // Compatibility observation for existing cycle-stability testbenches.
  /* verilator lint_off UNUSEDSIGNAL */
  wire [5:0] post_amount_q = g_post_group[0].amount_q;
  /* verilator lint_on UNUSEDSIGNAL */
  reg [LANES*33-1:0] post_sum_q;
  reg [LANES*32-1:0] post_raw_q;
  wire post_relu_q=g_post_group[0].relu_q;
  wire post_relu6_q=g_post_group[0].relu6_q;
  wire signed [7:0] post_max_q=g_post_group[0].max_q;
  reg [3:0] post_channels_q;
  reg [5:0] post_x_q, post_y_q;
  reg [31:0] accum_q [0:LANES-1];
  reg [3:0] tap_q, channel_q;
  reg [6:0] weight_index_q;
  reg [6:0] weight_index_next;
  wire channel_last = (channel_q + 1'b1 >= in_channels_q);
  wire [3:0] next_channel = channel_last ? 4'd0 : channel_q + 4'd1;
  wire [3:0] next_tap = channel_last ? tap_q + 4'd1 : tap_q;
  reg [LANES*8-1:0] weights [0:WEIGHT_DEPTH-1];
  reg [WEIGHT_DEPTH-1:0] weight_loaded_q;
  reg [5:0] pending_x_q, pending_y_q;

  wire line_cfg_ready, line_in_ready, line_out_valid, line_done, line_error, line_busy;
  wire [PIX_BITS*9-1:0] line_window;
  wire [5:0] line_x, line_y;
  wire [PIX_BITS-1:0] in_pixel = in_token[PIX_BITS-1:0];
  // Two elastic stages: Bias sum -> shift/activation -> registered output.
  // Accept the next window as soon as the Bias stage takes the final raw
  // accumulator, independently of downstream output backpressure.
  wire result_ready = !result_valid_q || out_ready;
  wire post_take = post_valid_q && (post_internal_q
                  ? (state_q == C_FUSED_FIRST) : result_ready);
  wire post_ready = !post_valid_q || post_take;
  wire quant_submit = ((state_q == C_QUANT) || (state_q == C_DW_QUANT))
                      && post_ready;
  wire quant_internal = (state_q == C_DW_QUANT) && (mode_q == MODE_FUSED);
  wire next_window_ready = quant_submit && !quant_internal && (mode_q != MODE_GEMM);
  wire line_out_ready = frame_active_q && (mode_q != MODE_GEMM)
                       && (!result_valid_q || out_ready)
                       && (!post_valid_q || post_take)
                       && ((state_q == C_IDLE) || next_window_ready);
  // Timing-19: prefetch at the SAME edge that advances weight_index_q.
  // Reading the next address keeps the current MAC operand/cycle unchanged,
  // while separating LUTRAM/address selection from APM + accumulator feedback.
  // Weights are immutable during a frame; configuration/window acceptance
  // already provides the first-word boundary. No new state or wait cycle.
  reg [PIX_BITS-1:0] mac_b_q, weight_prefetch_ram_q;
  reg [6:0] active_weight_end_q;
  wire [PIX_BITS-1:0] active_weights=mac_b_q;
  always @* begin
    weight_index_next=weight_index_q;
    case (state_q)
      C_DW:if(tap_q!=8)weight_index_next=weight_index_q+1'b1;
      C_DW_QUANT,C_QUANT:
        if(quant_submit && quant_internal)weight_index_next=7'd9;
      C_FUSED_FIRST:if(post_take)weight_index_next=7'd9;
      C_PW:if(!channel_last)weight_index_next=weight_index_q+1'b1;
      C_REGULAR:weight_index_next=weight_index_q+1'b1;
      default:begin end
    endcase
    // Match the original last-assignment priority for a new window.
    if(line_out_valid && line_out_ready)weight_index_next=0;
  end
  // Two-step weight lookahead: the SRAM and local operand register are
  // separate boundaries. The next pixel/phase is primed during existing
  // quant/window cycles, without adding a state or delaying a MAC.
  reg [6:0] weight_ram_addr;
  wire [7:0] weight_plus_two={1'b0,weight_index_q}+8'd2;
  always @* begin
    weight_ram_addr=0;
    case(state_q)
      C_DW:if(weight_plus_two<8'd9)weight_ram_addr=weight_plus_two[6:0];
      C_REGULAR,C_PW:
        if(weight_plus_two<{1'b0,active_weight_end_q})
          weight_ram_addr=weight_plus_two[6:0];
      C_DW_QUANT:if(mode_q==MODE_FUSED)weight_ram_addr=7'd9;
      C_FUSED_FIRST:weight_ram_addr=post_take
          ? ((in_channels_q>1)?7'd10:7'd0) : 7'd9;
      default:begin end
    endcase
    if(line_out_valid && line_out_ready)
      weight_ram_addr=((mode_q==MODE_PW) && in_channels_q==1)?7'd0:7'd1;
  end
  always @(posedge clk)weight_prefetch_ram_q<=weights[weight_ram_addr];
  always @(posedge clk or negedge rst_n)
    if(!rst_n)mac_b_q<=0;
    else if(mode_q==MODE_GEMM)begin
      if(in_valid && in_ready)mac_b_q<=in_token[8+:PIX_BITS];
    end else mac_b_q<=weight_prefetch_ram_q;
  reg [PIX_BITS-1:0] activations;
  wire [(LANES*32)-1:0] a24_stage1_bias_capture;
  genvar a24_stage1_bias_bit;
  generate for(a24_stage1_bias_bit=0;a24_stage1_bias_bit<(LANES*32);a24_stage1_bias_bit=a24_stage1_bias_bit+1)begin:g_a24_stage1_bias
    if(a24_stage1_bias_bit==152)begin:g_pad
      ai_core_sparse_hold_pad #(.STAGES(2)) timingHoldA21_pad(.data_in(cfg_stage1_bias[a24_stage1_bias_bit]),.data_out(a24_stage1_bias_capture[a24_stage1_bias_bit]));
    end else assign a24_stage1_bias_capture[a24_stage1_bias_bit]=cfg_stage1_bias[a24_stage1_bias_bit];
  end endgenerate
  wire [LANES*32-1:0] accum_flat;
  wire [(LANES*32)-1:0] accum_capture_delayed;
  genvar accum_capture_bit;
  generate for(accum_capture_bit=0;accum_capture_bit<(LANES*32);accum_capture_bit=accum_capture_bit+1)begin:g_accum_capture
    if(accum_capture_bit==13 || accum_capture_bit==126 || accum_capture_bit==159)begin:g_pad
      ai_core_sparse_hold_pad #(.STAGES(2)) timingHoldA21_pad(.data_in(accum_flat[accum_capture_bit]),.data_out(accum_capture_delayed[accum_capture_bit]));
    end else assign accum_capture_delayed[accum_capture_bit]=accum_flat[accum_capture_bit];
  end endgenerate

  // Never forward mac_sum into the quantizer: all nine DW products must
  // cross accum_q before Bias/Shift/activation. Config stays locked until
  // frame completion, including every output backpressure cycle.
  wire use_stage0 = quant_stage0_q;
  wire [LANES*32-1:0] quant_bias = use_stage0 ? stage0_bias_q : stage1_bias_q;
  wire [4:0] quant_shift = use_stage0 ? stage0_shift_q : stage1_shift_q;
  wire quant_relu = use_stage0 ? stage0_relu_q : stage1_relu_q;
  wire quant_relu6 = use_stage0 ? stage0_relu6_q : stage1_relu6_q;
  wire signed [7:0] quant_max = use_stage0 ? stage0_max_q : stage1_max_q;
  wire [PIX_BITS-1:0] quant_result;
  reg [6:0] required_weights;
  reg missing_weights;
  integer w;
  integer lane;
  integer n;

  always @* begin
    case (cfg_mode)
      MODE_DW: required_weights = 7'd9;
      MODE_FUSED: required_weights = 7'd9 + {3'd0, cfg_in_channels};
      MODE_REGULAR: required_weights = 7'd9 * cfg_in_channels;
      MODE_PW: required_weights = {3'd0, cfg_in_channels};
      MODE_GEMM: required_weights = 0;
      default: required_weights = 0;
    endcase
    missing_weights = 0;
    for (w=0; w<WEIGHT_DEPTH; w=w+1)
      if ((w < required_weights) && !weight_loaded_q[w]) missing_weights = 1;
  end
  wire invalid_conv_cfg = cfg_width == 0 || cfg_height == 0
      || cfg_width > MAX_WIDTH_U || cfg_height > MAX_HEIGHT_U
      || cfg_in_channels == 0 || cfg_in_channels > LANES_U
      || cfg_out_channels == 0 || cfg_out_channels > LANES_U
      || (cfg_mode == MODE_DW && cfg_out_channels != cfg_in_channels)
      || (cfg_stage0_relu6 && cfg_stage0_relu6_max < 0)
      || (cfg_stage1_relu6 && cfg_stage1_relu6_max < 0)
      || missing_weights;
  wire invalid_gemm_cfg = (cfg_k == 0) || (cfg_k > MAX_K_U)
      || (cfg_in_channels != 1)
      || (cfg_out_channels == 0) || (cfg_out_channels > LANES_U)
      || (cfg_stage1_relu6 && cfg_stage1_relu6_max < 0);
  wire invalid_cfg = (cfg_mode == MODE_GEMM) ? invalid_gemm_cfg
                   : ((cfg_mode <= MODE_PW) ? invalid_conv_cfg : 1'b1);
  // Timing-13B: configuration payload is captured at the accepted
  // descriptor handshake.  Legality still gates frame/state start below;
  // keeping this boundary separate prevents weight-completeness checks from
  // entering every payload register CE cone.
  wire cfg_fire = cfg_valid && cfg_ready;
  // Timing-13A: GEMM-only result initialization must not depend on the
  // convolution weight-count/missing-weight validation tree.
  wire gemm_start_ok = cfg_valid && cfg_ready
                     && (cfg_mode == MODE_GEMM) && !invalid_gemm_cfg;
  wire conv_start_frame = cfg_valid && cfg_ready
                        && (cfg_mode != MODE_GEMM) && !invalid_cfg;

  assign cfg_ready = !frame_active_q && (state_q == C_IDLE)
                  && ((cfg_mode == MODE_GEMM) || line_cfg_ready)
                  && !weight_valid;
  assign weight_ready = !frame_active_q && (state_q == C_IDLE) && !cfg_valid;
  assign in_ready = (mode_q == MODE_GEMM) ? ((state_q == C_GEMM) && !gemm_token_last_q)
                   : line_in_ready;
  assign out_valid = result_valid_q;
  genvar out_lane;
  generate for(out_lane=0;out_lane<LANES;out_lane=out_lane+1)begin:g_pixel_view
    assign out_pixel[out_lane*8+:8]=result_gemm_q
      ? result_q[out_lane*32+:8] : result_q[out_lane*8+:8];
  end endgenerate
  assign out_data = result_q;
  assign out_accum = result_raw_q;
  assign busy = frame_active_q || line_busy || (state_q != C_IDLE)
              || post_valid_q || result_valid_q;

  ai_window3x3_v2 #(.LANES(LANES), .MAX_WIDTH(MAX_WIDTH),
                    .MAX_HEIGHT(MAX_HEIGHT)) window_i (
    .clk(clk), .rst_n(rst_n),
    .cfg_valid(conv_start_frame), .cfg_ready(line_cfg_ready),
    .cfg_width(cfg_width), .cfg_height(cfg_height),
    // A 1x1 kernel has no halo: SAME and VALID select the same centers.
    .cfg_pad_same(cfg_pad_same || cfg_mode == MODE_PW), .cfg_stride2(cfg_stride2),
    .in_valid(in_valid), .in_ready(line_in_ready), .in_pixel(in_pixel),
    .out_valid(line_out_valid), .out_ready(line_out_ready),
    .out_window(line_window), .out_x(line_x), .out_y(line_y),
    .done(line_done), .error(line_error), .busy(line_busy)
  );

  wire [PIX_BITS-1:0] mac_a = mac_a_q;
  wire [PIX_BITS-1:0] mac_b = mac_b_q;
  wire signed [15:0] mac_product [0:LANES-1];
  wire [31:0] mac_sum [0:LANES-1];
  genvar g;
  generate for (g=0; g<LANES; g=g+1) begin : g_acc
    assign accum_flat[g*32 +: 32] = accum_q[g];
    assign mac_product[g] = $signed(mac_a[g*8 +: 8]) * $signed(mac_b[g*8 +: 8]);
    assign mac_sum[g] = accum_q[g] + {{16{mac_product[g][15]}},mac_product[g]};
  end endgenerate
  wire [LANES*32-1:0] quant_gemm_result;
  // Local controls use the existing elastic quant_submit boundary.
  // Preserved per-lane FFs keep the shift/activation/format drivers local.
  genvar pg;
  generate for(pg=0;pg<LANES;pg=pg+1)begin:g_post_group
    reg [5:0] amount_q /* synthesis syn_preserve=1 syn_keep=1 */;
    reg left_q /* synthesis syn_preserve=1 syn_keep=1 */;
    reg relu_q /* synthesis syn_preserve=1 syn_keep=1 */;
    reg relu6_q /* synthesis syn_preserve=1 syn_keep=1 */;
    reg relu6_zero_q /* synthesis syn_preserve=1 syn_keep=1 */;
    reg gemm_q /* synthesis syn_preserve=1 syn_keep=1 */;
    reg active_q /* synthesis syn_preserve=1 syn_keep=1 */;
    reg signed [7:0] max_q /* synthesis syn_preserve=1 syn_keep=1 */;
    always @(posedge clk or negedge rst_n) begin
      if(!rst_n)begin
        amount_q<=0;left_q<=0;relu_q<=0;relu6_q<=0;relu6_zero_q<=0;
        gemm_q<=0;active_q<=0;max_q<=0;
      end else if(quant_submit)begin
        amount_q<=post_amount_next;
        left_q<=(mode_q==MODE_GEMM) && gemm_shift_q[5];
        relu_q<=quant_relu;relu6_q<=quant_relu6;
        relu6_zero_q<=quant_relu6 && (mode_q!=MODE_GEMM);
        max_q<=quant_max;gemm_q<=(mode_q==MODE_GEMM);
        active_q <= (pg < ((state_q==C_DW_QUANT) ? in_channels_q : out_channels_q));
      end
    end
    ai_postprocess_shift_v1 #(.LANES(1),.PRECOMPUTED_CTRL(1),
      .RIGHT_ONLY_PIXEL(1),.RIGHT_SHIFT_LOW_BITS(2)) postprocess_i (
      .biased(post_sum_q[pg*33+:33]), .gemm(1'b0), .shift(6'sd0),
      .relu(relu_q), .relu6(relu6_q), .relu6_max(max_q),
      .precomputed_left(left_q), .precomputed_amount(amount_q),
      .precomputed_relu6_zero(relu6_zero_q),
      .result8(quant_result[pg*8+:8]),
      .result32(quant_gemm_result[pg*32+:32])
    );
  end endgenerate
  wire [PIX_BITS-1:0] output_pixel_result;
  wire [LANES*32-1:0] gemm_result_data;
  wire [LANES*32-1:0] packed_pixel_result={{(LANES*24){1'b0}},output_pixel_result};
  wire [LANES*32-1:0] quantized_data_result;
  genvar q;
  generate for(q=0;q<LANES;q=q+1)begin:g_result_pack
    assign output_pixel_result[q*8+:8]=g_post_group[q].active_q
      ? quant_result[q*8+:8] : 8'd0;
    assign gemm_result_data[q*32+:32]=g_post_group[q].active_q
      ? quant_gemm_result[q*32+:32] : 32'd0;
    assign quantized_data_result[q*32+:32]=g_post_group[q].gemm_q
       ? gemm_result_data[q*32+:32] : packed_pixel_result[q*32+:32];
  end endgenerate

  always @* begin
    activations = 0;
    case (state_q)
      C_DW: activations = dw_operand_q;
      C_REGULAR: for (n=0; n<LANES; n=n+1)
        activations[n*8 +: 8] = conv_scalar_q;
      // The fused DW result is registered into dw_pixel_q before C_PW.
      // Keeping this state free of a result-to-MAC bypass prevents the
      // postprocess control fanout from entering the MAC input path.
      C_PW: for (n=0; n<LANES; n=n+1)
        activations[n*8 +: 8] = conv_scalar_q;
      default: begin end
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= C_IDLE;
      frame_active_q <= 0;
      line_complete_q <= 0;
      mode_q <= 0;
      quant_stage0_q <= 0;
      in_channels_q <= 0;
      out_channels_q <= 0;
      gemm_k_q <= 0;
      gemm_index_q <= 0;
      gemm_token_valid_q <= 0;
      gemm_token_last_q <= 0;
      stage0_bias_q <= 0;
      stage1_bias_q <= 0;
      stage0_shift_q <= 0;
      stage1_shift_q <= 0;
      gemm_shift_q <= 0;
      stage0_relu_q <= 0;
      stage1_relu_q <= 0;
      stage0_relu6_q <= 0;
      stage1_relu6_q <= 0;
      stage0_max_q <= 0;
      stage1_max_q <= 0;
      window_q <= 0;
      mac_a_q <= 0;
      dw_pixel_q <= 0;
      result_q <= 0;
      result_raw_q <= 0;
      result_valid_q <= 0;
      result_gemm_q <= 0;
      post_valid_q <= 0;
      post_internal_q <= 0;
      post_sum_q <= 0;
      post_raw_q <= 0;
      post_channels_q <= 0;
      post_x_q <= 0;
      post_y_q <= 0;
      tap_q <= 0;
      channel_q <= 0;
      weight_index_q <= 0;
      active_weight_end_q <= 0;
      weight_loaded_q <= 0;
      pending_x_q <= 0;
      pending_y_q <= 0;
      out_x <= 0;
      out_y <= 0;
      done <= 0;
      error <= 0;
      perf_mac_count <= 0;
      perf_busy_cycles <= 0;
      perf_input_stall_cycles <= 0;
      perf_output_stall_cycles <= 0;
      for (lane=0; lane<LANES; lane=lane+1) accum_q[lane] <= 0;
    end else begin
      done <= 0;
      weight_index_q <= weight_index_next;
      gemm_token_valid_q <= 1'b0;
      if (busy) perf_busy_cycles <= perf_busy_cycles + 1'b1;
      if (frame_active_q && state_q == C_IDLE && !line_out_valid && !line_complete_q)
        perf_input_stall_cycles <= perf_input_stall_cycles + 1'b1;
      if (out_valid && !out_ready)
        perf_output_stall_cycles <= perf_output_stall_cycles + 1'b1;
      if (weight_valid && weight_ready) begin
        if (weight_addr < WEIGHT_DEPTH_U) begin
          weights[weight_addr] <= weight_data;
          weight_loaded_q[weight_addr] <= 1'b1;
        end else error <= 1'b1;
      end
      if (cfg_fire) begin
        error <= invalid_cfg;
        // Payload registers are shadowed on every accepted descriptor.  No
        // consumer can use them until the legal branch below starts a frame.
        // Operational state and mode remain validity-gated.
        quant_stage0_q <= (cfg_mode == MODE_DW) ||
                          (cfg_mode == MODE_FUSED) ||
                          (cfg_mode == MODE_REGULAR);
        in_channels_q <= cfg_in_channels;
        active_weight_end_q <= required_weights;
        out_channels_q <= cfg_out_channels;
        gemm_k_q <= cfg_k;
        stage0_bias_q <= cfg_stage0_bias;
        stage1_bias_q <= a24_stage1_bias_capture;
        stage0_shift_q <= cfg_stage0_shift;
        stage1_shift_q <= cfg_stage1_shift;
        gemm_shift_q <= cfg_gemm_shift;
        stage0_relu_q <= cfg_stage0_relu;
        stage1_relu_q <= cfg_stage1_relu;
        stage0_relu6_q <= cfg_stage0_relu6;
        stage1_relu6_q <= cfg_stage1_relu6;
        stage0_max_q <= cfg_stage0_relu6_max;
        stage1_max_q <= cfg_stage1_relu6_max;
        if (invalid_cfg) done <= 1;
        else begin
          frame_active_q <= 1;
          line_complete_q <= 0;
          mode_q <= cfg_mode;
          gemm_index_q <= 0;
          gemm_token_last_q <= 1'b0;
          if (cfg_mode == MODE_GEMM) begin
            for (lane=0; lane<LANES; lane=lane+1) accum_q[lane] <= 0;
            state_q <= C_GEMM;
          end
        end
      end
      // Keep the later post_take write higher priority, exactly as before.
      if (gemm_start_ok) result_q <= 0;
      if (line_error) error <= 1;
      if (line_done) line_complete_q <= 1;
      if ((mode_q != MODE_GEMM) && frame_active_q && line_complete_q
          && state_q == C_IDLE && !line_out_valid
          && !post_valid_q && !result_valid_q) begin
        frame_active_q <= 0;
        done <= 1;
      end

      case (state_q)
        C_IDLE: begin end
        C_DW: begin
          if (tap_q != 8)
            mac_a_q <= window_q[(tap_q+4'd1)*PIX_BITS +: PIX_BITS];
          perf_mac_count <= perf_mac_count + {60'd0, in_channels_q};
          for (lane=0; lane<LANES; lane=lane+1)
            if (lane < in_channels_q)
              accum_q[lane] <= mac_sum[lane];
          if (tap_q == 8) begin
            state_q <= C_DW_QUANT;
          end
          else begin
            tap_q <= tap_q + 1'b1;
          end
        end
        C_DW_QUANT, C_QUANT: if (quant_submit) begin
          if (quant_internal) begin
            quant_stage0_q <= 1'b0;
            state_q <= C_FUSED_FIRST;
          end else state_q <= (mode_q == MODE_GEMM) ? C_OUT : C_IDLE;
        end
        C_FUSED_FIRST: if (post_take) begin
          dw_pixel_q <= output_pixel_result;
          mac_a_q <= {LANES{output_pixel_result[7:0]}};
          for (lane=0; lane<LANES; lane=lane+1) accum_q[lane] <= 0;
          channel_q <= 0;
          state_q <= C_PW;
        end
        C_PW: begin
          if (!channel_last)
            mac_a_q <= {LANES{dw_pixel_q[next_channel*8 +: 8]}};
          perf_mac_count <= perf_mac_count + {60'd0, out_channels_q};
          for (lane=0; lane<LANES; lane=lane+1)
            if (lane < out_channels_q)
              accum_q[lane] <= mac_sum[lane];
          if (channel_q + 1'b1 >= in_channels_q) state_q <= C_QUANT;
          else begin
            channel_q <= channel_q + 1'b1;
          end
        end
        C_REGULAR: begin
          if (!(channel_last && tap_q == 8))
            mac_a_q <= {LANES{window_q[next_tap*PIX_BITS+next_channel*8 +: 8]}};
          perf_mac_count <= perf_mac_count + {60'd0, out_channels_q};
          for (lane=0; lane<LANES; lane=lane+1)
            if (lane < out_channels_q)
              accum_q[lane] <= mac_sum[lane];
          if (channel_q + 1'b1 >= in_channels_q) begin
            channel_q <= 0;
            if (tap_q == 8) state_q <= C_QUANT;
            else tap_q <= tap_q + 1'b1;
          end else begin
            channel_q <= channel_q + 1'b1;
          end
        end
        C_GEMM: begin
          // Consume the previous registered token before capturing its
          // successor. The accumulator feedback and signed INT8 multiply
          // are unchanged; bubbles never re-accumulate stale token data.
          if (gemm_token_valid_q) begin
            perf_mac_count <= perf_mac_count + {60'd0, out_channels_q};
            for (lane=0; lane<LANES; lane=lane+1)
              if (lane < out_channels_q)
                accum_q[lane] <= mac_sum[lane];
            if (gemm_token_last_q) state_q <= C_QUANT;
          end
          if (in_valid && in_ready) begin
            mac_a_q <= {LANES{in_token[7:0]}};
            gemm_token_valid_q <= 1'b1;
            gemm_token_last_q <= (gemm_index_q + 16'd1 >= gemm_k_q);
            if (gemm_index_q + 16'd1 >= gemm_k_q) begin
              gemm_index_q <= 0;
            end else gemm_index_q <= gemm_index_q + 16'd1;
          end else if (in_ready)
            perf_input_stall_cycles <= perf_input_stall_cycles + 1'b1;
        end
        C_OUT: begin end // GEMM waits for its elastic output handshake.
        default: state_q <= C_IDLE;
      endcase

      if (result_valid_q && out_ready) begin
        result_valid_q <= 1'b0;
        if (result_gemm_q) begin
          frame_active_q <= 1'b0;
          state_q <= C_IDLE;
          done <= 1'b1;
        end
      end
      if (post_take) begin
        post_valid_q <= 1'b0;
        if (!post_internal_q) begin
          result_q <= quantized_data_result;
          result_raw_q <= post_raw_q;
          result_gemm_q <= post_gemm_q;
          result_valid_q <= 1'b1;
          out_x <= post_x_q;
          out_y <= post_y_q;
        end
      end
      if (quant_submit) begin
        post_valid_q <= 1'b1;
        post_internal_q <= quant_internal;
        post_raw_q <= accum_capture_delayed;
        for (lane=0; lane<LANES; lane=lane+1)
          post_sum_q[lane*33+:33] <=
            legacy_bias_right_low(accum_q[lane],quant_bias[lane*32+:32],
                                  post_right_low_next);
        post_channels_q <= (state_q == C_DW_QUANT) ? in_channels_q : out_channels_q;
        post_x_q <= (mode_q == MODE_GEMM) ? 6'd0 : pending_x_q;
        post_y_q <= (mode_q == MODE_GEMM) ? 6'd0 : pending_y_q;
      end
      if (line_out_valid && line_out_ready) begin
        window_q <= line_window;
        pending_x_q <= line_x;
        pending_y_q <= line_y;
        tap_q <= 0;
        channel_q <= 0;
        for (lane=0; lane<LANES; lane=lane+1) accum_q[lane] <= 0;
        case (mode_q)
          MODE_DW, MODE_FUSED: begin
            // Use the incoming window, not the previous window_q contents.
            // This later assignment retains new-window acceptance priority.
            mac_a_q <= line_window[0+:PIX_BITS];
            quant_stage0_q <= 1'b1;
            state_q <= C_DW;
          end
          MODE_REGULAR: begin
            mac_a_q <= {LANES{line_window[7:0]}};
            state_q <= C_REGULAR;
          end
          default: begin
            dw_pixel_q <= line_window[4*PIX_BITS+:PIX_BITS];
            mac_a_q <= {LANES{line_window[4*PIX_BITS+:8]}};
            state_q <= C_PW;
          end
        endcase
      end
    end
  end
endmodule

// Backwards-compatible Phase 2 interface.  Existing Phase 2 testbenches keep
// their narrow 2-bit mode and 64-bit pixel ports while the default Phase 2
// source manifest can switch to the unified implementation.
/* verilator lint_off DECLFILENAME */
module ai_conv8_v2 #(
  parameter integer LANES = 8,
  parameter integer MAX_WIDTH = 32,
  parameter integer MAX_HEIGHT = 32
) (
  input  wire                     clk,
  input  wire                     rst_n,
  input  wire                     weight_valid,
  output wire                     weight_ready,
  input  wire [6:0]               weight_addr,
  input  wire [LANES*8-1:0]       weight_data,
  input  wire                     cfg_valid,
  output wire                     cfg_ready,
  input  wire [1:0]               cfg_mode,
  input  wire [5:0]               cfg_width,
  input  wire [5:0]               cfg_height,
  input  wire                     cfg_pad_same,
  input  wire                     cfg_stride2,
  input  wire [3:0]               cfg_in_channels,
  input  wire [3:0]               cfg_out_channels,
  input  wire [LANES*32-1:0]      cfg_stage0_bias,
  input  wire [LANES*32-1:0]      cfg_stage1_bias,
  input  wire [4:0]               cfg_stage0_shift,
  input  wire [4:0]               cfg_stage1_shift,
  input  wire                     cfg_stage0_relu,
  input  wire                     cfg_stage1_relu,
  input  wire                     cfg_stage0_relu6,
  input  wire                     cfg_stage1_relu6,
  input  wire signed [7:0]        cfg_stage0_relu6_max,
  input  wire signed [7:0]        cfg_stage1_relu6_max,
  input  wire                     in_valid,
  output wire                     in_ready,
  input  wire [LANES*8-1:0]       in_pixel,
  output wire                     out_valid,
  input  wire                     out_ready,
  output wire [LANES*8-1:0]       out_pixel,
  output wire [5:0]               out_x,
  output wire [5:0]               out_y,
  output wire                     done,
  output wire                     error,
  output wire                     busy,
  output wire [63:0]              perf_mac_count,
  output wire [63:0]              perf_busy_cycles,
  output wire [63:0]              perf_input_stall_cycles,
  output wire [63:0]              perf_output_stall_cycles
);
  /* verilator lint_off PINCONNECTEMPTY */
  ai_compute_core_v1 #(.LANES(LANES), .MAX_WIDTH(MAX_WIDTH),
                       .MAX_HEIGHT(MAX_HEIGHT)) core_i (
    .clk(clk), .rst_n(rst_n),
    .weight_valid(weight_valid), .weight_ready(weight_ready),
    .weight_addr(weight_addr), .weight_data(weight_data),
    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
    .cfg_mode({1'b0,cfg_mode}), .cfg_k(16'd0),
    .cfg_width(cfg_width), .cfg_height(cfg_height),
    .cfg_pad_same(cfg_pad_same), .cfg_stride2(cfg_stride2),
    .cfg_in_channels(cfg_in_channels), .cfg_out_channels(cfg_out_channels),
    .cfg_stage0_bias(cfg_stage0_bias), .cfg_stage1_bias(cfg_stage1_bias),
    .cfg_stage0_shift(cfg_stage0_shift), .cfg_stage1_shift(cfg_stage1_shift),
    .cfg_gemm_shift(6'sd0),
    .cfg_stage0_relu(cfg_stage0_relu), .cfg_stage1_relu(cfg_stage1_relu),
    .cfg_stage0_relu6(cfg_stage0_relu6), .cfg_stage1_relu6(cfg_stage1_relu6),
    .cfg_stage0_relu6_max(cfg_stage0_relu6_max),
    .cfg_stage1_relu6_max(cfg_stage1_relu6_max),
    .in_valid(in_valid), .in_ready(in_ready), .in_token({8'd0,in_pixel}),
    .out_valid(out_valid), .out_ready(out_ready), .out_pixel(out_pixel),
    .out_data(), .out_accum(), .out_x(out_x), .out_y(out_y),
    .done(done), .error(error), .busy(busy),
    .perf_mac_count(perf_mac_count), .perf_busy_cycles(perf_busy_cycles),
    .perf_input_stall_cycles(perf_input_stall_cycles),
    .perf_output_stall_cycles(perf_output_stall_cycles)
  );
  /* verilator lint_on PINCONNECTEMPTY */
endmodule
/* verilator lint_on DECLFILENAME */

// An even number of kept LUT inversions is a cycle-neutral identity.
// Actual minimum delay must be checked in the routed fast-corner STA.
module ai_core_sparse_hold_pad #(parameter WIDTH=1, STAGES=2)(
  input wire [WIDTH-1:0] data_in, output wire [WIDTH-1:0] data_out);
  (* syn_keep=1 *) wire [WIDTH*(STAGES+1)-1:0] chain;
  assign chain[0+:WIDTH]=data_in;
  assign data_out=chain[WIDTH*STAGES+:WIDTH];
  genvar stage,bit_index;
  generate for(stage=0;stage<STAGES;stage=stage+1)begin:delay_stage
    for(bit_index=0;bit_index<WIDTH;bit_index=bit_index+1)begin:delay_bit
      (* syn_keep=1,syn_preserve=1 *) GTP_LUT1 #(.INIT(2'b01)) invert(
        .I0(chain[stage*WIDTH+bit_index]),.Z(chain[(stage+1)*WIDTH+bit_index]));
    end
  end endgenerate
endmodule
