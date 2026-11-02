`timescale 1ns/1ps

// Four-master AXI4 memory fabric for the PGL50H SoC.
//
// The ingress boundary keeps one pending descriptor per master while a
// second descriptor may be active downstream, giving the required two-entry
// command capacity without a large combinational crossbar.  Only one HMIC
// transaction is active at a time.  Read responses use a two-beat FIFO so a
// ready downstream can deliver a burst without a fabric-created bubble.
module pgl50h_axi4_mem_fabric #(
  parameter integer ADDR_WIDTH   = 32,
  parameter integer DATA_WIDTH   = 256,
  parameter integer ID_WIDTH     = 4,
  /* verilator lint_off UNUSEDPARAM */
  parameter integer NUM_MASTERS  = 4
  /* verilator lint_on UNUSEDPARAM */
) (
  input  wire                         clk,
  input  wire                         reset,
  input  wire                         init_done,

  input  wire [ID_WIDTH-1:0]          m0_awid,
  input  wire [ADDR_WIDTH-1:0]        m0_awaddr,
  input  wire [3:0]                   m0_awlen,
  input  wire                         m0_awvalid,
  output wire                         m0_awready,
  input  wire [DATA_WIDTH-1:0]        m0_wdata,
  input  wire [DATA_WIDTH/8-1:0]      m0_wstrb,
  input  wire                         m0_wlast,
  input  wire                         m0_wvalid,
  output wire                         m0_wready,
  output wire [ID_WIDTH-1:0]          m0_bid,
  output wire [1:0]                   m0_bresp,
  output wire                         m0_bvalid,
  input  wire                         m0_bready,
  input  wire [ID_WIDTH-1:0]          m0_arid,
  input  wire [ADDR_WIDTH-1:0]        m0_araddr,
  input  wire [3:0]                   m0_arlen,
  input  wire                         m0_arvalid,
  output wire                         m0_arready,
  output wire [ID_WIDTH-1:0]          m0_rid,
  output wire [DATA_WIDTH-1:0]        m0_rdata,
  output wire [1:0]                   m0_rresp,
  output wire                         m0_rlast,
  output wire                         m0_rvalid,
  input  wire                         m0_rready,

  input  wire [ID_WIDTH-1:0]          m1_awid,
  input  wire [ADDR_WIDTH-1:0]        m1_awaddr,
  input  wire [3:0]                   m1_awlen,
  input  wire                         m1_awvalid,
  output wire                         m1_awready,
  input  wire [DATA_WIDTH-1:0]        m1_wdata,
  input  wire [DATA_WIDTH/8-1:0]      m1_wstrb,
  input  wire                         m1_wlast,
  input  wire                         m1_wvalid,
  output wire                         m1_wready,
  output wire [ID_WIDTH-1:0]          m1_bid,
  output wire [1:0]                   m1_bresp,
  output wire                         m1_bvalid,
  input  wire                         m1_bready,
  input  wire [ID_WIDTH-1:0]          m1_arid,
  input  wire [ADDR_WIDTH-1:0]        m1_araddr,
  input  wire [3:0]                   m1_arlen,
  input  wire                         m1_arvalid,
  output wire                         m1_arready,
  output wire [ID_WIDTH-1:0]          m1_rid,
  output wire [DATA_WIDTH-1:0]        m1_rdata,
  output wire [1:0]                   m1_rresp,
  output wire                         m1_rlast,
  output wire                         m1_rvalid,
  input  wire                         m1_rready,

  input  wire [ID_WIDTH-1:0]          m2_awid,
  input  wire [ADDR_WIDTH-1:0]        m2_awaddr,
  input  wire [3:0]                   m2_awlen,
  input  wire                         m2_awvalid,
  output wire                         m2_awready,
  input  wire [DATA_WIDTH-1:0]        m2_wdata,
  input  wire [DATA_WIDTH/8-1:0]      m2_wstrb,
  input  wire                         m2_wlast,
  input  wire                         m2_wvalid,
  output wire                         m2_wready,
  output wire [ID_WIDTH-1:0]          m2_bid,
  output wire [1:0]                   m2_bresp,
  output wire                         m2_bvalid,
  input  wire                         m2_bready,
  input  wire [ID_WIDTH-1:0]          m2_arid,
  input  wire [ADDR_WIDTH-1:0]        m2_araddr,
  input  wire [3:0]                   m2_arlen,
  input  wire                         m2_arvalid,
  output wire                         m2_arready,
  output wire [ID_WIDTH-1:0]          m2_rid,
  output wire [DATA_WIDTH-1:0]        m2_rdata,
  output wire [1:0]                   m2_rresp,
  output wire                         m2_rlast,
  output wire                         m2_rvalid,
  input  wire                         m2_rready,

  input  wire [ID_WIDTH-1:0]          m3_awid,
  input  wire [ADDR_WIDTH-1:0]        m3_awaddr,
  input  wire [3:0]                   m3_awlen,
  input  wire                         m3_awvalid,
  output wire                         m3_awready,
  input  wire [DATA_WIDTH-1:0]        m3_wdata,
  input  wire [DATA_WIDTH/8-1:0]      m3_wstrb,
  input  wire                         m3_wlast,
  input  wire                         m3_wvalid,
  output wire                         m3_wready,
  output wire [ID_WIDTH-1:0]          m3_bid,
  output wire [1:0]                   m3_bresp,
  output wire                         m3_bvalid,
  input  wire                         m3_bready,
  input  wire [ID_WIDTH-1:0]          m3_arid,
  input  wire [ADDR_WIDTH-1:0]        m3_araddr,
  input  wire [3:0]                   m3_arlen,
  input  wire                         m3_arvalid,
  output wire                         m3_arready,
  output wire [ID_WIDTH-1:0]          m3_rid,
  output wire [DATA_WIDTH-1:0]        m3_rdata,
  output wire [1:0]                   m3_rresp,
  output wire                         m3_rlast,
  output wire                         m3_rvalid,
  input  wire                         m3_rready,

  output wire [ID_WIDTH-1:0]          d_awid,
  output wire [ADDR_WIDTH-1:0]        d_awaddr,
  output wire [3:0]                   d_awlen,
  output wire                         d_awvalid,
  input  wire                         d_awready,
  output wire [DATA_WIDTH-1:0]        d_wdata,
  output wire [DATA_WIDTH/8-1:0]      d_wstrb,
  output wire                         d_wlast,
  output wire                         d_wvalid,
  input  wire                         d_wready,
  input  wire [ID_WIDTH-1:0]          d_bid,
  input  wire [1:0]                   d_bresp,
  input  wire                         d_bvalid,
  output wire                         d_bready,
  output wire [ID_WIDTH-1:0]          d_arid,
  output wire [ADDR_WIDTH-1:0]        d_araddr,
  output wire [3:0]                   d_arlen,
  output wire                         d_arvalid,
  input  wire                         d_arready,
  input  wire [ID_WIDTH-1:0]          d_rid,
  input  wire [DATA_WIDTH-1:0]        d_rdata,
  input  wire [1:0]                   d_rresp,
  input  wire                         d_rlast,
  input  wire                         d_rvalid,
  output wire                         d_rready,

  output wire [7:0]                   perf_max_wait0,
  output wire [7:0]                   perf_max_wait1,
  output wire [7:0]                   perf_max_wait2,
  output wire [7:0]                   perf_max_wait3
);

  localparam [3:0] ST_IDLE       = 4'd0;
  localparam [3:0] ST_AR_SEND    = 4'd1;
  localparam [3:0] ST_RD         = 4'd2;
  localparam [3:0] ST_WR_SEND    = 4'd3;
  localparam [3:0] ST_WR_WAIT_W  = 4'd4;
  localparam [3:0] ST_WR_BWAIT   = 4'd5;
  localparam [3:0] ST_WR_RESP    = 4'd6;

  reg [3:0] state;
  reg [1:0] rr_ptr;
  reg [1:0] active_owner;
  reg [ID_WIDTH-1:0] active_id;
  reg [ADDR_WIDTH-1:0] active_addr;
  reg [3:0] active_len;
  reg [3:0] active_beat;
  reg [DATA_WIDTH-1:0] active_wdata;
  reg [DATA_WIDTH/8-1:0] active_wstrb;
  reg active_wlast;
  reg downstream_aw_sent;
  reg downstream_w_sent;

  reg aw_pending [0:3];
  reg w_pending [0:3];
  reg ar_pending [0:3];
  reg [ID_WIDTH-1:0] aw_id_q [0:3];
  reg [ADDR_WIDTH-1:0] aw_addr_q [0:3];
  reg [3:0] aw_len_q [0:3];
  reg [DATA_WIDTH-1:0] w_data_q [0:3];
  reg [DATA_WIDTH/8-1:0] w_strb_q [0:3];
  reg w_last_q [0:3];
  reg [ID_WIDTH-1:0] ar_id_q [0:3];
  reg [ADDR_WIDTH-1:0] ar_addr_q [0:3];
  reg [3:0] ar_len_q [0:3];
  reg [7:0] starve_count [0:3];
  reg [7:0] max_wait [0:3];

  reg [DATA_WIDTH-1:0] r_fifo_data [0:1];
  reg r_fifo_last [0:1];
  reg [ID_WIDTH-1:0] r_fifo_id [0:1];
  reg [1:0] r_fifo_resp [0:1];
  reg r_head;
  reg r_tail;
  reg [1:0] r_count;
  reg [ID_WIDTH-1:0] b_id_reg;
  reg [1:0] b_resp_reg;
  reg choose_valid;
  reg [1:0] choose_idx;
  reg choose_write;
  reg direct_ar_valid;
  reg [1:0] direct_ar_idx;
  integer k;
  integer idx;
  integer i;

  wire request0 = ar_pending[0] || (aw_pending[0] && w_pending[0]);
  wire request1 = ar_pending[1] || (aw_pending[1] && w_pending[1]);
  wire request2 = ar_pending[2] || (aw_pending[2] && w_pending[2]);
  wire request3 = ar_pending[3] || (aw_pending[3] && w_pending[3]);
  wire current_write0 = m0_awvalid && m0_wvalid;
  wire current_write1 = m1_awvalid && m1_wvalid;
  wire current_write2 = m2_awvalid && m2_wvalid;
  wire current_write3 = m3_awvalid && m3_wvalid;
  wire owner_rready = (active_owner == 2'd0) ? m0_rready :
                      (active_owner == 2'd1) ? m1_rready :
                      (active_owner == 2'd2) ? m2_rready : m3_rready;
  wire owner_bready = (active_owner == 2'd0) ? m0_bready :
                      (active_owner == 2'd1) ? m1_bready :
                      (active_owner == 2'd2) ? m2_bready : m3_bready;
  wire rd_push = (state == ST_RD) && d_rvalid && d_rready;
  wire rd_pop = (state == ST_RD) && (r_count != 0) && owner_rready;

  // Fixed-size arbitration.  Starved masters are promoted first; otherwise
  // the round-robin pointer provides deterministic service order.
  always @* begin
    choose_valid = 1'b0;
    choose_idx = 2'd0;
    choose_write = 1'b0;
    direct_ar_valid = 1'b0;
    direct_ar_idx = 2'd0;
    idx = 0;
    for (k = 0; k < 4; k = k + 1) begin
      if (!choose_valid && ((k == 0 && request0 && starve_count[0] == 8'hff) ||
                            (k == 1 && request1 && starve_count[1] == 8'hff) ||
                            (k == 2 && request2 && starve_count[2] == 8'hff) ||
                            (k == 3 && request3 && starve_count[3] == 8'hff))) begin
        choose_valid = 1'b1;
        choose_idx = k[1:0];
        choose_write = (k == 0) ? (aw_pending[0] && w_pending[0] && !ar_pending[0]) :
                       (k == 1) ? (aw_pending[1] && w_pending[1] && !ar_pending[1]) :
                       (k == 2) ? (aw_pending[2] && w_pending[2] && !ar_pending[2]) :
                                  (aw_pending[3] && w_pending[3] && !ar_pending[3]);
      end
    end
    if (!choose_valid) begin
      idx = 0;
      for (k = 0; k < 4; k = k + 1) begin
        idx = {30'd0, rr_ptr} + k;
        if (idx >= 4) idx = idx - 4;
        if (!choose_valid && ((idx == 0 && request0) || (idx == 1 && request1) ||
                              (idx == 2 && request2) || (idx == 3 && request3))) begin
          choose_valid = 1'b1;
          choose_idx = idx[1:0];
          choose_write = (idx == 0) ? (aw_pending[0] && w_pending[0] && !ar_pending[0]) :
                         (idx == 1) ? (aw_pending[1] && w_pending[1] && !ar_pending[1]) :
                         (idx == 2) ? (aw_pending[2] && w_pending[2] && !ar_pending[2]) :
                                      (aw_pending[3] && w_pending[3] && !ar_pending[3]);
        end
      end
    end

    // Fast path for the common CPU-only case: when the fabric is idle and
    // there is no queued request, capture a currently presented read directly
    // into the active descriptor.  This preserves the register boundary (the
    // downstream AR is still emitted from ST_AR_SEND) while removing one
    // queue-capture/arbitration cycle from each isolated refill.  A simultaneous
    // AW/W pair disables the shortcut so both channels can be queued normally.
    if ((state == ST_IDLE) && init_done &&
        !request0 && !request1 && !request2 && !request3 &&
        !current_write0 && !current_write1 &&
        !current_write2 && !current_write3) begin
      for (k = 0; k < 4; k = k + 1) begin
        idx = {30'd0, rr_ptr} + k;
        if (idx >= 4) idx = idx - 4;
        if (!direct_ar_valid &&
            ((idx == 0 && m0_arvalid) || (idx == 1 && m1_arvalid) ||
             (idx == 2 && m2_arvalid) || (idx == 3 && m3_arvalid))) begin
          direct_ar_valid = 1'b1;
          direct_ar_idx = idx[1:0];
        end
      end
    end
  end

  assign m0_awready = init_done && !aw_pending[0];
  assign m1_awready = init_done && !aw_pending[1];
  assign m2_awready = init_done && !aw_pending[2];
  assign m3_awready = init_done && !aw_pending[3];
  assign m0_arready = init_done && !ar_pending[0];
  assign m1_arready = init_done && !ar_pending[1];
  assign m2_arready = init_done && !ar_pending[2];
  assign m3_arready = init_done && !ar_pending[3];
  assign m0_wready = init_done && ((aw_pending[0] && !w_pending[0]) || ((state == ST_WR_WAIT_W) && active_owner == 0));
  assign m1_wready = init_done && ((aw_pending[1] && !w_pending[1]) || ((state == ST_WR_WAIT_W) && active_owner == 1));
  assign m2_wready = init_done && ((aw_pending[2] && !w_pending[2]) || ((state == ST_WR_WAIT_W) && active_owner == 2));
  assign m3_wready = init_done && ((aw_pending[3] && !w_pending[3]) || ((state == ST_WR_WAIT_W) && active_owner == 3));

  assign m0_rvalid = (state == ST_RD) && active_owner == 0 && (r_count != 0);
  assign m1_rvalid = (state == ST_RD) && active_owner == 1 && (r_count != 0);
  assign m2_rvalid = (state == ST_RD) && active_owner == 2 && (r_count != 0);
  assign m3_rvalid = (state == ST_RD) && active_owner == 3 && (r_count != 0);
  assign m0_rid = (r_count != 0) ? r_fifo_id[r_head] : active_id;
  assign m1_rid = m0_rid; assign m2_rid = m0_rid; assign m3_rid = m0_rid;
  assign m0_rdata = (r_count != 0) ? r_fifo_data[r_head] : {DATA_WIDTH{1'b0}};
  assign m1_rdata = m0_rdata; assign m2_rdata = m0_rdata; assign m3_rdata = m0_rdata;
  assign m0_rlast = (r_count != 0) ? r_fifo_last[r_head] : 1'b0;
  assign m1_rlast = m0_rlast; assign m2_rlast = m0_rlast; assign m3_rlast = m0_rlast;
  assign m0_rresp = (r_count != 0) ? r_fifo_resp[r_head] : 2'b00;
  assign m1_rresp = m0_rresp; assign m2_rresp = m0_rresp; assign m3_rresp = m0_rresp;

  assign m0_bvalid = (state == ST_WR_RESP) && active_owner == 0;
  assign m1_bvalid = (state == ST_WR_RESP) && active_owner == 1;
  assign m2_bvalid = (state == ST_WR_RESP) && active_owner == 2;
  assign m3_bvalid = (state == ST_WR_RESP) && active_owner == 3;
  assign m0_bid = b_id_reg; assign m1_bid = b_id_reg; assign m2_bid = b_id_reg; assign m3_bid = b_id_reg;
  assign m0_bresp = b_resp_reg; assign m1_bresp = b_resp_reg; assign m2_bresp = b_resp_reg; assign m3_bresp = b_resp_reg;

  assign d_arid = active_id;
  assign d_araddr = active_addr;
  assign d_arlen = active_len;
  assign d_arvalid = (state == ST_AR_SEND);
  assign d_rready = (state == ST_RD) && (r_count < 2);
  assign d_awid = active_id;
  assign d_awaddr = active_addr;
  assign d_awlen = active_len;
  assign d_awvalid = (state == ST_WR_SEND) && !downstream_aw_sent;
  assign d_wdata = active_wdata;
  assign d_wstrb = active_wstrb;
  assign d_wlast = active_wlast || (active_beat == active_len);
  assign d_wvalid = (state == ST_WR_SEND) && !downstream_w_sent;
  assign d_bready = (state == ST_WR_BWAIT);

  assign perf_max_wait0 = max_wait[0];
  assign perf_max_wait1 = max_wait[1];
  assign perf_max_wait2 = max_wait[2];
  assign perf_max_wait3 = max_wait[3];

  always @(posedge clk) begin
    if (reset) begin
      state <= ST_IDLE;
      rr_ptr <= 2'd0;
      active_owner <= 2'd0;
      active_id <= {ID_WIDTH{1'b0}};
      active_addr <= {ADDR_WIDTH{1'b0}};
      active_len <= 4'd0;
      active_beat <= 4'd0;
      active_wdata <= {DATA_WIDTH{1'b0}};
      active_wstrb <= {(DATA_WIDTH/8){1'b0}};
      active_wlast <= 1'b0;
      downstream_aw_sent <= 1'b0;
      downstream_w_sent <= 1'b0;
      r_head <= 1'b0;
      r_tail <= 1'b0;
      r_count <= 2'd0;
      r_fifo_id[0] <= {ID_WIDTH{1'b0}};
      r_fifo_id[1] <= {ID_WIDTH{1'b0}};
      r_fifo_resp[0] <= 2'b00;
      r_fifo_resp[1] <= 2'b00;
      b_id_reg <= {ID_WIDTH{1'b0}};
      b_resp_reg <= 2'b00;
      for (i = 0; i < 4; i = i + 1) begin
        aw_pending[i] <= 1'b0;
        w_pending[i] <= 1'b0;
        ar_pending[i] <= 1'b0;
        aw_id_q[i] <= {ID_WIDTH{1'b0}};
        aw_addr_q[i] <= {ADDR_WIDTH{1'b0}};
        aw_len_q[i] <= 4'd0;
        w_data_q[i] <= {DATA_WIDTH{1'b0}};
        w_strb_q[i] <= {(DATA_WIDTH/8){1'b0}};
        w_last_q[i] <= 1'b0;
        ar_id_q[i] <= {ID_WIDTH{1'b0}};
        ar_addr_q[i] <= {ADDR_WIDTH{1'b0}};
        ar_len_q[i] <= 4'd0;
        starve_count[i] <= 8'd0;
        max_wait[i] <= 8'd0;
      end
    end else begin
      if (m0_awvalid && m0_awready) begin aw_pending[0] <= 1'b1; aw_id_q[0] <= m0_awid; aw_addr_q[0] <= m0_awaddr; aw_len_q[0] <= m0_awlen; end
      if (m1_awvalid && m1_awready) begin aw_pending[1] <= 1'b1; aw_id_q[1] <= m1_awid; aw_addr_q[1] <= m1_awaddr; aw_len_q[1] <= m1_awlen; end
      if (m2_awvalid && m2_awready) begin aw_pending[2] <= 1'b1; aw_id_q[2] <= m2_awid; aw_addr_q[2] <= m2_awaddr; aw_len_q[2] <= m2_awlen; end
      if (m3_awvalid && m3_awready) begin aw_pending[3] <= 1'b1; aw_id_q[3] <= m3_awid; aw_addr_q[3] <= m3_awaddr; aw_len_q[3] <= m3_awlen; end
      if (m0_arvalid && m0_arready && !(direct_ar_valid && direct_ar_idx == 2'd0)) begin ar_pending[0] <= 1'b1; ar_id_q[0] <= m0_arid; ar_addr_q[0] <= m0_araddr; ar_len_q[0] <= m0_arlen; end
      if (m1_arvalid && m1_arready && !(direct_ar_valid && direct_ar_idx == 2'd1)) begin ar_pending[1] <= 1'b1; ar_id_q[1] <= m1_arid; ar_addr_q[1] <= m1_araddr; ar_len_q[1] <= m1_arlen; end
      if (m2_arvalid && m2_arready && !(direct_ar_valid && direct_ar_idx == 2'd2)) begin ar_pending[2] <= 1'b1; ar_id_q[2] <= m2_arid; ar_addr_q[2] <= m2_araddr; ar_len_q[2] <= m2_arlen; end
      if (m3_arvalid && m3_arready && !(direct_ar_valid && direct_ar_idx == 2'd3)) begin ar_pending[3] <= 1'b1; ar_id_q[3] <= m3_arid; ar_addr_q[3] <= m3_araddr; ar_len_q[3] <= m3_arlen; end
      if (m0_wvalid && m0_wready && !(state == ST_WR_WAIT_W && active_owner == 0)) begin w_pending[0] <= 1'b1; w_data_q[0] <= m0_wdata; w_strb_q[0] <= m0_wstrb; w_last_q[0] <= m0_wlast; end
      if (m1_wvalid && m1_wready && !(state == ST_WR_WAIT_W && active_owner == 1)) begin w_pending[1] <= 1'b1; w_data_q[1] <= m1_wdata; w_strb_q[1] <= m1_wstrb; w_last_q[1] <= m1_wlast; end
      if (m2_wvalid && m2_wready && !(state == ST_WR_WAIT_W && active_owner == 2)) begin w_pending[2] <= 1'b1; w_data_q[2] <= m2_wdata; w_strb_q[2] <= m2_wstrb; w_last_q[2] <= m2_wlast; end
      if (m3_wvalid && m3_wready && !(state == ST_WR_WAIT_W && active_owner == 3)) begin w_pending[3] <= 1'b1; w_data_q[3] <= m3_wdata; w_strb_q[3] <= m3_wstrb; w_last_q[3] <= m3_wlast; end

      for (i = 0; i < 4; i = i + 1) begin
        if ((i == 0 && request0) || (i == 1 && request1) || (i == 2 && request2) || (i == 3 && request3)) begin
          if (choose_valid && state == ST_IDLE && choose_idx == i[1:0]) starve_count[i] <= 8'd0;
          else if (starve_count[i] != 8'hff) starve_count[i] <= starve_count[i] + 1'b1;
          if (starve_count[i] > max_wait[i]) max_wait[i] <= starve_count[i];
        end else begin
          starve_count[i] <= 8'd0;
        end
      end

      case (state)
        ST_IDLE: begin
          if (direct_ar_valid) begin
            active_owner <= direct_ar_idx;
            rr_ptr <= direct_ar_idx + 2'd1;
            active_beat <= 4'd0;
            r_head <= 1'b0;
            r_tail <= 1'b0;
            r_count <= 2'd0;
            case (direct_ar_idx)
              2'd0: begin active_id <= m0_arid; active_addr <= m0_araddr; active_len <= m0_arlen; end
              2'd1: begin active_id <= m1_arid; active_addr <= m1_araddr; active_len <= m1_arlen; end
              2'd2: begin active_id <= m2_arid; active_addr <= m2_araddr; active_len <= m2_arlen; end
              default: begin active_id <= m3_arid; active_addr <= m3_araddr; active_len <= m3_arlen; end
            endcase
            state <= ST_AR_SEND;
          end else if (choose_valid && init_done) begin
            active_owner <= choose_idx;
            rr_ptr <= choose_idx + 2'd1;
            active_beat <= 4'd0;
            r_head <= 1'b0;
            r_tail <= 1'b0;
            r_count <= 2'd0;
            if (choose_write) begin
              active_id <= aw_id_q[choose_idx];
              active_addr <= aw_addr_q[choose_idx];
              active_len <= aw_len_q[choose_idx];
              active_wdata <= w_data_q[choose_idx];
              active_wstrb <= w_strb_q[choose_idx];
              active_wlast <= w_last_q[choose_idx];
              aw_pending[choose_idx] <= 1'b0;
              w_pending[choose_idx] <= 1'b0;
              downstream_aw_sent <= 1'b0;
              downstream_w_sent <= 1'b0;
              state <= ST_WR_SEND;
            end else begin
              active_id <= ar_id_q[choose_idx];
              active_addr <= ar_addr_q[choose_idx];
              active_len <= ar_len_q[choose_idx];
              ar_pending[choose_idx] <= 1'b0;
              state <= ST_AR_SEND;
            end
          end
        end
        ST_AR_SEND: begin
          if (d_arvalid && d_arready) state <= ST_RD;
        end
        ST_RD: begin
          if (rd_push) begin
            r_fifo_data[r_tail] <= d_rdata;
            r_fifo_last[r_tail] <= d_rlast || (active_beat == active_len);
            r_fifo_id[r_tail] <= d_rid;
            r_fifo_resp[r_tail] <= d_rresp;
            r_tail <= r_tail ^ 1'b1;
            active_beat <= active_beat + 1'b1;
          end
          if (rd_pop) r_head <= r_head ^ 1'b1;
          case ({rd_push, rd_pop})
            2'b10: r_count <= r_count + 1'b1;
            2'b01: r_count <= r_count - 1'b1;
            default: r_count <= r_count;
          endcase
          if (rd_pop && r_fifo_last[r_head] && (r_count == 1) && !rd_push) state <= ST_IDLE;
        end
        ST_WR_SEND: begin
          if (d_awvalid && d_awready) downstream_aw_sent <= 1'b1;
          if (d_wvalid && d_wready) downstream_w_sent <= 1'b1;
          if ((downstream_aw_sent || (d_awvalid && d_awready)) &&
              (downstream_w_sent || (d_wvalid && d_wready))) begin
            if (active_wlast || (active_beat == active_len)) begin
              state <= ST_WR_BWAIT;
            end else begin
              active_beat <= active_beat + 1'b1;
              downstream_aw_sent <= 1'b1;
              downstream_w_sent <= 1'b0;
              state <= ST_WR_WAIT_W;
            end
          end
        end
        ST_WR_WAIT_W: begin
          if ((active_owner == 0 && m0_wvalid && m0_wready) ||
              (active_owner == 1 && m1_wvalid && m1_wready) ||
              (active_owner == 2 && m2_wvalid && m2_wready) ||
              (active_owner == 3 && m3_wvalid && m3_wready)) begin
            if (active_owner == 0) begin active_wdata <= m0_wdata; active_wstrb <= m0_wstrb; active_wlast <= m0_wlast; end
            else if (active_owner == 1) begin active_wdata <= m1_wdata; active_wstrb <= m1_wstrb; active_wlast <= m1_wlast; end
            else if (active_owner == 2) begin active_wdata <= m2_wdata; active_wstrb <= m2_wstrb; active_wlast <= m2_wlast; end
            else begin active_wdata <= m3_wdata; active_wstrb <= m3_wstrb; active_wlast <= m3_wlast; end
            downstream_w_sent <= 1'b0;
            state <= ST_WR_SEND;
          end
        end
        ST_WR_BWAIT: begin
          if (d_bvalid && d_bready) begin
            b_id_reg <= d_bid;
            b_resp_reg <= d_bresp;
            state <= ST_WR_RESP;
          end
        end
        ST_WR_RESP: begin
          if (owner_bready) state <= ST_IDLE;
        end
        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
