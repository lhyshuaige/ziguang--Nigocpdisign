`timescale 1ns/1ps

// Internal AXI4 slave to PGL50H HMIC user-port adapter.
//
// The HMIC port represents one 256-bit command at a time and has no WVALID,
// B, or RREADY signals.  This wrapper therefore splits AXI bursts into
// single-beat HMIC commands, registers every command/data field, and holds
// AXI responses until the downstream fabric accepts them.
module pgl50h_axi4_hmic_adapter #(
  parameter integer AXI_ADDR_WIDTH  = 32,
  parameter integer HMIC_ADDR_WIDTH = 28,
  parameter integer AXI_DATA_WIDTH  = 256,
  parameter integer ID_WIDTH        = 4,
  parameter [31:0]  CPU_MEM_BASE    = 32'h8000_0000,
  parameter integer HMIC_ADDR_SHIFT = 3
) (
  input  wire                         clk,
  input  wire                         reset,
  input  wire                         init_done,

  // Internal AXI4 slave side.
  input  wire [ID_WIDTH-1:0]          s_axi_awid,
  input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
  input  wire [3:0]                   s_axi_awlen,
  input  wire                         s_axi_awvalid,
  output wire                         s_axi_awready,
  input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
  input  wire [AXI_DATA_WIDTH/8-1:0]  s_axi_wstrb,
  input  wire                         s_axi_wlast,
  input  wire                         s_axi_wvalid,
  output wire                         s_axi_wready,
  output wire [ID_WIDTH-1:0]          s_axi_bid,
  output wire [1:0]                   s_axi_bresp,
  output wire                         s_axi_bvalid,
  input  wire                         s_axi_bready,

  input  wire [ID_WIDTH-1:0]          s_axi_arid,
  input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
  input  wire [3:0]                   s_axi_arlen,
  input  wire                         s_axi_arvalid,
  output wire                         s_axi_arready,
  output wire [ID_WIDTH-1:0]          s_axi_rid,
  output wire [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
  output wire [1:0]                   s_axi_rresp,
  output wire                         s_axi_rlast,
  output wire                         s_axi_rvalid,
  input  wire                         s_axi_rready,

  // PGL50H HMIC user port.  WVALID/RREADY are absent by IP contract.
  output wire [HMIC_ADDR_WIDTH-1:0]   axi_awaddr,
  output wire                         axi_awuser_ap,
  output wire [ID_WIDTH-1:0]          axi_awuser_id,
  output wire [3:0]                   axi_awlen,
  input  wire                         axi_awready,
  output wire                         axi_awvalid,
  output wire [AXI_DATA_WIDTH-1:0]    axi_wdata,
  output wire [AXI_DATA_WIDTH/8-1:0]  axi_wstrb,
  input  wire                         axi_wready,
  input  wire [ID_WIDTH-1:0]          axi_wusero_id,
  input  wire                         axi_wusero_last,
  output wire [HMIC_ADDR_WIDTH-1:0]   axi_araddr,
  output wire                         axi_aruser_ap,
  output wire [ID_WIDTH-1:0]          axi_aruser_id,
  output wire [3:0]                   axi_arlen,
  input  wire                         axi_arready,
  output wire                         axi_arvalid,
  input  wire [AXI_DATA_WIDTH-1:0]    axi_rdata,
  input  wire [ID_WIDTH-1:0]          axi_rid,
  input  wire                         axi_rlast,
  input  wire                         axi_rvalid
);

  localparam [3:0] ST_IDLE    = 4'd0;
  localparam [3:0] ST_RD_CMD  = 4'd1;
  localparam [3:0] ST_RD_WAIT = 4'd2;
  localparam [3:0] ST_RD_RESP = 4'd3;
  localparam [3:0] ST_WR_DATA = 4'd4;
  localparam [3:0] ST_WR_HMIC = 4'd5;
  localparam [3:0] ST_WR_RESP = 4'd6;

  reg [3:0] state;

  reg [ID_WIDTH-1:0]       rd_id_reg;
  reg [AXI_ADDR_WIDTH-1:0] rd_addr_reg;
  reg [3:0]                rd_len_reg;
  reg [3:0]                rd_count_reg;
  reg [AXI_DATA_WIDTH-1:0] rd_data_reg;
  reg                      rd_error_reg;
  reg                      rd_abort_reg;

  reg [ID_WIDTH-1:0]       wr_id_reg;
  reg [AXI_ADDR_WIDTH-1:0] wr_addr_reg;
  reg [3:0]                wr_len_reg;
  reg [3:0]                wr_count_reg;
  reg [AXI_DATA_WIDTH-1:0] wr_data_reg;
  reg [AXI_DATA_WIDTH/8-1:0] wr_strb_reg;
  reg                      wr_last_reg;
  reg                      wr_error_reg;
  reg                      wr_abort_reg;
  reg                      wr_hmic_aw_sent;

  wire hmic_aw_fire = axi_awvalid && axi_awready;
  // UG042003 p36-37: AW and W are independent. WREADY is the data
  // transfer indication (there is no WVALID), with ID/LAST in that cycle.
  wire hmic_w_fire = (state == ST_WR_HMIC) && axi_wready &&
                     (wr_hmic_aw_sent || hmic_aw_fire);

  // The HMIC user port addresses one 256-bit beat at a time.  Reject an
  // address below the CPU DDR window, a non-32-byte-aligned beat, an address
  // that wraps the AXI address space, or a burst that extends past the
  // representable HMIC byte range.  Invalid reads still return every AXI
  // beat with DECERR; invalid writes consume the complete W burst before
  // returning B/DECERR, so neither case can deadlock an AXI master.
  localparam integer HMIC_BYTE_ADDR_WIDTH = HMIC_ADDR_WIDTH + HMIC_ADDR_SHIFT;
  localparam [AXI_ADDR_WIDTH:0] HMIC_BYTE_LIMIT =
    ({{AXI_ADDR_WIDTH{1'b0}}, 1'b1} << HMIC_BYTE_ADDR_WIDTH);
  wire [AXI_ADDR_WIDTH:0] rd_burst_bytes =
    ({{(AXI_ADDR_WIDTH-3){1'b0}}, s_axi_arlen} +
     {{AXI_ADDR_WIDTH{1'b0}}, 1'b1}) * 33'd32;
  wire [AXI_ADDR_WIDTH:0] wr_burst_bytes =
    ({{(AXI_ADDR_WIDTH-3){1'b0}}, s_axi_awlen} +
     {{AXI_ADDR_WIDTH{1'b0}}, 1'b1}) * 33'd32;
  wire [AXI_ADDR_WIDTH:0] rd_end_addr_ext =
    {1'b0, s_axi_araddr} + rd_burst_bytes - 33'd1;
  wire [AXI_ADDR_WIDTH:0] wr_end_addr_ext =
    {1'b0, s_axi_awaddr} + wr_burst_bytes - 33'd1;
  wire [AXI_ADDR_WIDTH:0] rd_end_offset_ext =
    rd_end_addr_ext - {1'b0, CPU_MEM_BASE};
  wire [AXI_ADDR_WIDTH:0] wr_end_offset_ext =
    wr_end_addr_ext - {1'b0, CPU_MEM_BASE};
  wire rd_addr_error = (s_axi_araddr < CPU_MEM_BASE) ||
                       (s_axi_araddr[4:0] != 5'd0) ||
                       rd_end_addr_ext[AXI_ADDR_WIDTH] ||
                       (rd_end_offset_ext >= HMIC_BYTE_LIMIT);
  wire wr_addr_error = (s_axi_awaddr < CPU_MEM_BASE) ||
                       (s_axi_awaddr[4:0] != 5'd0) ||
                       wr_end_addr_ext[AXI_ADDR_WIDTH] ||
                       (wr_end_offset_ext >= HMIC_BYTE_LIMIT);

  function [HMIC_ADDR_WIDTH-1:0] to_hmic_addr;
    input [AXI_ADDR_WIDTH-1:0] address;
    reg [AXI_ADDR_WIDTH-1:0] offset;
    begin
      offset = address - CPU_MEM_BASE;
      to_hmic_addr = offset[HMIC_ADDR_SHIFT+HMIC_ADDR_WIDTH-1:HMIC_ADDR_SHIFT];
    end
  endfunction

  wire idle_ready = (state == ST_IDLE) && init_done;
  wire read_accept = s_axi_arvalid && s_axi_arready;
  wire write_accept = s_axi_awvalid && s_axi_awready;

  // Read has arbitration priority over write when both address channels are
  // asserted.  AW and W are intentionally separated after the AW handshake.
  assign s_axi_arready = idle_ready;
  assign s_axi_awready = idle_ready && !s_axi_arvalid;
  assign s_axi_wready  = (state == ST_WR_DATA);

  assign s_axi_rid    = rd_id_reg;
  assign s_axi_rdata  = rd_abort_reg ? {AXI_DATA_WIDTH{1'b0}} : rd_data_reg;
  assign s_axi_rresp  = (rd_error_reg || rd_abort_reg) ? 2'b10 : 2'b00;
  assign s_axi_rlast  = (rd_count_reg == rd_len_reg);
  assign s_axi_rvalid = (state == ST_RD_RESP);

  assign s_axi_bid    = wr_id_reg;
  assign s_axi_bresp  = (wr_error_reg || wr_abort_reg) ? 2'b10 : 2'b00;
  assign s_axi_bvalid = (state == ST_WR_RESP);

  assign axi_awaddr    = to_hmic_addr(wr_addr_reg);
  assign axi_awuser_ap = 1'b0;
  assign axi_awuser_id = wr_id_reg;
  assign axi_awlen     = 4'd0;
  assign axi_awvalid   = (state == ST_WR_HMIC) && !wr_hmic_aw_sent;
  assign axi_wdata     = wr_data_reg;
  assign axi_wstrb     = (state == ST_WR_HMIC) ? wr_strb_reg :
                        {(AXI_DATA_WIDTH/8){1'b0}};

  assign axi_araddr    = to_hmic_addr(rd_addr_reg + (rd_count_reg * 32));
  assign axi_aruser_ap = 1'b0;
  assign axi_aruser_id = rd_id_reg;
  assign axi_arlen     = 4'd0;
  assign axi_arvalid   = (state == ST_RD_CMD);

  always @(posedge clk) begin
    if (reset) begin
      state         <= ST_IDLE;
      rd_id_reg     <= {ID_WIDTH{1'b0}};
      rd_addr_reg   <= {AXI_ADDR_WIDTH{1'b0}};
      rd_len_reg    <= 4'd0;
      rd_count_reg  <= 4'd0;
      rd_data_reg   <= {AXI_DATA_WIDTH{1'b0}};
      rd_error_reg  <= 1'b0;
      rd_abort_reg  <= 1'b0;
      wr_id_reg     <= {ID_WIDTH{1'b0}};
      wr_addr_reg   <= {AXI_ADDR_WIDTH{1'b0}};
      wr_len_reg    <= 4'd0;
      wr_count_reg  <= 4'd0;
      wr_data_reg   <= {AXI_DATA_WIDTH{1'b0}};
      wr_strb_reg   <= {(AXI_DATA_WIDTH/8){1'b0}};
      wr_last_reg   <= 1'b0;
      wr_error_reg  <= 1'b0;
      wr_abort_reg  <= 1'b0;
      wr_hmic_aw_sent <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: begin
          if (read_accept) begin
            rd_id_reg    <= s_axi_arid;
            rd_addr_reg  <= s_axi_araddr;
            rd_len_reg   <= s_axi_arlen;
            rd_count_reg <= 4'd0;
            rd_error_reg <= rd_addr_error;
            rd_abort_reg <= rd_addr_error;
            rd_data_reg  <= {AXI_DATA_WIDTH{1'b0}};
            state        <= rd_addr_error ? ST_RD_RESP : ST_RD_CMD;
          end else if (write_accept) begin
            wr_id_reg     <= s_axi_awid;
            wr_addr_reg   <= s_axi_awaddr;
            wr_len_reg    <= s_axi_awlen;
            wr_count_reg  <= 4'd0;
            wr_error_reg  <= wr_addr_error;
            wr_abort_reg  <= wr_addr_error;
            state         <= ST_WR_DATA;
          end
        end

        ST_RD_CMD: begin
          if (axi_arvalid && axi_arready)
            state <= ST_RD_WAIT;
        end

        ST_RD_WAIT: begin
          // HMIC has no RREADY; the registered AXI response holds the beat.
          if (axi_rvalid) begin
            rd_data_reg  <= axi_rdata;
            rd_error_reg <= (axi_rid != rd_id_reg) || !axi_rlast;
            state        <= ST_RD_RESP;
          end
        end

        ST_RD_RESP: begin
          if (s_axi_rvalid && s_axi_rready) begin
            if (rd_count_reg == rd_len_reg) begin
              state <= ST_IDLE;
            end else begin
              rd_count_reg <= rd_count_reg + 4'd1;
              rd_error_reg <= rd_abort_reg;
              state        <= rd_abort_reg ? ST_RD_RESP : ST_RD_CMD;
            end
          end
        end

        ST_WR_DATA: begin
          if (s_axi_wvalid && s_axi_wready) begin
            wr_hmic_aw_sent <= 1'b0;
            wr_data_reg <= s_axi_wdata;
            wr_strb_reg <= s_axi_wstrb;
            wr_last_reg <= s_axi_wlast || (wr_count_reg == wr_len_reg);
            if (s_axi_wlast != (wr_count_reg == wr_len_reg))
              wr_error_reg <= 1'b1;
            if (wr_abort_reg) begin
              if (s_axi_wlast || (wr_count_reg == wr_len_reg)) begin
                state <= ST_WR_RESP;
              end else begin
                wr_count_reg <= wr_count_reg + 4'd1;
                state <= ST_WR_DATA;
              end
            end else begin
              state <= ST_WR_HMIC;
            end
          end
        end

        ST_WR_HMIC: begin
          // Retire AW exactly once, even if the controller requests W later.
          // The buffered data/strobes remain stable until WREADY; AWREADY
          // need not still be high when that transfer happens.
          if (hmic_aw_fire)
            wr_hmic_aw_sent <= 1'b1;
          if (hmic_w_fire) begin
            wr_hmic_aw_sent <= 1'b0;
            if ((axi_wusero_id != wr_id_reg) || !axi_wusero_last)
              wr_error_reg <= 1'b1;
            if (wr_last_reg) begin
              state <= ST_WR_RESP;
            end else begin
              wr_count_reg <= wr_count_reg + 4'd1;
              wr_addr_reg  <= wr_addr_reg + 32;
              state        <= ST_WR_DATA;
            end
          end
        end

        ST_WR_RESP: begin
          if (s_axi_bvalid && s_axi_bready)
            state <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
