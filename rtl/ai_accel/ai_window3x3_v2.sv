module ai_window3x3_v2 #(
  parameter integer LANES = 8,
  parameter integer MAX_WIDTH = 32,
  parameter integer MAX_HEIGHT = 32
) (
  input  wire                     clk,
  input  wire                     rst_n,
  input  wire                     cfg_valid,
  output wire                     cfg_ready,
  input  wire [5:0]               cfg_width,
  input  wire [5:0]               cfg_height,
  input  wire                     cfg_pad_same,
  input  wire                     cfg_stride2,
  input  wire                     in_valid,
  output wire                     in_ready,
  input  wire [LANES*8-1:0]       in_pixel,
  output wire                     out_valid,
  input  wire                     out_ready,
  output wire [LANES*8*9-1:0]     out_window,
  output reg  [5:0]               out_x,
  output reg  [5:0]               out_y,
  output reg                      done,
  output reg                      error,
  output wire                     busy
);
  localparam integer PIX_BITS = LANES*8;
  localparam integer MEM_DEPTH = MAX_WIDTH+2;
  localparam [5:0] MAX_WIDTH_U = MAX_WIDTH[5:0];
  localparam [5:0] MAX_HEIGHT_U = MAX_HEIGHT[5:0];
  localparam [1:0] S_IDLE=0, S_FETCH=1, S_EMIT=2, S_FINISH=3;
  reg [1:0] state_q;
  reg [5:0] width_q, height_q;
  reg pad_q, stride2_q;
  reg [5:0] scan_width_q, scan_height_q;
  reg [5:0] scan_x_q, scan_y_q;
  reg [PIX_BITS-1:0] row_old [0:MEM_DEPTH-1];
  reg [PIX_BITS-1:0] row_new [0:MEM_DEPTH-1];
  reg [PIX_BITS-1:0] old_read_q, new_read_q, pixel_q;
  reg [PIX_BITS-1:0] top1_q, top2_q;
  reg [PIX_BITS-1:0] mid1_q, mid2_q;
  reg [PIX_BITS-1:0] bot1_q, bot2_q;
  reg out_valid_q;
  reg [PIX_BITS*9-1:0] out_window_reg;
  wire [PIX_BITS*9-1:0] window_write_raw={pixel_q,bot2_q,bot1_q,new_read_q,mid2_q,mid1_q,old_read_q,top2_q,top1_q};
  wire [PIX_BITS*9-1:0] window_write_delayed;
  ai_window_hold2 #(.WIDTH(PIX_BITS*9)) timingHoldWindowWrite_pad(.data_in(window_write_raw),.data_out(window_write_delayed));
  ai_window_hold2 #(.WIDTH(PIX_BITS*9)) timingHoldWindowOut_pad(.data_in(out_window_reg),.data_out(out_window));


  wire interior = !pad_q || ((scan_x_q != 0) && (scan_y_q != 0)
                  && (scan_x_q <= width_q) && (scan_y_q <= height_q));
  wire fetch_fire = (state_q == S_FETCH) && (!interior || (in_valid && in_ready));
  wire emit_fire = (state_q == S_EMIT) && (!out_valid_q || out_ready);
  wire last_x = scan_x_q + 1'b1 == scan_width_q;
  wire last_y = scan_y_q + 1'b1 == scan_height_q;
  wire has_next = !(last_x && last_y);
  wire [5:0] next_x = last_x ? 6'd0 : scan_x_q + 1'b1;
  wire [5:0] next_y = last_x ? scan_y_q + 1'b1 : scan_y_q;
  wire next_interior = !pad_q || (!last_x && (scan_x_q < width_q)
                       && (scan_y_q != 0) && (scan_y_q <= height_q));
  // A one-column VALID scan reuses the same RAM address on the next row.
  // Do not issue a same-address read/write in one cycle: FPGA RAM modes differ.
  // Incrementing a six-bit column never aliases itself, even on wrap.
  // Only a row restart at column zero can read/write the same address.
  wire next_ram_safe = !last_x || (scan_x_q != 0);
  wire prefetch_fire = emit_fire && has_next && next_ram_safe
                       && (!next_interior || in_valid);
  wire [5:0] row_read_addr = prefetch_fire ? next_x : scan_x_q;
  wire emit_window = (scan_x_q >= 2) && (scan_y_q >= 2)
      && (!stride2_q || (!scan_x_q[0] && !scan_y_q[0]));

  assign cfg_ready = (state_q == S_IDLE);
  assign in_ready = ((state_q == S_FETCH) && interior)
                 || ((state_q == S_EMIT) && emit_fire && has_next
                     && next_ram_safe && next_interior);
  assign out_valid = out_valid_q;
  assign busy = (state_q != S_IDLE) || out_valid_q;

  // Prime the synchronous row memories once, then prefetch the next column
  // while committing the current column. Padding never consumes input.
  always @(posedge clk) begin
    if (fetch_fire || prefetch_fire) begin
      old_read_q <= row_old[row_read_addr];
      new_read_q <= row_new[row_read_addr];
    end
    if (emit_fire) begin
      row_old[scan_x_q] <= new_read_q;
      row_new[scan_x_q] <= pixel_q;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      width_q <= 0;
      height_q <= 0;
      pad_q <= 0;
      stride2_q <= 0;
      scan_width_q <= 0;
      scan_height_q <= 0;
      scan_x_q <= 0;
      scan_y_q <= 0;
      pixel_q <= 0;
      top1_q <= 0; top2_q <= 0;
      mid1_q <= 0; mid2_q <= 0;
      bot1_q <= 0; bot2_q <= 0;
      out_window_reg <= 0;
      out_x <= 0;
      out_y <= 0;
      out_valid_q <= 0;
      done <= 0;
      error <= 0;
    end else begin
      done <= 0;
      if (out_valid_q && out_ready) out_valid_q <= 0;
      case (state_q)
        S_IDLE: if (cfg_valid) begin
          error <= 0;
          if (cfg_width == 0 || cfg_height == 0
              || cfg_width > MAX_WIDTH_U || cfg_height > MAX_HEIGHT_U) begin
            error <= 1;
            done <= 1;
          end else begin
            width_q <= cfg_width;
            height_q <= cfg_height;
            pad_q <= cfg_pad_same;
            stride2_q <= cfg_stride2;
            scan_width_q <= cfg_width + (cfg_pad_same ? 6'd2 : 6'd0);
            scan_height_q <= cfg_height + (cfg_pad_same ? 6'd2 : 6'd0);
            scan_x_q <= 0;
            scan_y_q <= 0;
            out_valid_q <= 0;
            state_q <= S_FETCH;
          end
        end
        S_FETCH: if (fetch_fire) begin
          pixel_q <= interior ? in_pixel : {PIX_BITS{1'b0}};
          state_q <= S_EMIT;
        end
        S_EMIT: if (emit_fire) begin
          top1_q <= top2_q; top2_q <= old_read_q;
          mid1_q <= mid2_q; mid2_q <= new_read_q;
          bot1_q <= bot2_q; bot2_q <= pixel_q;
          if (emit_window) begin
            out_window_reg[0*PIX_BITS +: PIX_BITS] <= window_write_delayed[0*PIX_BITS +: PIX_BITS];
            out_window_reg[1*PIX_BITS +: PIX_BITS] <= window_write_delayed[1*PIX_BITS +: PIX_BITS];
            out_window_reg[2*PIX_BITS +: PIX_BITS] <= window_write_delayed[2*PIX_BITS +: PIX_BITS];
            out_window_reg[3*PIX_BITS +: PIX_BITS] <= window_write_delayed[3*PIX_BITS +: PIX_BITS];
            out_window_reg[4*PIX_BITS +: PIX_BITS] <= window_write_delayed[4*PIX_BITS +: PIX_BITS];
            out_window_reg[5*PIX_BITS +: PIX_BITS] <= window_write_delayed[5*PIX_BITS +: PIX_BITS];
            out_window_reg[6*PIX_BITS +: PIX_BITS] <= window_write_delayed[6*PIX_BITS +: PIX_BITS];
            out_window_reg[7*PIX_BITS +: PIX_BITS] <= window_write_delayed[7*PIX_BITS +: PIX_BITS];
            out_window_reg[8*PIX_BITS +: PIX_BITS] <= window_write_delayed[8*PIX_BITS +: PIX_BITS];
            out_x <= (scan_x_q - 6'd2) >> stride2_q;
            out_y <= (scan_y_q - 6'd2) >> stride2_q;
            out_valid_q <= 1;
          end
          if (last_x) begin
            scan_x_q <= 0;
            if (last_y) state_q <= S_FINISH;
            else begin
              scan_y_q <= scan_y_q + 1'b1;
              state_q <= prefetch_fire ? S_EMIT : S_FETCH;
            end
          end else begin
            scan_x_q <= scan_x_q + 1'b1;
            state_q <= prefetch_fire ? S_EMIT : S_FETCH;
          end
          if (prefetch_fire) pixel_q <= next_interior ? in_pixel : {PIX_BITS{1'b0}};
        end
        S_FINISH: begin
          if (!out_valid_q || out_ready) begin
            done <= 1;
            state_q <= S_IDLE;
          end
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end
endmodule

// Two kept inversions: identity, no clock-cycle latency. Verify physical STA.
module ai_window_hold2 #(parameter WIDTH=1)(input wire [WIDTH-1:0] data_in,output wire [WIDTH-1:0] data_out);
  (* syn_keep=1 *) wire [WIDTH*3-1:0] chain;
  assign chain[0+:WIDTH]=data_in;
  assign data_out=chain[WIDTH*2+:WIDTH];
  genvar stage,bit_index;
  generate for(stage=0;stage<2;stage=stage+1)begin:delay_stage
    for(bit_index=0;bit_index<WIDTH;bit_index=bit_index+1)begin:delay_bit
      (* syn_keep=1,syn_preserve=1 *) GTP_LUT1 #(.INIT(2'b01)) invert(
        .I0(chain[stage*WIDTH+bit_index]),.Z(chain[(stage+1)*WIDTH+bit_index]));
    end
  end endgenerate
endmodule
