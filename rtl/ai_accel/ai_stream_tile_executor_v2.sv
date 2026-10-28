// Unified descriptor-driven DMA/tile executor, fixed eight INT8 lanes.
// Descriptor words: 0 flags, 1 src, 2 dst, 3 shape/K, 4 shifts/max0,
// 5 max1, 6..13 bias0, 14..21 bias1. All modes use the same queue and DMA.
// Flags 11..13 are the Phase 3 PW/regular-Conv partial-sum tile contract:
//   psum_enable=1, psum_final marks the last input-channel tile, and
//   psum_start clears the tile accumulator before the first input tile.
module ai_stream_tile_executor_v2 #(
  parameter integer MAX_K=255,
  parameter integer MAX_WIDTH=32, MAX_HEIGHT=32,
  parameter [3:0] AXI_ID=4'd2,
  parameter integer INPUT_BEATS=(MAX_WIDTH*MAX_HEIGHT+3)/4+18,
  parameter integer OUTPUT_BEATS=(MAX_WIDTH*MAX_HEIGHT+3)/4
)(
  input wire clk, rst_n,
  input wire cmd_valid, output wire cmd_ready, input wire [703:0] cmd_desc,
  // Optional per-tile Q24 sideband.  Legacy descriptors leave bit 14 clear
  // and tie this interface inactive, so the 704-bit command format remains
  // binary compatible.
  input wire q24_param_valid,
  input wire [255:0] q24_param_bias,
  input wire [255:0] q24_param_multiplier_q24,
  input wire q24_param_relu, q24_param_relu6,
  input wire signed [7:0] q24_param_relu6_max,
  output wire m_arvalid, input wire m_arready,
  output wire [3:0] m_arid, output wire [31:0] m_araddr,
  output wire [7:0] m_arlen, output wire [2:0] m_arsize,
  output wire [1:0] m_arburst,
  input wire m_rvalid, output wire m_rready, input wire [3:0] m_rid,
  input wire [255:0] m_rdata, input wire [1:0] m_rresp, input wire m_rlast,
  output wire m_awvalid, input wire m_awready,
  output wire [3:0] m_awid, output wire [31:0] m_awaddr,
  output wire [7:0] m_awlen, output wire [2:0] m_awsize,
  output wire [1:0] m_awburst,
  output wire m_wvalid, input wire m_wready, output wire [255:0] m_wdata,
  output wire [31:0] m_wstrb, output wire m_wlast,
  input wire m_bvalid, output wire m_bready, input wire [3:0] m_bid,
  input wire [1:0] m_bresp,
  output wire busy, output reg done, error,
  output reg [63:0] perf_read_beats, perf_compute_cycles, perf_busy_cycles,
  output reg [63:0] perf_axi_wait_cycles, output wire [63:0] perf_mac_count,
  output wire [31:0] perf_q24_scalar_stall_cycles,
  output reg [63:0] perf_overlap_cycles
);
  localparam integer IA=$clog2(INPUT_BEATS), OA=$clog2(OUTPUT_BEATS);
  // Phase 3 psum tiles use one 256-bit word per output pixel.  The current
  // production tile is limited to OUTPUT_BEATS pixels (normally <=16x16 for
  // the channel-tiled path) so this stays bounded and does not change legacy
  // descriptors.
  localparam integer PA=(OUTPUT_BEATS>1)?$clog2(OUTPUT_BEATS):1;
  localparam [PA-1:0] PSUM_ONE=1;
  localparam [PA-1:0] PSUM_TWO=2;
  localparam integer QUEUE_DEPTH=8, QW=$clog2(QUEUE_DEPTH);
  localparam [QW:0] QUEUE_LIMIT=4'd8;
  localparam [11:0] INPUT_LIMIT=INPUT_BEATS[11:0];
  localparam [11:0] OUTPUT_LIMIT=OUTPUT_BEATS[11:0];
  localparam [7:0] K_LIMIT=MAX_K[7:0];
  localparam [5:0] WIDTH_LIMIT=MAX_WIDTH[5:0], HEIGHT_LIMIT=MAX_HEIGHT[5:0];
  localparam [2:0] L_IDLE=0,L_ADDR=1,L_DATA=2,L_DRAIN=3;
  localparam [3:0] E_IDLE=0,E_WPRIME=1,E_WEIGHT=2,E_CFG=3,E_PRIME=4,
                   E_RUN=5,E_FLUSH=6,E_DRAIN=7,E_RETIRE=8;
  localparam [1:0] W_IDLE=0,W_AW=1,W_DATA=2,W_RESP=3;
  reg [2:0] ls;
  reg [3:0] es;
  reg [1:0] ws;
  reg [QW-1:0] q_head, q_tail, load_slot;
  // Keep the queue pointer itself unchanged. Only the memory write branches
  // use a sink-local identity delay; this adds no clock-cycle latency.
  (* syn_keep=1 *) wire [QW*5-1:0] tail_hold_chain;
  wire [QW-1:0] q_tail_memory=tail_hold_chain[QW*4+:QW];
  assign tail_hold_chain[0+:QW]=q_tail;
  genvar hold_stage,hold_bit;
  generate for(hold_stage=0;hold_stage<4;hold_stage=hold_stage+1)begin:g_tail_hold_stage
    for(hold_bit=0;hold_bit<QW;hold_bit=hold_bit+1)begin:g_tail_hold_bit
      (* syn_keep=1,syn_preserve=1 *) GTP_LUT1 #(.INIT(2'b01)) invert(
        .I0(tail_hold_chain[hold_stage*QW+hold_bit]),.Z(tail_hold_chain[(hold_stage+1)*QW+hold_bit]));
    end
  end endgenerate
  reg load_bank, exec_bank;
  reg [QW:0] q_count;
  reg [QUEUE_DEPTH-1:0] occupied, loaded, loaded_safe, failed, slot_has_bank;
  reg [703:0] descriptors [0:QUEUE_DEPTH-1];
  // Timing-18A: reserve on acceptance, commit only after a half-cycle RAM
  // write pipeline. The first bank preserves generic ready/valid semantics:
  // cmd_desc may change immediately after its accepting rising edge.
  reg [703:0] desc_accept_q, desc_write_n;
  // Timing-20: use the existing acceptance -> RAM-commit cycle to separate
  // output geometry/APM from the address comparison and per-slot status mux.
  reg [11:0] desc_accept_output_pixels_q;
  reg desc_accept_invalid_base_q;
  reg [QW-1:0] desc_accept_slot_q, desc_write_slot_n;
  reg desc_accept_valid_q, desc_write_valid_n;
  reg [QUEUE_DEPTH-1:0] q24_sideband_q;
  reg [255:0] q24_bias_q [0:QUEUE_DEPTH-1];
  reg [255:0] q24_multiplier_q [0:QUEUE_DEPTH-1];
  reg q24_relu_q [0:QUEUE_DEPTH-1];
  reg q24_relu6_q [0:QUEUE_DEPTH-1];
  reg signed [7:0] q24_relu6_max_q [0:QUEUE_DEPTH-1];
  reg [11:0] queued_beats [0:QUEUE_DEPTH-1];
  reg [QUEUE_DEPTH-1:0] slot_bank;
  reg [1:0] bank_busy;
  // Snapshot the queue head before execution. The head remains live for
  // loader bookkeeping; it no longer controls core datapaths every cycle.
  reg [703:0] exec_descriptor;
  reg exec_descriptor_valid,exec_q24_enable,exec_relu,exec_relu6;
  reg [255:0] exec_bias,exec_multiplier;
  reg signed [7:0] exec_relu6_max;
  wire [703:0] d=exec_descriptor;
  wire unused_descriptor=^{d[191:168],d[151:150],d[143:141],d[135:133],
                           d[111:110],d[103:102],d[63:9]};
  wire [2:0] mode=d[2:0];
  wire gemm=(mode==4);
  wire reuse_input=d[9];
  wire keep_output=d[10];
  wire psum_enable=d[11];
  wire psum_final=d[12];
  wire psum_start=d[13];
  wire q24_enable=d[14] && exec_q24_enable;
  wire [7:0] q24_channel_base=d[22:15];
  wire [255:0] q24_bias_tile=exec_bias;
  wire [255:0] q24_multiplier_tile=exec_multiplier;
  wire q24_relu_tile=exec_relu;
  wire q24_relu6_tile=exec_relu6;
  wire signed [7:0] q24_relu6_max_tile=exec_relu6_max;
  wire [5:0] width=d[101:96], height=d[109:104];
  wire [3:0] cin=d[115:112], cout=d[119:116];
  wire [7:0] k=d[127:120];
  function automatic [6:0] nweights(input [2:0] m,input [3:0] c);
    case(m)
      0:nweights=9;
      1:nweights=9+{3'd0,c};
      2:nweights=7'd9*{3'd0,c};
      3:nweights={3'd0,c};
      default:nweights=0;
    endcase
  endfunction
  wire [6:0] wc=nweights(mode,cin);
  wire [8:0] wb=({2'd0,wc}+9'd3)>>2;
  // A regular 3x3 descriptor may carry an 18x18 pre-packed halo for a
  // 16x16 output tile. The descriptor shape remains the input shape; derive
  // the emitted-window dimensions separately for output/PSUM storage.
  function automatic [5:0] conv_output_dim(input [2:0] m,
                                            input [5:0] dim,
                                            input pad,
                                            input stride2);
    begin
      if (m == 4)
        conv_output_dim = 6'd1;
      else if (m == 3 || pad)
        conv_output_dim = stride2 ? ((dim + 6'd1) >> 1) : dim;
      else if (dim < 6'd3)
        conv_output_dim = 6'd0;
      else
        conv_output_dim = stride2 ? ((dim - 6'd1) >> 1) : (dim - 6'd2);
    end
  endfunction
  wire [11:0] npixels={6'd0,width}*{6'd0,height};
  wire [11:0] nelements=gemm?{4'd0,k}:npixels;
  wire [2:0] incoming_mode=cmd_desc[2:0];
  wire [3:0] incoming_cin=cmd_desc[115:112],incoming_cout=cmd_desc[119:116];
  wire [5:0] incoming_width=cmd_desc[101:96],incoming_height=cmd_desc[109:104];
  wire [7:0] incoming_k=cmd_desc[127:120];
  wire incoming_reuse=cmd_desc[9];
  wire incoming_keep=cmd_desc[10];
  wire incoming_psum=cmd_desc[11];
  wire incoming_psum_final=cmd_desc[12];
  wire incoming_psum_start=cmd_desc[13];
  wire incoming_q24=cmd_desc[14];
  wire [5:0] incoming_output_width=conv_output_dim(
      incoming_mode,incoming_width,cmd_desc[3],cmd_desc[4]);
  wire [5:0] incoming_output_height=conv_output_dim(
      incoming_mode,incoming_height,cmd_desc[3],cmd_desc[4]);
  wire [11:0] incoming_output_pixels={6'd0,incoming_output_width}
      *{6'd0,incoming_output_height};
  // Timing-17: for unsigned 6-bit output dimensions, W*H > LIMIT is
  // exactly H > floor(LIMIT/W). Clamp the constant threshold to 63;
  // W==0 has zero product and must never exceed capacity. Only this
  // validation predicate uses the table; DMA/address arithmetic is unchanged.
  function automatic [5:0] clamp_psum_height(input [31:0] quotient);
    clamp_psum_height=(quotient>32'd63) ? 6'd63 : quotient[5:0];
  endfunction
  function automatic [5:0] psum_height_limit(input [5:0] output_width);
    case (output_width)
      6'd0: psum_height_limit=6'd63;
      6'd1: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd1);
      6'd2: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd2);
      6'd3: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd3);
      6'd4: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd4);
      6'd5: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd5);
      6'd6: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd6);
      6'd7: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd7);
      6'd8: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd8);
      6'd9: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd9);
      6'd10: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd10);
      6'd11: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd11);
      6'd12: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd12);
      6'd13: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd13);
      6'd14: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd14);
      6'd15: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd15);
      6'd16: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd16);
      6'd17: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd17);
      6'd18: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd18);
      6'd19: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd19);
      6'd20: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd20);
      6'd21: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd21);
      6'd22: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd22);
      6'd23: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd23);
      6'd24: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd24);
      6'd25: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd25);
      6'd26: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd26);
      6'd27: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd27);
      6'd28: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd28);
      6'd29: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd29);
      6'd30: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd30);
      6'd31: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd31);
      6'd32: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd32);
      6'd33: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd33);
      6'd34: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd34);
      6'd35: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd35);
      6'd36: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd36);
      6'd37: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd37);
      6'd38: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd38);
      6'd39: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd39);
      6'd40: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd40);
      6'd41: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd41);
      6'd42: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd42);
      6'd43: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd43);
      6'd44: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd44);
      6'd45: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd45);
      6'd46: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd46);
      6'd47: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd47);
      6'd48: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd48);
      6'd49: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd49);
      6'd50: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd50);
      6'd51: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd51);
      6'd52: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd52);
      6'd53: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd53);
      6'd54: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd54);
      6'd55: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd55);
      6'd56: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd56);
      6'd57: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd57);
      6'd58: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd58);
      6'd59: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd59);
      6'd60: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd60);
      6'd61: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd61);
      6'd62: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd62);
      6'd63: psum_height_limit=clamp_psum_height({20'd0,OUTPUT_LIMIT}/32'd63);
      default: psum_height_limit=6'd63;
    endcase
  endfunction
  wire incoming_psum_too_large = incoming_output_height
      > psum_height_limit(incoming_output_width);
  function automatic q24_multiplier_bad(input [255:0] params);
    integer qp;
    begin
      q24_multiplier_bad=1'b0;
      for(qp=0;qp<8;qp=qp+1)
        if(|params[qp*32+24 +: 8]) q24_multiplier_bad=1'b1;
    end
  endfunction
  // The production pixel adapter intentionally consumes an unsigned 24-bit
  // multiplier.  Reject non-zero sideband high bits at descriptor acceptance
  // instead of silently truncating them in ai_postprocess_q24_pixel.
  wire incoming_q24_multiplier_bad = q24_multiplier_bad(q24_param_multiplier_q24);
  wire k_exceeds_limit;
  generate if (MAX_K < 255) begin:g_k_limit
    assign k_exceeds_limit=incoming_k>K_LIMIT;
  end else begin:g_full_k_range
    assign k_exceeds_limit=1'b0;
  end endgenerate
  wire [11:0] incoming_pixels={6'd0,incoming_width}*{6'd0,incoming_height};
  wire [11:0] incoming_beats = incoming_mode==4
     ? ({4'd0,incoming_k}+12'd2)/12'd3
     : (({5'd0,nweights(incoming_mode,incoming_cin)}+12'd3)>>2)
       + (incoming_reuse ? 12'd0 : ((incoming_pixels+12'd3)>>2));
  wire [32:0] read_end={1'b0,cmd_desc[63:32]}+{16'd0,incoming_beats,5'd0};
  // A is the unsigned 32-bit byte address; P is the unsigned 12-bit
  // pixel count. For B=ceil(P/4), low+B>=1024 iff P>4*(1023-low).
  // Comparing P with the address-only threshold removes beat rounding
  // and address addition from this path. End == 2^32 still overflows.
  // P==0 never overflows; GEMM always writes one 32-byte beat.
  // A[4:0] cannot carry for a multiple-of-32 increment, even if unaligned.
  // Timing-17A: parallel 4/4/2-bit comparisons instead of feeding the
  // product's low bits through a full 12-bit compare carry chain.
  // The threshold's low two bits are zero; equality of its upper ten
  // bits overflows iff either of the product's low two bits is nonzero.
  function automatic output_pixels_exceed_free(input [11:0] pixels,
                                                input [9:0] free_words);
    reg hi_gt,hi_eq,mid_gt,mid_eq,lo_gt,lo_eq;
    begin
      hi_gt=pixels[11:8]>free_words[9:6];
      hi_eq=pixels[11:8]==free_words[9:6];
      mid_gt=pixels[7:4]>free_words[5:2];
      mid_eq=pixels[7:4]==free_words[5:2];
      lo_gt=pixels[3:2]>free_words[1:0];
      lo_eq=pixels[3:2]==free_words[1:0];
      output_pixels_exceed_free=hi_gt || (hi_eq && mid_gt)
          || (hi_eq && mid_eq && (lo_gt || (lo_eq && (|pixels[1:0]))));
    end
  endfunction
  wire write_overflow = incoming_mode==4 ? (&cmd_desc[95:69])
       : ((&cmd_desc[95:79])
          && output_pixels_exceed_free(incoming_output_pixels,~cmd_desc[78:69]));
  wire unused_end_low=^read_end[31:0];
  wire invalid_base=(incoming_mode>4) || cmd_desc[36:32]!=0 || cmd_desc[68:64]!=0
       || (incoming_q24 && !q24_param_valid)
       || (incoming_q24 && q24_param_valid && incoming_q24_multiplier_bad)
       // Q24 is the final INT8 boundary of standalone DW/CONV/PW or PW PSUM.
       // Fused mode still has a legacy intermediate DW quantizer; GEMM emits
       // INT32 words. Reject these combinations instead of silently bypassing.
       || (incoming_q24 && (incoming_mode==1 || incoming_mode==4))
       || (incoming_q24 && q24_param_relu6 && q24_param_relu6_max[7])
       || (incoming_mode==4 && (incoming_reuse || incoming_keep))
       || (incoming_psum && ((incoming_mode!=2 && incoming_mode!=3)
                             || incoming_reuse || incoming_keep
                             || incoming_psum_final && !incoming_psum
                             || incoming_psum_too_large))
       || (!incoming_psum && (incoming_psum_final || incoming_psum_start))
       || incoming_cout==0 || incoming_cout>8 || read_end[32]
       || incoming_beats>INPUT_LIMIT
       || ((incoming_mode==4)
           ? (incoming_k==0 || k_exceeds_limit || incoming_cin!=1
              // Keep the legacy GEMM boundary-rejection contract.
              || ({1'b0,cmd_desc[43:32]}+{1'b0,incoming_beats[6:0],5'd0}>13'd4096))
           : (incoming_width==0 || incoming_height==0
              || incoming_width>WIDTH_LIMIT || incoming_height>HEIGHT_LIMIT
              || incoming_cin==0 || incoming_cin>8
              || (incoming_mode==0 && incoming_cin!=incoming_cout)
              || (cmd_desc[7] && cmd_desc[159])
              || (cmd_desc[8] && cmd_desc[167])));
  // Preserve the combinational arithmetic view used by existing differential
  // tests. It has no production consumer and is removed by synthesis.
  wire invalid=invalid_base || write_overflow;
  wire accepted_write_overflow = desc_accept_q[2:0]==4
       ? (&desc_accept_q[95:69])
       : ((&desc_accept_q[95:79])
          && output_pixels_exceed_free(desc_accept_output_pixels_q,
                                       ~desc_accept_q[78:69]));
  wire accepted_invalid=desc_accept_invalid_base_q || accepted_write_overflow;
  reg [31:0] load_addr;
  reg [11:0] remaining;
  reg [IA-1:0] load_index;
  // The input RAM is synchronous and returns the old word on a same-address
  // read/write.  Delay the accepted-beat watermark by one clock so a newly
  // written beat is never offered to the core until its read port has seen it.
  reg [11:0] readable_beats;
  reg [7:0] rb_count,rb_index;
  // Limit bursts to 16 beats and never cross 4 KiB.
  function automatic [7:0] burst_len(input [31:0] unused_addr,input [11:0] count);
    reg [12:0] boundary;
    reg [11:0] n;
    begin
      boundary=(13'd4096-{1'b0,unused_addr[11:0]})>>5;
      n=(count>16)?12'd16:count;
      if({1'b0,n}>boundary) n=boundary[11:0];
      burst_len=n[7:0];
    end
  endfunction
  integer qidx;
  function automatic [2:0] first_load_slot(input [7:0] mask);
    begin
      if (|mask[3:0]) begin
        if (|mask[1:0]) first_load_slot=mask[0]?3'd0:3'd1;
        else first_load_slot=mask[2]?3'd2:3'd3;
      end else begin
        if (|mask[5:4]) first_load_slot=mask[4]?3'd4:3'd5;
        else first_load_slot=mask[6]?3'd6:3'd7;
      end
    end
  endfunction
  function automatic [3:0] pick_load(input [2:0] head,
                                     input [7:0] ready_mask,
                                     input [1:0] banks);
    reg [7:0] after_head;
    begin
      after_head=ready_mask & (8'hff << head);
      if ((&banks) || !(|ready_mask)) pick_load={1'b0,head};
      else pick_load={1'b1,(|after_head) ? first_load_slot(after_head)
                                        : first_load_slot(ready_mask)};
    end
  endfunction
  // Committed occupied slots are inside the reserved head/count interval.
  // Build readiness per physical slot; a pair of fixed priority encoders
  // implements the same oldest-first ring order without dynamic bit reads.
  wire [7:0] load_ready_mask=occupied & ~loaded & ~slot_has_bank;
  wire [3:0] load_pick=pick_load(q_head,load_ready_mask,bank_busy);
  reg load_candidate_valid;
  reg [QW-1:0] load_candidate_slot;
  reg load_candidate_bank;
  wire [703:0] load_d=descriptors[load_candidate_slot];
  wire unused_load_d=^load_d;
  wire [11:0] load_beats=queued_beats[load_candidate_slot];
  always @* begin
    load_candidate_valid=load_pick[3];
    load_candidate_slot=load_pick[2:0];
    load_candidate_bank=!bank_busy[0] ? 1'b0 : 1'b1;
  end
  assign cmd_ready=(q_count<QUEUE_LIMIT);
  assign busy=(q_count!=0)||(ls!=L_IDLE)||(es!=E_IDLE)||(ws!=W_IDLE);
  assign m_arvalid=(ls==L_ADDR);
  assign m_araddr=load_addr;
  assign m_arlen=rb_count-8'd1;
  assign m_arid=AXI_ID; assign m_arsize=5; assign m_arburst=1;
  assign m_rready=(ls==L_DATA)||(ls==L_DRAIN);
  wire read_ok=(m_rresp==0)&&(m_rid==AXI_ID);
  wire tile_we=(ls==L_DATA)&&m_rvalid&&read_ok;
  reg [IA-1:0] in_beat;
  reg [1:0] in_sub;
  // Timing-15A: remaining input tokens/pixels. Load once at the existing
  // execution-start boundary; only accepted core inputs consume this count.
  // This keeps descriptor dimensions/multiplication out of per-input ready.
  reg [11:0] in_index;
  reg [6:0] weight_index;
  wire cr,ir,ov,cd,ce,unused_cb,wr;
  wire [63:0] op;
  wire [255:0] og;
  wire [255:0] raw_accum;
  wire [63:0] unused_busy,unused_is,unused_os;
  wire [5:0] unused_x,unused_y;
  wire loading_head=slot_has_bank[q_head] && load_slot==q_head && ls!=L_IDLE;
  wire beat_ready=loaded_safe[q_head] || failed[q_head]
                  || (loading_head && { {(12-IA){1'b0}},in_beat}<readable_beats);
  wire weight_ready_to_send=(es==E_WEIGHT) && beat_ready;
  wire input_ready_to_send=(es==E_RUN) && (in_index!=12'd0)
                            && (reuse_input || beat_ready);
  // Elastic register cuts the tile-RAM/mode mux -> core/APM path. Cursor
  // advancement belongs to the buffer's input handshake, not the core's.
  reg token_valid_q;
  reg [71:0] token_q /* synthesis syn_preserve=1 syn_keep=1 */;
  wire token_space=!token_valid_q || ir;
  wire input_fetch=input_ready_to_send && token_space;
  wire consume=(weight_ready_to_send && wr)||input_fetch;
  wire last_sub=gemm ? (in_sub==2) : (in_sub==3);
  wire [IA-1:0] ram_ra=(consume && last_sub)?in_beat+1'b1:in_beat;
  wire [255:0] ram_data;
  ai_tile_buffer_v1c #(.DEPTH(INPUT_BEATS),.DATA_WIDTH(256)) input_i(
    .clk(clk),.write_bank(load_bank),.write_valid(tile_we),
    .write_addr(load_index),.write_data(m_rdata),
    .read_bank(exec_bank),.read_addr(ram_ra),.read_data(ram_data));
  wire [255:0] pixel_beat;
  wire [71:0] token=failed[q_head] ? 72'd0
       : gemm ? ram_data[in_sub*72+:72]
              : {8'd0,pixel_beat[in_sub*64+:64]};
  ai_compute_core_v1 #(.MAX_K(MAX_K),.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT)) core_i(
    .clk(clk),.rst_n(rst_n),
    .weight_valid(weight_ready_to_send),.weight_ready(wr),.weight_addr(weight_index),
    .weight_data(failed[q_head] ? 64'd0 : ram_data[in_sub*64+:64]),
    .cfg_valid(es==E_CFG),.cfg_ready(cr),.cfg_mode(mode),.cfg_k({8'd0,k}),
    .cfg_width(width),.cfg_height(height),.cfg_pad_same(d[3]),.cfg_stride2(d[4]),
    .cfg_in_channels(cin),.cfg_out_channels(cout),
    .cfg_stage0_bias(d[447:192]),.cfg_stage1_bias(d[703:448]),
    .cfg_stage0_shift(d[132:128]),.cfg_stage1_shift(d[140:136]),
    .cfg_gemm_shift(d[149:144]),
    .cfg_stage0_relu(d[5]),.cfg_stage1_relu(d[6]),
    .cfg_stage0_relu6(d[7]),.cfg_stage1_relu6(d[8]),
    .cfg_stage0_relu6_max(d[159:152]),.cfg_stage1_relu6_max(d[167:160]),
    .in_valid(token_valid_q),.in_ready(ir),.in_token(token_q),
    .out_valid(ov),.out_ready(core_out_ready),.out_pixel(op),.out_data(og),
    .out_accum(raw_accum),
    .out_x(unused_x),.out_y(unused_y),.done(cd),.error(ce),.busy(unused_cb),
    .perf_mac_count(perf_mac_count),.perf_busy_cycles(unused_busy),
    .perf_input_stall_cycles(unused_is),.perf_output_stall_cycles(unused_os));

  // Ping-pong output tiles retain the previous layer while the current layer
  // writes the opposite bank. Only weights need an AXI read for a reused input.
  reg [255:0] output_mem[0:OUTPUT_BEATS-1];
  reg [255:0] output_mem1[0:OUTPUT_BEATS-1];
  // One INT32 partial sum per lane for each spatial position. It is used
  // when a descriptor explicitly enables PW or regular-Conv channel tiling.
  reg [255:0] psum_mem[0:OUTPUT_BEATS-1];
  reg [255:0] pack, output_read0, output_read1;
  reg output_bank, prev_bank, prev_valid;
  reg [11:0] prev_pixels;
  reg [3:0] prev_channels;
  assign pixel_beat = reuse_input ? (prev_bank ? output_read1 : output_read0)
                                  : ram_data;
  reg [1:0] pack_sub;
  reg [OA:0] output_count;
  reg [OA:0] out_index;
  wire [11:0] output_count_wide={{(11-OA){1'b0}},output_count};
  wire [11:0] out_index_wide={{(11-OA){1'b0}},out_index};
  reg [7:0] write_count,write_index;
  reg [31:0] write_addr;
  reg [31:0] tail_strb;
  reg result_error, write_failed;
  reg [PA-1:0] psum_index;
  // Registered read plus one-entry output pipeline lets PDS infer a dual-port
  // RAM for psum_mem.  The old asynchronous read mapped 2,048 LUT RAM bits.
  reg [PA-1:0] psum_read_addr;
  reg psum_pending;
  reg [255:0] psum_pending_raw;
  reg [255:0] psum_prev_sync;
  // Timing-7: isolate DRM read + INT32 PSUM addition from final legacy
  // shift/activation. Final legacy Bias is retimed into this II=1 stage.
  // PSUM RAM writes retain their original address/commit boundary; Q24 has
  // its own input registers and retains its existing ready/valid contract.
  // Retimed within the existing II=1 stage: first wrap the PSUM to INT32,
  // then add signed Bias at 33 bits before this register boundary.
  reg [263:0] psum_legacy_biased_q;
  reg psum_legacy_sum_valid_q;
  // Timing-9: descriptor parameters used by the legacy PSUM postprocess are
  // captured when the queue head starts execution.  This removes the
  // descriptor RAM/q_head read from the PSUM sum -> postprocess path while
  // keeping the descriptor fixed until the tile is drained and retired.
  reg [255:0] psum_legacy_bias_q;
  wire [4:0] psum_legacy_shift_q=g_psum_post_lane[0].shift_q;
  wire psum_legacy_relu_q=g_psum_post_lane[0].relu_q;
  wire psum_legacy_relu6_q=g_psum_post_lane[0].relu6_q;
  wire signed [7:0] psum_legacy_relu6_max_q=g_psum_post_lane[0].max_q;
  // Legacy (non-Q24) PSUM results cross a register before packing/output.
  // Q24 keeps its existing adapter timing; this stage targets the measured
  // PSUM -> ai_postprocess_v1 -> output RAM path without changing PSUM
  // address/read semantics.
  reg psum_legacy_pending;
  reg [63:0] psum_legacy_pixel_q;
  wire [255:0] unused_psum_result32;
  wire q24_adapter_in_ready;
  wire q24_adapter_out_valid;
  wire q24_adapter_out_ready;
  wire [63:0] q24_adapter_pixel;
  wire q24_adapter_busy;
  wire [31:0] q24_scalar_stall_cycles;
  assign perf_q24_scalar_stall_cycles = q24_scalar_stall_cycles;
  wire [255:0] psum_sum;
  wire [63:0] psum_quant_pixel;
  // A final Q24 tile is committed only when the shared scalar serializer can
  // accept it.  This turns its one-entry output into explicit backpressure on
  // the PSUM pipeline instead of dropping a pixel while it is busy.
  wire q24_direct = q24_enable && !psum_enable;
  wire q24_wait = q24_enable && !q24_adapter_in_ready
                && (psum_enable ? (psum_final && psum_pending) : ov);
  wire core_out_ready = (es==E_RUN) && !q24_wait;
  wire out_accept = core_out_ready && ov;
  wire psum_commit = psum_enable && psum_pending
                   && (!q24_enable || !psum_final || q24_adapter_in_ready);
  wire q24_start = (psum_commit && q24_enable && psum_final)
                || (out_accept && q24_direct);
  wire [255:0] q24_final_accum = psum_enable ? psum_sum : raw_accum;
  wire [63:0] q24_masked_pixel;
  genvar q24_lane;
  generate for(q24_lane=0;q24_lane<8;q24_lane=q24_lane+1) begin:g_q24_mask
    assign q24_masked_pixel[q24_lane*8+:8] = (q24_lane<cout)
        ? q24_adapter_pixel[q24_lane*8+:8] : 8'd0;
  end endgenerate
  wire [63:0] output_pixel = q24_adapter_out_valid ? q24_masked_pixel
                              : (psum_legacy_pending ? psum_legacy_pixel_q : op);
  genvar psum_lane;
  generate for(psum_lane=0; psum_lane<8; psum_lane=psum_lane+1) begin:g_psum_add
    assign psum_sum[psum_lane*32 +: 32] =
      psum_prev_sync[psum_lane*32 +: 32]
      + psum_pending_raw[psum_lane*32 +: 32];
  end endgenerate
  function automatic [263:0] legacy_final_bias_sum(input [255:0] final_sum,bias_params);
    integer lane;
    reg signed [31:0] a,bi;
    begin
      for(lane=0;lane<8;lane=lane+1)begin
        a=final_sum[lane*32+:32];
        bi=bias_params[lane*32+:32];
        legacy_final_bias_sum[lane*33+:33]=$signed({a[31],a})+$signed({bi[31],bi});
      end
    end
  endfunction
  // Exact existing E_IDLE start predicate, including streamed partial loads.
  wire legacy_psum_cfg_capture=(es==E_IDLE) && exec_descriptor_valid && occupied[q_head] &&
      (loaded[q_head] || (!failed[q_head] && !gemm && loading_head && readable_beats!=0));
  wire [255:0] descriptor_bias_source=d[703:448];
  wire [(256)-1:0] legacy_bias_delayed;
  genvar legacy_bias_bit;
  generate for(legacy_bias_bit=0;legacy_bias_bit<(256);legacy_bias_bit=legacy_bias_bit+1)begin:g_legacy_bias
    if(legacy_bias_bit==98 || legacy_bias_bit==106 || legacy_bias_bit==247 || legacy_bias_bit==246)begin:g_pad
      ai_sparse_hold_pad #(.STAGES(2)) timingHoldA21_pad(.data_in(psum_legacy_bias_q[legacy_bias_bit]),.data_out(legacy_bias_delayed[legacy_bias_bit]));
    end else assign legacy_bias_delayed[legacy_bias_bit]=psum_legacy_bias_q[legacy_bias_bit];
  end endgenerate
  wire [(256)-1:0] pending_raw_delayed;
  genvar pending_raw_bit;
  generate for(pending_raw_bit=0;pending_raw_bit<(256);pending_raw_bit=pending_raw_bit+1)begin:g_pending_raw
    if(pending_raw_bit==101 || pending_raw_bit==108 || pending_raw_bit==109)begin:g_pad
      ai_sparse_hold_pad #(.STAGES(2)) timingHoldA21_pad(.data_in(raw_accum[pending_raw_bit]),.data_out(pending_raw_delayed[pending_raw_bit]));
    end else assign pending_raw_delayed[pending_raw_bit]=raw_accum[pending_raw_bit];
  end endgenerate
  wire [(256)-1:0] q24_bias_capture_delayed;
  genvar q24_bias_bit;
  generate for(q24_bias_bit=0;q24_bias_bit<(256);q24_bias_bit=q24_bias_bit+1)begin:g_q24_bias
    if(q24_bias_bit==112)begin:g_pad
      ai_sparse_hold_pad #(.STAGES(2)) timingHoldA21_pad(.data_in(q24_param_bias[q24_bias_bit]),.data_out(q24_bias_capture_delayed[q24_bias_bit]));
    end else assign q24_bias_capture_delayed[q24_bias_bit]=q24_param_bias[q24_bias_bit];
  end endgenerate
  wire [(256)-1:0] descriptor_bias_capture_delayed;
  genvar descriptor_bias_bit;
  generate for(descriptor_bias_bit=0;descriptor_bias_bit<(256);descriptor_bias_bit=descriptor_bias_bit+1)begin:g_descriptor_bias
    if(descriptor_bias_bit==231)begin:g_pad
      ai_sparse_hold_pad #(.STAGES(2)) timingHoldA21_pad(.data_in(descriptor_bias_source[descriptor_bias_bit]),.data_out(descriptor_bias_capture_delayed[descriptor_bias_bit]));
    end else assign descriptor_bias_capture_delayed[descriptor_bias_bit]=descriptor_bias_source[descriptor_bias_bit];
  end endgenerate
  wire [255:0] a24_exec_bias_read=q24_bias_q[q_head];
  wire [(256)-1:0] a24_exec_bias_capture;
  genvar a24_exec_bias_bit;
  generate for(a24_exec_bias_bit=0;a24_exec_bias_bit<(256);a24_exec_bias_bit=a24_exec_bias_bit+1)begin:g_a24_exec_bias
    if(a24_exec_bias_bit==50)begin:g_pad
      ai_sparse_hold_pad #(.STAGES(2)) timingHoldA21_pad(.data_in(a24_exec_bias_read[a24_exec_bias_bit]),.data_out(a24_exec_bias_capture[a24_exec_bias_bit]));
    end else assign a24_exec_bias_capture[a24_exec_bias_bit]=a24_exec_bias_read[a24_exec_bias_bit];
  end endgenerate
  wire [(704)-1:0] a24_desc_capture;
  genvar a24_desc_bit;
  generate for(a24_desc_bit=0;a24_desc_bit<(704);a24_desc_bit=a24_desc_bit+1)begin:g_a24_desc
    if(a24_desc_bit==621)begin:g_pad
      ai_sparse_hold_pad #(.STAGES(2)) timingHoldA21_pad(.data_in(cmd_desc[a24_desc_bit]),.data_out(a24_desc_capture[a24_desc_bit]));
    end else assign a24_desc_capture[a24_desc_bit]=cmd_desc[a24_desc_bit];
  end endgenerate
  genvar pl;
  generate for(pl=0;pl<8;pl=pl+1)begin:g_psum_post_lane
    reg [4:0] shift_q /* synthesis syn_preserve=1 syn_keep=1 */;
    reg relu_q /* synthesis syn_preserve=1 syn_keep=1 */;
    reg relu6_q /* synthesis syn_preserve=1 syn_keep=1 */;
    reg signed [7:0] max_q /* synthesis syn_preserve=1 syn_keep=1 */;
    always @(posedge clk or negedge rst_n)
      if(!rst_n)begin shift_q<=0;relu_q<=0;relu6_q<=0;max_q<=0;end
      else if(legacy_psum_cfg_capture)begin
        shift_q<=d[140:136];relu_q<=d[6];relu6_q<=d[8];max_q<=d[167:160];
      end
    wire relu_delayed, relu6_delayed;
    wire [7:0] max_delayed;
    if(pl==5)begin:g_relu_hold
      ai_sparse_hold_pad #(.STAGES(4)) timingHoldA21_relu(.data_in(relu_q),.data_out(relu_delayed));
    end else if(pl==2)begin:g_relu_hold_a24
      ai_sparse_hold_pad #(.STAGES(2)) timingHoldA24_relu(.data_in(relu_q),.data_out(relu_delayed));
    end else assign relu_delayed=relu_q;
    if(pl==2)begin:g_relu6_max_hold
      ai_sparse_hold_pad #(.STAGES(4)) timingHoldA21_relu6(.data_in(relu6_q),.data_out(relu6_delayed));
      ai_sparse_hold_pad #(.STAGES(4)) timingHoldA21_max0(.data_in(max_q[0]),.data_out(max_delayed[0]));
      assign max_delayed[7:1]=max_q[7:1];
    end else begin:g_other_ctrl
      assign relu6_delayed=relu6_q;
      assign max_delayed=max_q;
    end
    ai_postprocess_shift_v1 #(.LANES(1),.PRECOMPUTED_CTRL(1)) psum_quant_i (
      .biased(psum_legacy_biased_q[pl*33+:33]),.gemm(1'b0),.shift(6'sd0),
      .relu(relu_delayed),.relu6(relu6_delayed),.relu6_max(max_delayed),
      .precomputed_left(1'b0),.precomputed_amount({1'b0,shift_q}),
      .precomputed_relu6_zero(relu6_delayed),
      .result8(psum_quant_pixel[pl*8+:8]),
      .result32(unused_psum_result32[pl*32+:32])
    );
  end endgenerate
  ai_postprocess_q24_pixel q24_pixel_i (
    .clk(clk), .rst_n(rst_n),
    .param_valid(q24_start),
    .param_bias(q24_bias_tile), .param_multiplier_q24(q24_multiplier_tile),
    .param_relu(q24_relu_tile), .param_relu6(q24_relu6_tile),
    .param_relu6_max(q24_relu6_max_tile),
    .in_valid(q24_start), .in_ready(q24_adapter_in_ready),
    .in_accum(q24_final_accum), .in_channel_base(q24_channel_base),
    .out_valid(q24_adapter_out_valid), .out_ready(q24_adapter_out_ready),
    .out_pixel(q24_adapter_pixel), .busy(q24_adapter_busy),
    .perf_scalar_stall_cycles(q24_scalar_stall_cycles)
  );
  assign q24_adapter_out_ready = q24_adapter_out_valid;
  // A burst is issued only after every W beat is committed to the output
  // RAM. Nigo's fabric owns an entire burst once it accepts AW; issuing an
  // incomplete burst could otherwise block the AR needed to produce it.
  wire [7:0] full_write_count=burst_len(write_addr,12'd16);
  wire [11:0] produced_pending=output_count_wide-out_index_wide;
  wire writer_can_start=(es==E_RUN || es==E_FLUSH || es==E_DRAIN)
      && occupied[q_head] && loaded[q_head] && !failed[q_head]
      && !result_error && !write_failed && !keep_output
      && !q24_adapter_busy
      && (!psum_enable || psum_final)
      && (produced_pending>={4'd0,full_write_count}
          || (es==E_DRAIN && produced_pending!=0));
  wire [7:0] next_write_count=(produced_pending>={4'd0,full_write_count})
      ? full_write_count : burst_len(write_addr,produced_pending);
  wire push_cmd=cmd_valid&&cmd_ready;
  wire retire_cmd=(es==E_RETIRE);
  always @(posedge clk)
    if (rst_n && push_cmd) begin
      desc_accept_q<=a24_desc_capture;
      desc_accept_output_pixels_q<=incoming_output_pixels;
      // Sideband validity/range is sampled at acceptance, never at commit.
      desc_accept_invalid_base_q<=invalid_base;
    end
  always @(posedge clk or negedge rst_n)
    if (!rst_n) begin desc_accept_valid_q<=0;desc_accept_slot_q<=0;end
    else begin
      desc_accept_valid_q<=push_cmd;
      if (push_cmd) desc_accept_slot_q<=q_tail;
    end
  // Native falling-edge FFs, already verified in the standalone PGL50H probe.
  // Data, write address and write enable all cross the same existing half-cycle.
  always @(negedge clk)
    if (rst_n && desc_accept_valid_q) desc_write_n<=desc_accept_q;
  always @(negedge clk or negedge rst_n)
    if (!rst_n) begin desc_write_valid_n<=0;desc_write_slot_n<=0;end
    else begin
      desc_write_valid_n<=desc_accept_valid_q;
      if (desc_accept_valid_q) desc_write_slot_n<=desc_accept_slot_q;
    end
  always @(posedge clk)
    if (rst_n && desc_write_valid_n) descriptors[desc_write_slot_n]<=desc_write_n;
  wire flush_partial=(es==E_FLUSH)&&!gemm&&(pack_sub!=0)
                    && !q24_adapter_busy && !psum_pending
                    && !psum_legacy_sum_valid_q && !psum_legacy_pending;
  wire output_event=(psum_legacy_pending && !q24_enable)
                  || (q24_adapter_out_valid && q24_adapter_out_ready)
                  || (out_accept && !psum_enable && !q24_enable);
  wire output_we=(output_event && (gemm || pack_sub==3)) || flush_partial;
  wire [255:0] packed_full={output_pixel,pack[191:0]};
  wire [255:0] output_wdata=flush_partial?pack:(gemm?og:packed_full);
  wire [OA-1:0] writer_ra=(ws==W_DATA && m_wready)
                              ? out_index[OA-1:0]+1'b1 : out_index[OA-1:0];
  // The previous and current output tiles always occupy opposite banks for
  // reuse_input. Give each existing SDP RAM its own read address so a reused
  // pixel stream and background writeback can proceed in the same cycle.
  wire [OA-1:0] output_ra0=(es==E_RUN && reuse_input && !prev_bank)
                                ? ram_ra[OA-1:0] : writer_ra;
  wire [OA-1:0] output_ra1=(es==E_RUN && reuse_input && prev_bank)
                                ? ram_ra[OA-1:0] : writer_ra;
  always @(posedge clk) begin
    if(output_we && !output_bank) output_mem[output_count[OA-1:0]]<=output_wdata;
    if(output_we && output_bank) output_mem1[output_count[OA-1:0]]<=output_wdata;
    output_read0<=output_mem[output_ra0];
    output_read1<=output_mem1[output_ra1];
    // With the scalar Q24 serializer, a pending output can wait several
    // cycles.  Freeze the registered PSUM read during that wait so the
    // synchronous RAM does not advance past the channel tile being consumed.
    if (!q24_adapter_busy || q24_start)
      psum_prev_sync<=psum_start ? 256'd0 : psum_mem[psum_read_addr];
  end
  assign m_awvalid=(ws==W_AW); assign m_awaddr=write_addr;
  assign m_awid=AXI_ID; assign m_awlen=write_count-8'd1;
  assign m_awsize=5; assign m_awburst=1;
  assign m_wvalid=(ws==W_DATA);
  assign m_wdata=output_bank ? output_read1 : output_read0;
  assign m_wstrb=(es==E_DRAIN && out_index+1'b1==output_count)
      ? tail_strb : 32'hffffffff;
  assign m_wlast=(write_index+8'd1==write_count);
  assign m_bready=(ws==W_RESP);
  function automatic [31:0] gemm_strobe(input [3:0] c);
    case(c)
      1:gemm_strobe=32'hf; 2:gemm_strobe=32'hff;
      3:gemm_strobe=32'hfff; 4:gemm_strobe=32'hffff;
      5:gemm_strobe=32'hfffff; 6:gemm_strobe=32'hffffff;
      7:gemm_strobe=32'hfffffff; 8:gemm_strobe=32'hffffffff;
      default:gemm_strobe=0;
    endcase
  endfunction
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      ls<=L_IDLE; es<=E_IDLE; ws<=W_IDLE; q_head<=0;q_tail<=0;load_slot<=0;
      load_bank<=0;exec_bank<=0;q_count<=0;
      exec_descriptor<=0;exec_descriptor_valid<=0;
      exec_q24_enable<=0;exec_bias<=0;exec_multiplier<=0;
      exec_relu<=0;exec_relu6<=0;exec_relu6_max<=0;
      token_valid_q<=0;token_q<=0;
      occupied<=0;loaded<=0;loaded_safe<=0;failed<=0;slot_has_bank<=0;slot_bank<=0;
      q24_sideband_q<=0;
      for(qidx=0;qidx<QUEUE_DEPTH;qidx=qidx+1) begin
        q24_bias_q[qidx]<=0;
        q24_multiplier_q[qidx]<=0;
        q24_relu_q[qidx]<=0;
        q24_relu6_q[qidx]<=0;
        q24_relu6_max_q[qidx]<=0;
      end
      bank_busy<=0;load_addr<=0;remaining<=0;
      load_index<=0;readable_beats<=0;rb_count<=0;rb_index<=0;
      in_beat<=0;in_sub<=0;in_index<=0;weight_index<=0;
          pack<=0;pack_sub<=0;output_count<=0;out_index<=0;
      psum_index<=0;psum_read_addr<=0;psum_pending<=0;
      psum_pending_raw<=0;
      psum_legacy_biased_q<=0;psum_legacy_sum_valid_q<=0;
      psum_legacy_bias_q<=0;
      psum_legacy_pending<=0;psum_legacy_pixel_q<=0;
      output_bank<=0;prev_bank<=0;prev_valid<=0;prev_pixels<=0;prev_channels<=0;
      write_count<=0;write_index<=0;write_addr<=0;tail_strb<=0;
      result_error<=0;write_failed<=0;
      done<=0;error<=0;perf_read_beats<=0;perf_compute_cycles<=0;
      perf_busy_cycles<=0;perf_axi_wait_cycles<=0;perf_overlap_cycles<=0;
    end else begin
      done<=0;
      if(es==E_IDLE) begin
        exec_descriptor<=descriptors[q_head];
        exec_descriptor_valid<=occupied[q_head];
        exec_q24_enable<=q24_sideband_q[q_head];
        exec_bias<=a24_exec_bias_capture;exec_multiplier<=q24_multiplier_q[q_head];
        exec_relu<=q24_relu_q[q_head];exec_relu6<=q24_relu6_q[q_head];
        exec_relu6_max<=q24_relu6_max_q[q_head];
      end
      if(retire_cmd) exec_descriptor_valid<=0;
      if(es!=E_RUN) token_valid_q<=0;
      else if(token_space) begin
        token_valid_q<=input_ready_to_send;
        if(input_ready_to_send)token_q<=token;
      end
      if(busy) perf_busy_cycles<=perf_busy_cycles+1'b1;
      if(es==E_RUN) perf_compute_cycles<=perf_compute_cycles+1'b1;
      if(es==E_RUN && ls!=L_IDLE) perf_overlap_cycles<=perf_overlap_cycles+1'b1;
      if((m_arvalid&&!m_arready)||(m_rready&&!m_rvalid)
         ||(m_awvalid&&!m_awready)||(m_wvalid&&!m_wready)||(m_bready&&!m_bvalid))
        perf_axi_wait_cycles<=perf_axi_wait_cycles+1'b1;
      // loaded is set on the same edge as the final RAM write; it must not
      // bypass the delayed watermark until the RAM read has observed it.
      // Keep this per slot so a newly selected loader cannot invalidate a
      // completed descriptor's readiness.
      loaded_safe<=loaded;
      // q_count includes this reserved slot from the accepting edge. Loader
      // and executor cannot observe it until the descriptor RAM is committed.
      if(desc_write_valid_n) occupied[desc_write_slot_n]<=1'b1;
      // Full-cycle acceptance registers identify exactly the same pending
      // slot as desc_write_* at this edge. This does not extend the half-cycle
      // RAM write path. Pending slots are invisible to loader/executor.
      if(desc_accept_valid_q) begin
        loaded[desc_accept_slot_q]<=accepted_invalid;
        failed[desc_accept_slot_q]<=accepted_invalid;
        // Match the original delayed watermark on the FIRST visible cycle.
        // A newly committed slot cannot yet have an AXI data write to delay.
        loaded_safe[desc_accept_slot_q]<=accepted_invalid;
      end
      if(push_cmd) begin
        queued_beats[q_tail_memory]<=incoming_beats;
        q24_sideband_q[q_tail_memory]<=cmd_desc[14] && q24_param_valid;
        q24_bias_q[q_tail_memory]<=q24_bias_capture_delayed;
        q24_multiplier_q[q_tail_memory]<=q24_param_multiplier_q24;
        q24_relu_q[q_tail_memory]<=q24_param_relu;
        q24_relu6_q[q_tail_memory]<=q24_param_relu6;
        q24_relu6_max_q[q_tail_memory]<=q24_param_relu6_max;
        loaded_safe[q_tail]<=0;
        slot_has_bank[q_tail]<=0;
        q_tail<=q_tail+1'b1;
      end
      // Registered watermark is intentionally one cycle behind load_index.
      // At the following RAM edge, a just-written beat is read back normally.
      readable_beats<={{(12-IA){1'b0}},load_index};
      case ({push_cmd,retire_cmd})
        2'b10:q_count<=q_count+1'b1;
        2'b01:q_count<=q_count-1'b1;
        default:begin end
      endcase
      if (ls==L_IDLE && load_candidate_valid) begin
        load_slot<=load_candidate_slot;
        load_bank<=load_candidate_bank;
        slot_has_bank[load_candidate_slot]<=1;
        slot_bank[load_candidate_slot]<=load_candidate_bank;
        bank_busy[load_candidate_bank]<=1;
        load_addr<=load_d[63:32];
        remaining<=load_beats;
        load_index<=0;
        readable_beats<=0;
        rb_index<=0;
        rb_count<=burst_len(load_d[63:32],load_beats);
        ls<=L_ADDR;
      end
      case(ls)
        L_ADDR:if(m_arready)ls<=L_DATA;
        L_DATA:if(m_rvalid)begin
          perf_read_beats<=perf_read_beats+1'b1;
          if(!read_ok) failed[load_slot]<=1;
          load_index<=load_index+1'b1;
          if(m_rlast)begin
            if(rb_index+8'd1!=rb_count || !read_ok || failed[load_slot])begin
              failed[load_slot]<=1;loaded[load_slot]<=1;ls<=L_IDLE;
            end else if(remaining=={4'd0,rb_count})begin
              loaded[load_slot]<=1;ls<=L_IDLE;
            end else begin
              load_addr<=load_addr+{19'd0,rb_count,5'd0};
              remaining<=remaining-{4'd0,rb_count};rb_index<=0;
              rb_count<=burst_len(load_addr+{19'd0,rb_count,5'd0},
                                 remaining-{4'd0,rb_count});ls<=L_ADDR;
            end
          end else if(rb_index+8'd1==rb_count)begin
            failed[load_slot]<=1;ls<=L_DRAIN;
          end else rb_index<=rb_index+1'b1;
        end
        L_DRAIN:if(m_rvalid)begin
          perf_read_beats<=perf_read_beats+1'b1;
          if(m_rlast)begin loaded[load_slot]<=1;ls<=L_IDLE;end
        end
        default:begin end
      endcase
      // Two consecutive II=1 stages: final INT32 sum + signed Bias, then pixel.
      // q_head (and therefore Bias/shift/activation/mode/output bank) remains
      // fixed until E_FLUSH/E_DRAIN drain both valids. Packing advances only
      // on the pixel valid, preserving spatial order and the final marker.
      // AXI backpressure is absorbed by the existing whole-tile output RAM.
      psum_legacy_sum_valid_q<=psum_commit && psum_final && !q24_enable;
      if(psum_commit && psum_final && !q24_enable)
        psum_legacy_biased_q<=legacy_final_bias_sum(psum_sum,legacy_bias_delayed);
      psum_legacy_pending<=psum_legacy_sum_valid_q;
      if(psum_legacy_sum_valid_q)
        psum_legacy_pixel_q<=psum_quant_pixel;
      // Commit the previous psum pipeline entry and capture the current core
      // result in the same cycle when possible.  This preserves one result per
      // cycle while giving the memory a registered read address.
      if(psum_enable) begin
        if(psum_pending && psum_commit) begin
          psum_mem[psum_index] <= psum_sum;
          psum_index <= psum_index + 1'b1;
        end
        if(out_accept) begin
          psum_pending_raw <= pending_raw_delayed;
          psum_pending <= 1'b1;
          psum_read_addr <= psum_index +
            (psum_commit ? PSUM_TWO : PSUM_ONE);
        end else if(psum_pending && psum_commit) begin
          psum_pending <= 1'b0;
          psum_read_addr <= psum_index + 1'b1;
        end
      end else begin
        psum_pending <= 1'b0;
        if(out_accept && !q24_enable) begin
          if(gemm || pack_sub==3)begin
            output_count<=output_count+1'b1;pack_sub<=0;pack<=0;
          end else begin
            pack[pack_sub*64+:64]<=output_pixel;
            pack_sub<=pack_sub+1'b1;
          end
        end
      end
      if(psum_legacy_pending && !q24_enable) begin
        if(gemm || pack_sub==3)begin
          output_count<=output_count+1'b1;pack_sub<=0;pack<=0;
        end else begin
          pack[pack_sub*64+:64]<=psum_legacy_pixel_q;
          pack_sub<=pack_sub+1'b1;
        end
      end
      if(q24_adapter_out_valid && q24_adapter_out_ready) begin
        if(pack_sub==3)begin
          output_count<=output_count+1'b1;pack_sub<=0;pack<=0;
        end else begin
          pack[pack_sub*64+:64]<=q24_masked_pixel;
          pack_sub<=pack_sub+1'b1;
        end
      end
      case(es)
        E_IDLE:if(legacy_psum_cfg_capture)begin
          // Snapshot all parameters consumed by the legacy PSUM result path
          // before the tile can produce a final sum. q_head cannot advance
          // until both postprocess pipeline stages and output drain finish.
          psum_legacy_bias_q<=descriptor_bias_capture_delayed;
          exec_bank<=slot_bank[q_head];
          result_error<=failed[q_head] || (reuse_input &&
                         (!prev_valid || prev_pixels!=npixels || prev_channels!=cin));
          write_failed<=0;
          write_addr<=d[95:64];
          output_bank<=reuse_input ? !prev_bank : 1'b0;
          pack<=0;pack_sub<=0;output_count<=0;out_index<=0;
          psum_index<=0;psum_read_addr<=0;psum_pending<=0;
          psum_legacy_sum_valid_q<=0;
          psum_legacy_pending<=0;
          in_beat<=0;in_sub<=0;in_index<=nelements;weight_index<=0;
          if(failed[q_head] || (reuse_input &&
             (!prev_valid || prev_pixels!=npixels || prev_channels!=cin)))
            es<=loaded[q_head] ? E_RETIRE : E_FLUSH;
          else es<=gemm?E_CFG:E_WPRIME;
        end
        E_WPRIME:es<=E_WEIGHT;
        E_WEIGHT:if(weight_ready_to_send && wr)begin
          if(weight_index+7'd1==wc)begin
            in_beat<=reuse_input ? {IA{1'b0}} : wb[IA-1:0];in_sub<=0;es<=E_CFG;
          end else begin
            weight_index<=weight_index+1'b1;
            in_sub<=in_sub+1'b1;
            if(in_sub==3)in_beat<=in_beat+1'b1;
          end
        end
        E_CFG:if(cr)es<=E_PRIME;
        E_PRIME:begin
          // Configuration errors complete immediately in the core.
          if(cd)begin
            result_error<=ce;
            es<=loaded[q_head] ? E_RETIRE : E_FLUSH;
          end
          else es<=E_RUN;
        end
        E_RUN:begin
          if(input_fetch)begin
            in_index<=in_index-12'd1;
            if(last_sub)begin in_sub<=0;in_beat<=in_beat+1'b1;end
            else in_sub<=in_sub+1'b1;
          end
          if(cd)begin result_error<=ce || failed[q_head];es<=E_FLUSH;end
        end
        // A late AXI error may arrive after compute has started.  The core
        // completes with zero tokens, but its output is discarded only after
        // the loader drains the response and releases the bank safely.
        E_FLUSH:if(loaded[q_head])begin
          if(psum_pending || psum_legacy_sum_valid_q || psum_legacy_pending
              || q24_adapter_busy) begin
            // Hold the descriptor until the final PSUM has entered and
            // drained the single shared Q24 serializer.
          end
          else if(result_error || failed[q_head]) es<=E_RETIRE;
          else begin
          if(flush_partial)output_count<=output_count+1'b1;
          prev_valid<=keep_output && (output_count!=0 || flush_partial);
          if(keep_output)begin
            prev_bank<=output_bank;
            prev_pixels<=gemm ? 12'd0 : (output_count_wide<<2)
                          + {10'd0,pack_sub};
            prev_channels<=cout;
          end
          tail_strb<=gemm?gemm_strobe(cout):
            (pack_sub==1?32'hff:pack_sub==2?32'hffff:
             pack_sub==3?32'hffffff:32'hffffffff);
          es<=E_DRAIN;
          end
        end
        E_DRAIN:if(ws==W_IDLE && !psum_pending && !psum_legacy_sum_valid_q
                    && !psum_legacy_pending
                    && !q24_adapter_busy && (keep_output || result_error ||
                                 write_failed || out_index==output_count))begin
          if(write_failed)result_error<=1;
          es<=E_RETIRE;
        end
        E_RETIRE:begin
          done<=1;error<=result_error;occupied[q_head]<=0;
          loaded[q_head]<=0;
          if(slot_has_bank[q_head]) begin
            bank_busy[slot_bank[q_head]]<=0;
            slot_has_bank[q_head]<=0;
          end
          q_head<=q_head+1'b1;es<=E_IDLE;
        end
        default:begin end
      endcase
      case(ws)
        W_IDLE:if(writer_can_start)begin
          write_count<=next_write_count;
          write_index<=0;
          ws<=W_AW;
        end
        W_AW:if(m_awready)ws<=W_DATA;
        W_DATA:if(m_wready)begin
          out_index<=out_index+1'b1;
          if(m_wlast)ws<=W_RESP;
          else write_index<=write_index+1'b1;
        end
        W_RESP:if(m_bvalid)begin
          if(m_bresp!=0 || m_bid!=AXI_ID)write_failed<=1;
          write_addr<=write_addr+{19'd0,write_count,5'd0};
          ws<=W_IDLE;
        end
        default:ws<=W_IDLE;
      endcase
    end
  end
endmodule


// An even number of kept LUT inversions is a cycle-neutral identity.
// Actual minimum delay must be checked in the routed fast-corner STA.
module ai_sparse_hold_pad #(parameter WIDTH=1, STAGES=2)(
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
