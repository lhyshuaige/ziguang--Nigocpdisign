// Serialize one eight-channel output pixel through the shared pipelined Q24
// unit. The adapter keeps up to eight scalar lanes in flight: submission and
// return counters are independent, so the Q24 pipeline can accept one lane
// per cycle while preserving channel order under backpressure.
module ai_postprocess_q24_pixel (
  input  wire         clk,
  input  wire         rst_n,
  input  wire         param_valid,
  input  wire [255:0] param_bias,
  input  wire [255:0] param_multiplier_q24,
  input  wire         param_relu,
  input  wire         param_relu6,
  input  wire signed [7:0] param_relu6_max,
  input  wire         in_valid,
  output wire         in_ready,
  input  wire [255:0] in_accum,
  input  wire [7:0]   in_channel_base,
  output wire         out_valid,
  input  wire         out_ready,
  output wire [63:0]  out_pixel,
  output wire         busy,
  output wire [31:0]  perf_scalar_stall_cycles
);
  reg [255:0] bias_q, multiplier_q24_q, accum_q;
  reg [7:0] channel_base_q;
  reg relu_q, relu6_q;
  reg signed [7:0] relu6_max_q;
  reg active_q, pixel_valid_q;
  reg [3:0] submit_count_q, return_count_q;
  reg [63:0] pixel_q;
  reg [31:0] scalar_stall_q;

  wire scalar_in_valid = active_q && (submit_count_q < 4'd8);
  wire scalar_in_ready;
  wire scalar_out_valid;
  wire [15:0] scalar_channel;
  wire signed [7:0] scalar_value;
  wire [15:0] expected_channel = {8'd0, channel_base_q} + {12'd0, return_count_q};
  wire scalar_channel_ok = (scalar_channel == expected_channel);
  wire scalar_out_ready = active_q && !pixel_valid_q &&
                           (return_count_q < 4'd8) && scalar_channel_ok;
  wire [2:0] submit_lane = submit_count_q[2:0];
  wire [31:0] lane_bias = bias_q[submit_lane*32 +: 32];
  wire [23:0] lane_multiplier = multiplier_q24_q[submit_lane*32 +: 24];
  wire signed [31:0] scalar_bias = $signed(lane_bias);
  // The checked MobileNet Q24 manifest has multiplier <= 10,036,957, so a
  // signed 25-bit production operand is sufficient. The packed sideband
  // remains 32 bits for CSR/descriptor compatibility.
  wire [23:0] scalar_multiplier = lane_multiplier;
  wire [15:0] scalar_channel_in = {8'd0, channel_base_q} + {13'd0, submit_lane};

  assign in_ready = !active_q && (!pixel_valid_q || out_ready);
  assign out_valid = pixel_valid_q;
  assign out_pixel = pixel_q;
  assign busy = active_q || pixel_valid_q;
  assign perf_scalar_stall_cycles = scalar_stall_q;

  ai_postprocess_q24_pc #(.CHANNEL_BITS(16), .MULTIPLIER_BITS(24),
                          .MULTIPLIER_UNSIGNED(1)) scalar_i (
    .clk(clk), .rst_n(rst_n),
    .in_valid(scalar_in_valid), .in_ready(scalar_in_ready),
    .in_accum($signed(accum_q[submit_lane*32 +: 32])),
    .in_channel(scalar_channel_in), .in_bias(scalar_bias),
    .in_multiplier_q24(scalar_multiplier),
    .in_relu(relu_q), .in_relu6(relu6_q), .in_relu6_max(relu6_max_q),
    .out_valid(scalar_out_valid), .out_ready(scalar_out_ready),
    .out_channel(scalar_channel), .out_value(scalar_value)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bias_q <= 0;
      multiplier_q24_q <= 0;
      accum_q <= 0;
      channel_base_q <= 0;
      relu_q <= 0;
      relu6_q <= 0;
      relu6_max_q <= 0;
      active_q <= 0;
      pixel_valid_q <= 0;
      submit_count_q <= 0;
      return_count_q <= 0;
      pixel_q <= 0;
      scalar_stall_q <= 0;
    end else begin
      if (param_valid) begin
        bias_q <= param_bias;
        multiplier_q24_q <= param_multiplier_q24;
        relu_q <= param_relu;
        relu6_q <= param_relu6;
        relu6_max_q <= param_relu6_max;
      end
      if (scalar_in_valid && !scalar_in_ready)
        scalar_stall_q <= scalar_stall_q + 1'b1;
      if (pixel_valid_q && out_ready)
        pixel_valid_q <= 0;

      // Capture a new eight-lane pixel only when the previous one has fully
      // drained. The scalar pipeline starts on the following cycle.
      if (in_valid && in_ready) begin
        accum_q <= in_accum;
        channel_base_q <= in_channel_base;
        active_q <= 1;
        submit_count_q <= 0;
        return_count_q <= 0;
        if (out_ready)
          pixel_valid_q <= 0;
      end

      // Independent submission counter: keep feeding the shared unit while
      // it is ready, without waiting for the previous lane's return.
      if (scalar_in_valid && scalar_in_ready)
        submit_count_q <= submit_count_q + 1'b1;

      // Independent return counter: output order is checked against the
      // expected channel before any lane is consumed.
      if (scalar_out_valid && scalar_out_ready) begin
        if (return_count_q == 4'd7) begin
          pixel_q <= {scalar_value, pixel_q[55:0]};
          pixel_valid_q <= 1;
          // A completed pixel may be consumed while the next pixel is
          // accepted in the same cycle.  Preserve the new active state in
          // that case; otherwise the final-return assignment would discard
          // the just-captured accum/parameters.
          if (!(in_valid && in_ready)) begin
            active_q <= 0;
            return_count_q <= 4'd8;
          end
        end else begin
          pixel_q[return_count_q*8 +: 8] <= scalar_value;
          return_count_q <= return_count_q + 1'b1;
        end
      end
    end
  end
endmodule
