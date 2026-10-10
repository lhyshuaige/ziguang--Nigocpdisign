`timescale 1ns/1ps

// Single-outstanding HMIC user-port clock crossing.
//
// The CPU/AXI/AI/DMA fabric is clocked by pll_clk_sys.  The PDS HMIC user
// port is clocked by ddrphy_clkin.  HMIC has one command at a time and does
// not expose independent WVALID/RREADY channels, so a toggle mailbox is a
// better fit than a full AXI clock converter here.  The payload buses remain
// stable from the source handshake until the destination observes the toggle;
// only the toggles cross through two-flop synchronizers.
module pgl50h_axi_hmic_cdc #(
  parameter integer ADDR_WIDTH = 28,
  parameter integer DATA_WIDTH = 256,
  parameter integer ID_WIDTH   = 4
) (
  input  wire                     src_clk,
  input  wire                     src_reset,
  input  wire                     dst_clk,
  input  wire                     dst_reset,

  // pll_clk_sys side (adapter side)
  input  wire [ADDR_WIDTH-1:0]    s_awaddr,
  input  wire                     s_awuser_ap,
  input  wire [ID_WIDTH-1:0]      s_awuser_id,
  input  wire [3:0]               s_awlen,
  input  wire                     s_awvalid,
  output wire                     s_awready,
  input  wire [DATA_WIDTH-1:0]    s_wdata,
  input  wire [DATA_WIDTH/8-1:0]  s_wstrb,
  output wire                     s_wready,
  output wire [ID_WIDTH-1:0]      s_wusero_id,
  output wire                     s_wusero_last,
  input  wire [ADDR_WIDTH-1:0]    s_araddr,
  input  wire                     s_aruser_ap,
  input  wire [ID_WIDTH-1:0]      s_aruser_id,
  input  wire [3:0]               s_arlen,
  input  wire                     s_arvalid,
  output wire                     s_arready,
  output wire [DATA_WIDTH-1:0]    s_rdata,
  output wire [ID_WIDTH-1:0]      s_rid,
  output wire                     s_rlast,
  output wire                     s_rvalid,

  // ddrphy_clkin side (HMIC side)
  output wire [ADDR_WIDTH-1:0]    d_awaddr,
  output wire                     d_awuser_ap,
  output wire [ID_WIDTH-1:0]      d_awuser_id,
  output wire [3:0]               d_awlen,
  output wire                     d_awvalid,
  input  wire                     d_awready,
  output wire [DATA_WIDTH-1:0]    d_wdata,
  output wire [DATA_WIDTH/8-1:0]  d_wstrb,
  input  wire                     d_wready,
  input  wire [ID_WIDTH-1:0]      d_wusero_id,
  input  wire                     d_wusero_last,
  output wire [ADDR_WIDTH-1:0]    d_araddr,
  output wire                     d_aruser_ap,
  output wire [ID_WIDTH-1:0]      d_aruser_id,
  output wire [3:0]               d_arlen,
  output wire                     d_arvalid,
  input  wire                     d_arready,
  input  wire [DATA_WIDTH-1:0]    d_rdata,
  input  wire [ID_WIDTH-1:0]      d_rid,
  input  wire                     d_rlast,
  input  wire                     d_rvalid
);

  reg                            cmd_toggle_src;
  reg                            cmd_busy_src;
  reg                            cmd_is_write_src;
  reg [ADDR_WIDTH-1:0]           cmd_addr_src;
  reg                            cmd_ap_src;
  reg [ID_WIDTH-1:0]             cmd_id_src;
  reg [3:0]                      cmd_len_src;
  reg [DATA_WIDTH-1:0]           cmd_wdata_src;
  reg [DATA_WIDTH/8-1:0]         cmd_wstrb_src;

  reg                            rsp_sync1_src;
  reg                            rsp_sync2_src;
  reg                            rsp_seen_src;
  reg                            rsp_pulse_src;
  reg [DATA_WIDTH-1:0]           rsp_data_src;
  reg [ID_WIDTH-1:0]             rsp_id_src;
  reg                            rsp_last_src;
  reg [ID_WIDTH-1:0]             rsp_wid_src;
  reg                            rsp_wlast_src;

  wire src_cmd_ready = !cmd_busy_src && !src_reset;
  wire src_read_fire = src_cmd_ready && s_arvalid && s_arready;
  wire src_write_fire = src_cmd_ready && s_awvalid && s_awready && s_wready;

  assign s_arready = src_cmd_ready;
  assign s_awready = src_cmd_ready && !s_arvalid;
  assign s_wready  = src_cmd_ready && !s_arvalid;
  assign s_rdata   = rsp_data_src;
  assign s_rid     = rsp_id_src;
  assign s_rlast   = rsp_last_src;
  assign s_rvalid  = rsp_pulse_src;
  assign s_wusero_id   = rsp_wid_src;
  assign s_wusero_last = rsp_wlast_src;

  // Destination-side command mailbox and response payload.  Payload buses
  // are sampled only after the synchronized command toggle changes.
  (* ASYNC_REG = "TRUE" *) reg cmd_sync1_dst;
  (* ASYNC_REG = "TRUE" *) reg cmd_sync2_dst;
  reg                            cmd_seen_dst;
  reg                            dst_pending;
  reg                            dst_read_wait;
  reg                            dst_is_write;
  reg [ADDR_WIDTH-1:0]           dst_addr;
  reg                            dst_ap;
  reg [ID_WIDTH-1:0]             dst_id;
  reg [3:0]                      dst_len;
  reg [DATA_WIDTH-1:0]           dst_wdata;
  reg [DATA_WIDTH/8-1:0]         dst_wstrb;
  reg                            rsp_toggle_dst;
  reg                            rsp_is_read_dst;
  reg [DATA_WIDTH-1:0]           rsp_data_dst;
  reg [ID_WIDTH-1:0]             rsp_id_dst;
  reg                            rsp_last_dst;
  reg [ID_WIDTH-1:0]             rsp_wid_dst;
  reg                            rsp_wlast_dst;
  reg [1:0]                      dst_release;

  assign d_awaddr    = dst_addr;
  assign d_awuser_ap = dst_ap;
  assign d_awuser_id = dst_id;
  assign d_awlen     = dst_len;
  assign d_awvalid   = dst_pending && dst_is_write && dst_release[1];
  assign d_wdata     = dst_wdata;
  assign d_wstrb     = dst_wstrb;
  assign d_araddr    = dst_addr;
  assign d_aruser_ap = dst_ap;
  assign d_aruser_id = dst_id;
  assign d_arlen     = dst_len;
  assign d_arvalid   = dst_pending && !dst_is_write && dst_release[1];

  always @(posedge src_clk) begin
    if (src_reset) begin
      cmd_toggle_src <= 1'b0;
      cmd_busy_src   <= 1'b0;
      cmd_is_write_src <= 1'b0;
      cmd_addr_src   <= {ADDR_WIDTH{1'b0}};
      cmd_ap_src     <= 1'b0;
      cmd_id_src     <= {ID_WIDTH{1'b0}};
      cmd_len_src    <= 4'h0;
      cmd_wdata_src  <= {DATA_WIDTH{1'b0}};
      cmd_wstrb_src  <= {(DATA_WIDTH/8){1'b0}};
      rsp_sync1_src  <= 1'b0;
      rsp_sync2_src  <= 1'b0;
      rsp_seen_src   <= 1'b0;
      rsp_pulse_src  <= 1'b0;
      rsp_data_src   <= {DATA_WIDTH{1'b0}};
      rsp_id_src     <= {ID_WIDTH{1'b0}};
      rsp_last_src   <= 1'b0;
      rsp_wid_src    <= {ID_WIDTH{1'b0}};
      rsp_wlast_src  <= 1'b0;
    end else begin
      rsp_sync1_src <= rsp_toggle_dst;
      rsp_sync2_src <= rsp_sync1_src;
      rsp_pulse_src <= 1'b0;

      if (cmd_busy_src && (rsp_sync2_src != rsp_seen_src)) begin
        rsp_seen_src <= rsp_sync2_src;
        cmd_busy_src <= 1'b0;
        if (rsp_is_read_dst) begin
          rsp_data_src <= rsp_data_dst;
          rsp_id_src   <= rsp_id_dst;
          rsp_last_src <= rsp_last_dst;
          rsp_pulse_src <= 1'b1;
        end else begin
          rsp_wid_src  <= rsp_wid_dst;
          rsp_wlast_src <= rsp_wlast_dst;
        end
      end else if (!cmd_busy_src) begin
        if (src_read_fire) begin
          cmd_busy_src   <= 1'b1;
          cmd_is_write_src <= 1'b0;
          cmd_addr_src   <= s_araddr;
          cmd_ap_src     <= s_aruser_ap;
          cmd_id_src     <= s_aruser_id;
          cmd_len_src    <= s_arlen;
          cmd_toggle_src <= ~cmd_toggle_src;
        end else if (src_write_fire) begin
          cmd_busy_src   <= 1'b1;
          cmd_is_write_src <= 1'b1;
          cmd_addr_src   <= s_awaddr;
          cmd_ap_src     <= s_awuser_ap;
          cmd_id_src     <= s_awuser_id;
          cmd_len_src    <= s_awlen;
          cmd_wdata_src  <= s_wdata;
          cmd_wstrb_src  <= s_wstrb;
          cmd_toggle_src <= ~cmd_toggle_src;
        end
      end
    end
  end

  always @(posedge dst_clk or posedge dst_reset) begin
    if (dst_reset) begin
      dst_release   <= 2'b00;
      cmd_sync1_dst <= 1'b0;
      cmd_sync2_dst <= 1'b0;
      cmd_seen_dst  <= 1'b0;
      dst_pending   <= 1'b0;
      dst_read_wait <= 1'b0;
      dst_is_write  <= 1'b0;
      dst_addr      <= {ADDR_WIDTH{1'b0}};
      dst_ap        <= 1'b0;
      dst_id        <= {ID_WIDTH{1'b0}};
      dst_len       <= 4'h0;
      dst_wdata     <= {DATA_WIDTH{1'b0}};
      dst_wstrb     <= {(DATA_WIDTH/8){1'b0}};
      rsp_toggle_dst <= 1'b0;
      rsp_is_read_dst <= 1'b0;
      rsp_data_dst  <= {DATA_WIDTH{1'b0}};
      rsp_id_dst    <= {ID_WIDTH{1'b0}};
      rsp_last_dst  <= 1'b0;
      rsp_wid_dst   <= {ID_WIDTH{1'b0}};
      rsp_wlast_dst <= 1'b0;
    end else begin
      dst_release   <= {dst_release[0], 1'b1};
      cmd_sync1_dst <= cmd_toggle_src;
      cmd_sync2_dst <= cmd_sync1_dst;

      if (!dst_release[1]) begin
        dst_pending   <= 1'b0;
        dst_read_wait <= 1'b0;
      end else begin
        if (!dst_pending && !dst_read_wait && (cmd_sync2_dst != cmd_seen_dst)) begin
          cmd_seen_dst <= cmd_sync2_dst;
          dst_pending  <= 1'b1;
          dst_is_write <= cmd_is_write_src;
          dst_addr     <= cmd_addr_src;
          dst_ap       <= cmd_ap_src;
          dst_id       <= cmd_id_src;
          dst_len      <= cmd_len_src;
          dst_wdata    <= cmd_wdata_src;
          dst_wstrb    <= cmd_wstrb_src;
        end else if (dst_pending && dst_is_write) begin
          if (d_awvalid && d_awready && d_wready) begin
            dst_pending    <= 1'b0;
            rsp_is_read_dst <= 1'b0;
            rsp_wid_dst    <= d_wusero_id;
            rsp_wlast_dst  <= d_wusero_last;
            rsp_toggle_dst <= ~rsp_toggle_dst;
          end
        end else if (dst_pending && !dst_is_write) begin
          if (d_arvalid && d_arready) begin
            dst_pending   <= 1'b0;
            dst_read_wait <= 1'b1;
          end
        end else if (dst_read_wait && d_rvalid) begin
          dst_read_wait  <= 1'b0;
          rsp_is_read_dst <= 1'b1;
          rsp_data_dst   <= d_rdata;
          rsp_id_dst     <= d_rid;
          rsp_last_dst   <= d_rlast;
          rsp_toggle_dst <= ~rsp_toggle_dst;
        end
      end
    end
  end

endmodule

// Reset only the HMIC-facing half of the CDC in the ddrphy_clkin domain.
// The request can assert without a running DDR clock (including loss of
// init_done), but its release must traverse two DDR clock edges.  This does
// not replace or drive the HMIC IP's own board-level reset.
module pgl50h_ddr_cdc_reset (
  input  wire ddr_clk,
  input  wire async_reset,
  output wire ddr_reset
);
  reg [1:0] release_pipe;

  always @(posedge ddr_clk or posedge async_reset) begin
    if (async_reset)
      release_pipe <= 2'b11;
    else
      release_pipe <= {release_pipe[0], 1'b0};
  end

  assign ddr_reset = release_pipe[1];
endmodule
