`timescale 1ns/1ps

// CPU native-bus to the PGL50H HMIC AXI user port.
//
// The generated NaxRiscvContest exposes 64-bit native memory beats.  The
// PGL50H x32 HMIC user port exposes 256-bit data and a 28-bit, 8-byte aligned
// address.  A 64-byte cache-line refill is therefore translated to two HMIC
// reads, with each returned beat streamed as four 64-bit CPU responses.
// Writes are emitted as one HMIC beat per native 64-bit write fragment; the
// selected 8-byte lane and byte strobe are preserved.

module pgl50h_native_axi_bridge #(
  parameter integer AXI_ADDR_WIDTH = 28,
  parameter integer AXI_DATA_WIDTH = 256,
  parameter [31:0] CPU_MEM_BASE = 32'h8000_0000,
  parameter integer HMIC_ADDR_SHIFT = 3
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

  // PGL50H HMIC user port (the generated IP has no WVALID/RREADY signals).
  output wire [AXI_ADDR_WIDTH-1:0]    axi_awaddr,
  output wire                         axi_awuser_ap,
  output wire [3:0]                   axi_awuser_id,
  output wire [3:0]                   axi_awlen,
  input  wire                         axi_awready,
  output wire                         axi_awvalid,
  output wire [AXI_DATA_WIDTH-1:0]    axi_wdata,
  output wire [AXI_DATA_WIDTH/8-1:0]  axi_wstrb,
  input  wire                         axi_wready,
  input  wire [3:0]                   axi_wusero_id,
  input  wire                         axi_wusero_last,
  output wire [AXI_ADDR_WIDTH-1:0]    axi_araddr,
  output wire                         axi_aruser_ap,
  output wire [3:0]                   axi_aruser_id,
  output wire [3:0]                   axi_arlen,
  input  wire                         axi_arready,
  output wire                         axi_arvalid,
  input  wire [AXI_DATA_WIDTH-1:0]    axi_rdata,
  input  wire [3:0]                   axi_rid,
  input  wire                         axi_rlast,
  input  wire                         axi_rvalid
);

  localparam integer BYTE_LANES = AXI_DATA_WIDTH / 8;
  localparam integer WORD_LANES = AXI_DATA_WIDTH / 64;
  localparam integer LANE_BITS  = (WORD_LANES <= 1) ? 1 : $clog2(WORD_LANES);
  localparam [LANE_BITS-1:0] LAST_WORD = {LANE_BITS{1'b1}};
  // Use an implicit-width parameter assignment here.  The explicit
  // SystemVerilog sized cast is accepted by Verilator but rejected by the
  // ModelSim/PDS front-end shipped with the target flow.
  localparam [AXI_ADDR_WIDTH-1:0] WORD_LANES_ADDR = WORD_LANES;

  localparam [3:0] ST_IDLE     = 4'd0;
  localparam [3:0] ST_RD_AR    = 4'd1;
  localparam [3:0] ST_RD_WAIT  = 4'd2;
  localparam [3:0] ST_RD_RESP  = 4'd3;
  localparam [3:0] ST_WR       = 4'd4;
  localparam [3:0] ST_WR_RESP  = 4'd5;

  reg [3:0] state;
  reg       read_is_if;
  reg [31:0] read_line_addr;
  reg [0:0] read_id;
  reg [1:0] read_beat;
  reg [LANE_BITS-1:0] read_word;
  reg [AXI_DATA_WIDTH-1:0] read_data_reg;
  reg       read_error_reg;

  reg [AXI_ADDR_WIDTH-1:0] write_addr_reg;
  reg [3:0] write_id_reg;
  reg [AXI_DATA_WIDTH-1:0] write_data_reg;
  reg [BYTE_LANES-1:0] write_strb_reg;

  wire idle_ready = (state == ST_IDLE) && init_done;

  // Arbitration is intentionally explicit: instruction refills have highest
  // priority, followed by D-cache refills, then writeback fragments.  The
  // generated CPU sees a command as accepted only on its corresponding ready
  // channel, so no request can be lost when two native buses assert together.
  assign if_cmd_ready    = idle_ready;
  assign d_read_cmd_ready = idle_ready && !if_cmd_valid;
  assign d_write_cmd_ready = idle_ready && !if_cmd_valid && !d_read_cmd_valid;

  assign if_rsp_valid = (state == ST_RD_RESP) && read_is_if;
  assign if_rsp_data  = read_data_reg[read_word*64 +: 64];
  assign if_rsp_error = read_error_reg;

  assign d_read_rsp_valid = (state == ST_RD_RESP) && !read_is_if;
  assign d_read_rsp_id    = read_id;
  assign d_read_rsp_data  = read_data_reg[read_word*64 +: 64];
  assign d_read_rsp_error = read_error_reg;

  assign d_write_rsp_valid = (state == ST_WR_RESP);
  assign d_write_rsp_id    = write_id_reg[0:0];
  assign d_write_rsp_error = 1'b0;

  assign axi_awaddr    = write_addr_reg;
  assign axi_awuser_ap = 1'b0;
  assign axi_awuser_id = write_id_reg;
  assign axi_awlen     = 4'd0;
  assign axi_awvalid   = (state == ST_WR);
  assign axi_wdata     = write_data_reg;
  assign axi_wstrb     = write_strb_reg;
  wire [AXI_ADDR_WIDTH-1:0] read_hmic_addr;
  assign read_hmic_addr = cpu_to_hmic(read_line_addr) + (read_beat * WORD_LANES_ADDR);
  assign axi_araddr    = read_hmic_addr;
  assign axi_aruser_ap = 1'b0;
  assign axi_aruser_id = read_is_if ? 4'd0 : {3'd0, read_id};
  assign axi_arlen     = 4'd0;
  assign axi_arvalid   = (state == ST_RD_AR);

  function [AXI_ADDR_WIDTH-1:0] cpu_to_hmic;
    input [31:0] address;
    reg [31:0] offset;
    begin
      offset = address - CPU_MEM_BASE;
      cpu_to_hmic = offset[HMIC_ADDR_SHIFT+AXI_ADDR_WIDTH-1:HMIC_ADDR_SHIFT];
    end
  endfunction

  function [AXI_DATA_WIDTH-1:0] place_word;
    input [63:0] data;
    input [LANE_BITS-1:0] lane;
    reg [AXI_DATA_WIDTH-1:0] value;
    begin
      value = {AXI_DATA_WIDTH{1'b0}};
      value[lane*64 +: 64] = data;
      place_word = value;
    end
  endfunction

  function [BYTE_LANES-1:0] place_strobe;
    input [LANE_BITS-1:0] lane;
    reg [BYTE_LANES-1:0] value;
    begin
      value = {BYTE_LANES{1'b0}};
      value[lane*8 +: 8] = 8'hff;
      place_strobe = value;
    end
  endfunction

  wire read_response_fire = read_is_if ? (if_rsp_valid && if_rsp_ready)
                                       : (d_read_rsp_valid && d_read_rsp_ready);

  always @(posedge clk) begin
    if (reset) begin
      state          <= ST_IDLE;
      read_is_if     <= 1'b0;
      read_line_addr <= 32'h0;
      read_id        <= 1'b0;
      read_beat      <= 2'd0;
      read_word      <= {LANE_BITS{1'b0}};
      read_data_reg  <= {AXI_DATA_WIDTH{1'b0}};
      read_error_reg <= 1'b0;
      write_addr_reg <= {AXI_ADDR_WIDTH{1'b0}};
      write_id_reg   <= 4'h0;
      write_data_reg <= {AXI_DATA_WIDTH{1'b0}};
      write_strb_reg <= {BYTE_LANES{1'b0}};
    end else begin
      case (state)
        ST_IDLE: begin
          if (init_done && if_cmd_valid) begin
            read_is_if     <= 1'b1;
            read_line_addr <= {if_cmd_address[31:6], 6'b0};
            read_id        <= 1'b0;
            read_beat      <= 2'd0;
            read_word      <= {LANE_BITS{1'b0}};
            read_error_reg <= 1'b0;
            state          <= ST_RD_AR;
          end else if (init_done && d_read_cmd_valid) begin
            read_is_if     <= 1'b0;
            read_line_addr <= {d_read_cmd_address[31:6], 6'b0};
            read_id        <= d_read_cmd_id;
            read_beat      <= 2'd0;
            read_word      <= {LANE_BITS{1'b0}};
            read_error_reg <= 1'b0;
            state          <= ST_RD_AR;
          end else if (init_done && d_write_cmd_valid) begin
            // The HMIC command addresses a 32-byte x32 beat.  The native
            // 64-bit fragment selects one of its four 8-byte lanes.
            write_addr_reg <= cpu_to_hmic(d_write_cmd_address & 32'hffffffe0);
            write_id_reg   <= {3'd0, d_write_cmd_id};
            write_data_reg <= place_word(d_write_cmd_data, d_write_cmd_address[LANE_BITS+2:3]);
            write_strb_reg <= place_strobe(d_write_cmd_address[LANE_BITS+2:3]);
            state          <= ST_WR;
          end
        end

        ST_RD_AR: begin
          if (axi_arvalid && axi_arready)
            state <= ST_RD_WAIT;
        end

        ST_RD_WAIT: begin
          // HMIC has no RREADY; axi_rvalid is the completion indication.
          if (axi_rvalid) begin
            read_data_reg  <= axi_rdata;
            read_error_reg <= 1'b0;
            read_word      <= {LANE_BITS{1'b0}};
            state          <= ST_RD_RESP;
          end
        end

        ST_RD_RESP: begin
          if (read_response_fire) begin
            if ((read_word == LAST_WORD) && (read_beat == 2'd1)) begin
              state <= ST_IDLE;
            end else if (read_word == LAST_WORD) begin
              read_beat <= read_beat + 2'd1;
              read_word <= {LANE_BITS{1'b0}};
              state <= ST_RD_AR;
            end else begin
              read_word <= read_word + 1'b1;
            end
          end
        end

        ST_WR: begin
          if (axi_awvalid && axi_awready && axi_wready)
            state <= ST_WR_RESP;
        end

        ST_WR_RESP: begin
          state <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

  // These HMIC outputs are protocol metadata returned by the controller.  A
  // fixed single-beat bridge does not need to consume them, but keeping them
  // referenced makes the intended ID/last contract explicit to synthesis and
  // lint tools.
  wire unused_hmic_metadata = axi_wusero_id[0] ^ axi_wusero_last ^ axi_rid[0] ^ axi_rlast ^ d_write_cmd_last;

endmodule
