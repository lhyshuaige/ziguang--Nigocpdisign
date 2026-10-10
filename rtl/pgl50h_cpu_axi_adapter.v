`timescale 1ns/1ps

// CPU native memory buses to the internal 256-bit AXI4 contract.
//
// The generated NaxRiscv core exposes 64-bit native beats while the memory
// fabric is deliberately word-wide enough for a 64-byte cache-line refill in
// one AXI burst.  Instruction and data paths have independent AXI master
// ports so the fabric can arbitrate them separately.  Each adapter holds one
// native transaction at a time; the two-entry buffering requirement is kept
// at the fabric ingress where AXI IDs and backpressure are available.
module pgl50h_cpu_axi_adapter #(
  parameter integer ADDR_WIDTH = 32,
  parameter integer DATA_WIDTH = 256,
  parameter integer ID_WIDTH   = 4,
  // The generated native bus may present a DDR-relative address after the
  // reset-vector transaction.  Keep the AXI side in the system physical
  // address domain expected by the HMIC adapter.
  parameter [31:0] CPU_MEM_BASE = 32'h8000_0000
) (
  input  wire                         clk,
  input  wire                         reset,
  input  wire                         init_done,

  input  wire                         if_cmd_valid,
  output wire                         if_cmd_ready,
  input  wire [31:0]                  if_cmd_address,
  output wire                         if_rsp_valid,
  input  wire                         if_rsp_ready,
  output wire [63:0]                  if_rsp_data,
  output wire                         if_rsp_error,

  input  wire                         d_read_cmd_valid,
  output wire                         d_read_cmd_ready,
  input  wire [0:0]                   d_read_cmd_id,
  input  wire [31:0]                  d_read_cmd_address,
  output wire                         d_read_rsp_valid,
  input  wire                         d_read_rsp_ready,
  output wire [0:0]                   d_read_rsp_id,
  output wire [63:0]                  d_read_rsp_data,
  output wire                         d_read_rsp_error,

  input  wire                         d_write_cmd_valid,
  output wire                         d_write_cmd_ready,
  input  wire                         d_write_cmd_last,
  input  wire [31:0]                  d_write_cmd_address,
  input  wire [63:0]                  d_write_cmd_data,
  input  wire [0:0]                   d_write_cmd_id,
  output wire                         d_write_rsp_valid,
  output wire [0:0]                   d_write_rsp_id,
  output wire                         d_write_rsp_error,

  // CPU instruction AXI master.
  output wire [ID_WIDTH-1:0]          if_axi_arid,
  output wire [ADDR_WIDTH-1:0]        if_axi_araddr,
  output wire [3:0]                   if_axi_arlen,
  output wire                         if_axi_arvalid,
  input  wire                         if_axi_arready,
  input  wire [ID_WIDTH-1:0]          if_axi_rid,
  input  wire [DATA_WIDTH-1:0]        if_axi_rdata,
  input  wire [1:0]                   if_axi_rresp,
  input  wire                         if_axi_rlast,
  input  wire                         if_axi_rvalid,
  output wire                         if_axi_rready,

  // CPU data read AXI master.
  output wire [ID_WIDTH-1:0]          d_axi_arid,
  output wire [ADDR_WIDTH-1:0]        d_axi_araddr,
  output wire [3:0]                   d_axi_arlen,
  output wire                         d_axi_arvalid,
  input  wire                         d_axi_arready,
  input  wire [ID_WIDTH-1:0]          d_axi_rid,
  input  wire [DATA_WIDTH-1:0]        d_axi_rdata,
  input  wire [1:0]                   d_axi_rresp,
  input  wire                         d_axi_rlast,
  input  wire                         d_axi_rvalid,
  output wire                         d_axi_rready,

  // CPU data write AXI master.
  output wire [ID_WIDTH-1:0]          d_axi_awid,
  output wire [ADDR_WIDTH-1:0]        d_axi_awaddr,
  output wire [3:0]                   d_axi_awlen,
  output wire                         d_axi_awvalid,
  input  wire                         d_axi_awready,
  output wire [DATA_WIDTH-1:0]        d_axi_wdata,
  output wire [DATA_WIDTH/8-1:0]      d_axi_wstrb,
  output wire                         d_axi_wlast,
  output wire                         d_axi_wvalid,
  input  wire                         d_axi_wready,
  input  wire [ID_WIDTH-1:0]          d_axi_bid,
  input  wire [1:0]                   d_axi_bresp,
  input  wire                         d_axi_bvalid,
  output wire                         d_axi_bready
);

  localparam integer BYTE_LANES = DATA_WIDTH / 8;
  localparam integer WORD_LANES = DATA_WIDTH / 64;
  localparam integer LANE_BITS  = (WORD_LANES <= 1) ? 1 : $clog2(WORD_LANES);

  localparam [2:0] IF_IDLE = 3'd0;
  localparam [2:0] IF_AR   = 3'd1;
  localparam [2:0] IF_RWAIT = 3'd2;
  localparam [2:0] IF_RESP = 3'd3;

  localparam [3:0] D_IDLE  = 4'd0;
  localparam [3:0] D_AR    = 4'd1;
  localparam [3:0] D_RWAIT = 4'd2;
  localparam [3:0] D_RESP  = 4'd3;
  localparam [3:0] D_AWW   = 4'd4;
  localparam [3:0] D_BWAIT = 4'd5;
  localparam [3:0] D_BRESP = 4'd6;
  localparam [3:0] D_COLLECT = 4'd7;

  reg [2:0] if_state;
  reg [31:0] if_line_addr;
  reg        if_beat;
  reg [1:0]  if_word;
  reg [DATA_WIDTH-1:0] if_data_reg;
  reg        if_error_reg;

  reg [3:0] d_state;
  reg [31:0] d_line_addr;
  reg [0:0] d_read_id_reg;
  reg        d_beat;
  reg [1:0]  d_word;
  reg [DATA_WIDTH-1:0] d_data_reg;
  reg        d_error_reg;

  reg [ID_WIDTH-1:0] d_write_id_reg;
  reg [ADDR_WIDTH-1:0] d_write_addr_reg;
  reg [DATA_WIDTH-1:0] d_write_data_reg;
  reg [BYTE_LANES-1:0] d_write_strb_reg;
  reg [31:0] d_write_line_base_reg;
  reg [2:0]  d_write_fragment_index_reg;
  reg        d_write_last_reg;
  reg                  d_aw_sent;
  reg                  d_w_sent;
  reg                  d_write_error_reg;

  function [31:0] normalize_mem_addr;
    input [31:0] address;
    begin
      if (address < CPU_MEM_BASE)
        normalize_mem_addr = CPU_MEM_BASE + address;
      else
        normalize_mem_addr = address;
    end
  endfunction

  wire [31:0] if_mem_address = normalize_mem_addr(if_cmd_address);
  wire [31:0] d_mem_address  = normalize_mem_addr(d_read_cmd_address);
  wire [31:0] w_mem_address  = normalize_mem_addr(d_write_cmd_address);

  wire if_idle_ready = (if_state == IF_IDLE) && init_done;
  wire d_idle_ready  = (d_state == D_IDLE) && init_done;
  wire if_read_fire  = if_cmd_valid && if_cmd_ready;
  wire d_read_fire   = d_read_cmd_valid && d_read_cmd_ready;
  wire d_write_fire  = d_write_cmd_valid && d_write_cmd_ready;

  // IF has no competing native command.  D-read is selected over D-write if
  // both are asserted in one cycle; the losing request remains valid.
  assign if_cmd_ready      = if_idle_ready;
  assign d_read_cmd_ready  = d_idle_ready;
  // A native cache writeback is a stream of 64-bit fragments.  The generated
  // core keeps the cache-line base address on every fragment and asserts
  // `last` only on the final fragment, so accept the stream while each
  // fragment is serialized as one 256-bit AXI beat.
  assign d_write_cmd_ready = ((d_state == D_IDLE) || (d_state == D_COLLECT)) &&
                             init_done && !d_read_cmd_valid;

  assign if_rsp_valid = (if_state == IF_RESP);
  assign if_rsp_data  = if_data_reg[if_word*64 +: 64];
  assign if_rsp_error = if_error_reg;

  assign d_read_rsp_valid = (d_state == D_RESP);
  assign d_read_rsp_id    = d_read_id_reg;
  assign d_read_rsp_data  = d_data_reg[d_word*64 +: 64];
  assign d_read_rsp_error = d_error_reg;

  assign d_write_rsp_valid = (d_state == D_BRESP);
  assign d_write_rsp_id    = d_write_id_reg[0:0];
  assign d_write_rsp_error = d_write_error_reg;

  assign if_axi_arid    = {ID_WIDTH{1'b0}};
  assign if_axi_araddr  = if_line_addr;
  assign if_axi_arlen   = 4'd1; // two 256-bit beats = one 64-byte line
  assign if_axi_arvalid = (if_state == IF_AR);
  assign if_axi_rready  = (if_state == IF_RWAIT);

  assign d_axi_arid    = {{(ID_WIDTH-1){1'b0}}, d_read_id_reg};
  assign d_axi_araddr  = d_line_addr;
  assign d_axi_arlen   = 4'd1;
  assign d_axi_arvalid = (d_state == D_AR);
  assign d_axi_rready  = (d_state == D_RWAIT);

  assign d_axi_awid    = d_write_id_reg;
  assign d_axi_awaddr  = d_write_addr_reg;
  assign d_axi_awlen   = 4'd0;
  assign d_axi_awvalid = (d_state == D_AWW) && !d_aw_sent;
  assign d_axi_wdata   = d_write_data_reg;
  assign d_axi_wstrb   = d_write_strb_reg;
  assign d_axi_wlast   = 1'b1;
  assign d_axi_wvalid  = (d_state == D_AWW) && !d_w_sent;
  assign d_axi_bready  = (d_state == D_BWAIT);

  function [BYTE_LANES-1:0] make_strobe;
    input [LANE_BITS-1:0] lane;
    reg [BYTE_LANES-1:0] value;
    begin
      value = {BYTE_LANES{1'b0}};
      value[lane*8 +: 8] = 8'hff;
      make_strobe = value;
    end
  endfunction

  function [DATA_WIDTH-1:0] place_word;
    input [63:0] data;
    input [LANE_BITS-1:0] lane;
    reg [DATA_WIDTH-1:0] value;
    begin
      value = {DATA_WIDTH{1'b0}};
      value[lane*64 +: 64] = data;
      place_word = value;
    end
  endfunction

  always @(posedge clk) begin
    if (reset) begin
      if_state          <= IF_IDLE;
      if_line_addr      <= 32'h0;
      if_beat            <= 1'b0;
      if_word            <= 2'd0;
      if_data_reg       <= {DATA_WIDTH{1'b0}};
      if_error_reg      <= 1'b0;
    end else begin
      case (if_state)
        IF_IDLE: begin
          if (if_read_fire) begin
            if_line_addr <= {if_mem_address[31:6], 6'b0};
            if_beat      <= 1'b0;
            if_word      <= 2'd0;
            if_error_reg <= 1'b0;
            if_state     <= IF_AR;
          end
        end
        IF_AR: begin
          if (if_axi_arvalid && if_axi_arready)
            if_state <= IF_RWAIT;
        end
        IF_RWAIT: begin
          if (if_axi_rvalid && if_axi_rready) begin
            if_data_reg  <= if_axi_rdata;
            if_error_reg <= (if_axi_rresp != 2'b00) ||
                            (if_axi_rid != {ID_WIDTH{1'b0}}) ||
                            ((if_beat == 1'b1) && !if_axi_rlast);
            if_word      <= 2'd0;
            if_state     <= IF_RESP;
          end
        end
        IF_RESP: begin
          if (if_rsp_valid && if_rsp_ready) begin
            if (if_word == 2'd3) begin
              if (if_beat) begin
                if_state <= IF_IDLE;
              end else begin
                if_beat  <= 1'b1;
                if_state <= IF_RWAIT;
              end
            end else begin
              if_word <= if_word + 2'd1;
            end
          end
        end
        default: if_state <= IF_IDLE;
      endcase
    end
  end

  always @(posedge clk) begin
    if (reset) begin
      d_state           <= D_IDLE;
      d_line_addr       <= 32'h0;
      d_read_id_reg     <= 1'b0;
      d_beat             <= 1'b0;
      d_word             <= 2'd0;
      d_data_reg        <= {DATA_WIDTH{1'b0}};
      d_error_reg       <= 1'b0;
      d_write_id_reg    <= {ID_WIDTH{1'b0}};
      d_write_addr_reg  <= {ADDR_WIDTH{1'b0}};
      d_write_data_reg  <= {DATA_WIDTH{1'b0}};
      d_write_strb_reg  <= {BYTE_LANES{1'b0}};
      d_write_line_base_reg <= 32'h0;
      d_write_fragment_index_reg <= 3'd0;
      d_write_last_reg  <= 1'b0;
      d_aw_sent         <= 1'b0;
      d_w_sent          <= 1'b0;
      d_write_error_reg <= 1'b0;
    end else begin
      case (d_state)
        D_IDLE: begin
          if (d_read_fire) begin
            d_line_addr   <= {d_mem_address[31:6], 6'b0};
            d_read_id_reg <= d_read_cmd_id;
            d_beat        <= 1'b0;
            d_word        <= 2'd0;
            d_error_reg   <= 1'b0;
            d_state       <= D_AR;
          end else if (d_write_fire) begin
            d_write_id_reg    <= {{(ID_WIDTH-1){1'b0}}, d_write_cmd_id};
            d_write_last_reg  <= d_write_cmd_last;
            // A one-fragment native write retains its byte lane in the
            // address.  A cache-line writeback uses the line base and streams
            // fragments in order, handled by D_COLLECT below.
            if (d_write_cmd_last) begin
              d_write_addr_reg  <= {w_mem_address[31:5], 5'b0};
              d_write_data_reg  <= place_word(d_write_cmd_data, w_mem_address[4:3]);
              d_write_strb_reg  <= make_strobe(w_mem_address[4:3]);
              d_write_line_base_reg <= {w_mem_address[31:5], 5'b0};
              d_write_fragment_index_reg <= 3'd0;
            end else begin
              d_write_addr_reg  <= {w_mem_address[31:6], 6'b0};
              d_write_data_reg  <= place_word(d_write_cmd_data, 2'd0);
              d_write_strb_reg  <= make_strobe(2'd0);
              d_write_line_base_reg <= {w_mem_address[31:6], 6'b0};
              d_write_fragment_index_reg <= 3'd0;
            end
            d_aw_sent         <= 1'b0;
            d_w_sent          <= 1'b0;
            d_write_error_reg <= 1'b0;
            d_state           <= D_AWW;
          end
        end
        D_COLLECT: begin
          if (d_write_fire) begin
            d_write_id_reg    <= {{(ID_WIDTH-1){1'b0}}, d_write_cmd_id};
            d_write_last_reg  <= d_write_cmd_last;
            d_write_addr_reg  <= d_write_line_base_reg +
                                 ((d_write_fragment_index_reg >= 3'd4) ? 32'd32 : 32'd0);
            d_write_data_reg  <= place_word(d_write_cmd_data,
                                            d_write_fragment_index_reg[1:0]);
            d_write_strb_reg  <= make_strobe(d_write_fragment_index_reg[1:0]);
            d_aw_sent         <= 1'b0;
            d_w_sent          <= 1'b0;
            d_state           <= D_AWW;
          end
        end
        D_AR: begin
          if (d_axi_arvalid && d_axi_arready)
            d_state <= D_RWAIT;
        end
        D_RWAIT: begin
          if (d_axi_rvalid && d_axi_rready) begin
            d_data_reg  <= d_axi_rdata;
            d_error_reg <= (d_axi_rresp != 2'b00) ||
                           (d_axi_rid != {{(ID_WIDTH-1){1'b0}}, d_read_id_reg}) ||
                           ((d_beat == 1'b1) && !d_axi_rlast);
            d_word      <= 2'd0;
            d_state     <= D_RESP;
          end
        end
        D_RESP: begin
          if (d_read_rsp_valid && d_read_rsp_ready) begin
            if (d_word == 2'd3) begin
              if (d_beat) begin
                d_state <= D_IDLE;
              end else begin
                d_beat  <= 1'b1;
                d_state <= D_RWAIT;
              end
            end else begin
              d_word <= d_word + 2'd1;
            end
          end
        end
        D_AWW: begin
          if (d_axi_awvalid && d_axi_awready)
            d_aw_sent <= 1'b1;
          if (d_axi_wvalid && d_axi_wready)
            d_w_sent <= 1'b1;
          if ((d_aw_sent || (d_axi_awvalid && d_axi_awready)) &&
              (d_w_sent || (d_axi_wvalid && d_axi_wready)))
            d_state <= D_BWAIT;
        end
        D_BWAIT: begin
          if (d_axi_bvalid && d_axi_bready) begin
            d_write_error_reg <= d_write_error_reg ||
                                 (d_axi_bresp != 2'b00) ||
                                 (d_axi_bid != d_write_id_reg);
            if (d_write_last_reg) begin
              d_state <= D_BRESP;
            end else begin
              d_write_fragment_index_reg <= d_write_fragment_index_reg + 3'd1;
              d_state <= D_COLLECT;
            end
          end
        end
        D_BRESP: begin
          d_state <= D_IDLE;
        end
        default: d_state <= D_IDLE;
      endcase
    end
  end

  // Keep the generated native write metadata visible to synthesis/lint.
  wire unused_native_metadata = d_write_cmd_last ^ if_axi_rlast ^ d_axi_rlast;

endmodule
