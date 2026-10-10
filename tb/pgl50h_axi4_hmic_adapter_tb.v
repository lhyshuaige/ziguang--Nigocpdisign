`timescale 1ns/1ps

// Contract test for the internal AXI4 -> PGL50H HMIC user-port adapter.
// The HMIC model deliberately stalls command acceptance and the AXI model
// deliberately stalls R/B consumption to prove registered boundary holding.
module pgl50h_axi4_hmic_adapter_tb;
  localparam integer AW = 28;
  localparam integer DW = 256;
  localparam integer SW = DW / 8;

  reg clk;
  reg reset;
  reg init_done;

  reg [3:0] s_awid;
  reg [31:0] s_awaddr;
  reg [3:0] s_awlen;
  reg s_awvalid;
  wire s_awready;
  reg [DW-1:0] s_wdata;
  reg [SW-1:0] s_wstrb;
  reg s_wlast;
  reg s_wvalid;
  wire s_wready;
  wire [3:0] s_bid;
  wire [1:0] s_bresp;
  wire s_bvalid;
  reg s_bready;

  reg [3:0] s_arid;
  reg [31:0] s_araddr;
  reg [3:0] s_arlen;
  reg s_arvalid;
  wire s_arready;
  wire [3:0] s_rid;
  wire [DW-1:0] s_rdata;
  wire [1:0] s_rresp;
  wire s_rlast;
  wire s_rvalid;
  reg s_rready;

  wire [AW-1:0] h_awaddr;
  wire h_awuser_ap;
  wire [3:0] h_awuser_id;
  wire [3:0] h_awlen;
  reg h_awready;
  wire h_awvalid;
  wire [DW-1:0] h_wdata;
  wire [SW-1:0] h_wstrb;
  reg h_wready;
  wire [3:0] h_wusero_id;
  wire h_wusero_last;
  wire [AW-1:0] h_araddr;
  wire h_aruser_ap;
  wire [3:0] h_aruser_id;
  wire [3:0] h_arlen;
  reg h_arready;
  wire h_arvalid;
  reg [DW-1:0] h_rdata;
  reg [3:0] h_rid;
  reg h_rlast;
  reg h_rvalid;

  reg [DW-1:0] mem [0:31];
  reg pending_r;
  reg [AW-1:0] pending_addr;
  integer i;
  integer read_beats;
  integer read_wait;
  integer write_beats;
  integer h_ar_count;
  integer invalid_ar_before;
  integer invalid_r_count;
  integer invalid_w_count;
  reg [DW-1:0] wbeat0;
  reg [DW-1:0] wbeat1;

  always #5 clk = ~clk;

  // The HMIC controller returns the accepted write ID/last metadata in the
  // same cycle as the user-port write.  Model that timing combinationally so
  // the adapter can validate the metadata without a simulation race.
  assign h_wusero_id = h_awuser_id;
  assign h_wusero_last = 1'b1;

  pgl50h_axi4_hmic_adapter #(
    .AXI_ADDR_WIDTH(32), .HMIC_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW), .ID_WIDTH(4),
    .CPU_MEM_BASE(32'h8000_0000), .HMIC_ADDR_SHIFT(3)
  ) dut (
    .clk(clk), .reset(reset), .init_done(init_done),
    .s_axi_awid(s_awid), .s_axi_awaddr(s_awaddr), .s_axi_awlen(s_awlen),
    .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
    .s_axi_wdata(s_wdata), .s_axi_wstrb(s_wstrb), .s_axi_wlast(s_wlast),
    .s_axi_wvalid(s_wvalid), .s_axi_wready(s_wready),
    .s_axi_bid(s_bid), .s_axi_bresp(s_bresp), .s_axi_bvalid(s_bvalid),
    .s_axi_bready(s_bready),
    .s_axi_arid(s_arid), .s_axi_araddr(s_araddr), .s_axi_arlen(s_arlen),
    .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
    .s_axi_rid(s_rid), .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp),
    .s_axi_rlast(s_rlast), .s_axi_rvalid(s_rvalid), .s_axi_rready(s_rready),
    .axi_awaddr(h_awaddr), .axi_awuser_ap(h_awuser_ap), .axi_awuser_id(h_awuser_id),
    .axi_awlen(h_awlen), .axi_awready(h_awready), .axi_awvalid(h_awvalid),
    .axi_wdata(h_wdata), .axi_wstrb(h_wstrb), .axi_wready(h_wready),
    .axi_wusero_id(h_wusero_id), .axi_wusero_last(h_wusero_last),
    .axi_araddr(h_araddr), .axi_aruser_ap(h_aruser_ap), .axi_aruser_id(h_aruser_id),
    .axi_arlen(h_arlen), .axi_arready(h_arready), .axi_arvalid(h_arvalid),
    .axi_rdata(h_rdata), .axi_rid(h_rid), .axi_rlast(h_rlast), .axi_rvalid(h_rvalid)
  );

  always @(posedge clk) begin
    h_rvalid <= 1'b0;
    if (h_arvalid && h_arready) begin
      if (h_arlen !== 4'd0)
        $fatal(1, "HMIC adapter must issue single-beat commands");
      pending_addr <= h_araddr;
      pending_r <= 1'b1;
      h_ar_count = h_ar_count + 1;
    end
    if (pending_r) begin
      h_rdata <= mem[pending_addr[4:0]];
      h_rid <= 4'h3;
      h_rlast <= 1'b1;
      h_rvalid <= 1'b1;
      pending_r <= 1'b0;
    end
    if (h_awvalid && h_awready && h_wready) begin
      if (h_awaddr !== (write_beats == 0 ? 28'h0000_008 : 28'h0000_00c))
        $fatal(1, "unexpected HMIC write addr beat %0d: %h", write_beats, h_awaddr);
      mem[h_awaddr[4:0]] <= h_wdata;
      write_beats = write_beats + 1;
    end
  end

  task automatic issue_read;
    begin
      while (!s_arready) @(posedge clk);
      s_arid <= 4'h3;
      s_araddr <= 32'h8000_0040;
      s_arlen <= 4'd1;
      s_arvalid <= 1'b1;
      @(posedge clk);
      s_arvalid <= 1'b0;
      s_rready <= 1'b0;
      read_wait = 0;
      while (read_beats < 2) begin
        @(posedge clk);
        read_wait = read_wait + 1;
        if (read_wait == 2) s_rready <= 1'b1;
      if (s_rvalid && s_rready) begin
          if (s_rid !== 4'h3 || s_rresp !== 2'b00 || !s_rlast && (read_beats == 1))
            $fatal(1, "AXI read response metadata mismatch");
          if (s_rdata !== mem[8 + (read_beats * 4)])
            $fatal(1, "AXI read data mismatch at beat %0d", read_beats);
          read_beats = read_beats + 1;
        end
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    init_done = 1'b0;
    s_awid = 4'h0; s_awaddr = 32'h0; s_awlen = 4'h0; s_awvalid = 1'b0;
    s_wdata = {DW{1'b0}}; s_wstrb = {SW{1'b0}}; s_wlast = 1'b1; s_wvalid = 1'b0;
    s_bready = 1'b0;
    s_arid = 4'h0; s_araddr = 32'h0; s_arlen = 4'h0; s_arvalid = 1'b0;
    s_rready = 1'b1;
    h_awready = 1'b0; h_wready = 1'b0; h_arready = 1'b0;
    h_rdata = {DW{1'b0}}; h_rid = 4'h0; h_rlast = 1'b1; h_rvalid = 1'b0;
    pending_r = 1'b0; pending_addr = {AW{1'b0}};
    read_beats = 0; write_beats = 0; h_ar_count = 0;
    read_wait = 0;
    wbeat0 = {64'h1111_0007,64'h1111_0006,64'h1111_0005,64'h1111_0004};
    wbeat1 = {64'h2222_0003,64'h2222_0002,64'h2222_0001,64'h2222_0000};
    for (i = 0; i < 32; i = i + 1) mem[i] = {4{64'h0}};
    mem[8] = {64'h0000_0007,64'h0000_0006,64'h0000_0005,64'h0000_0004};
    mem[12] = {64'h0000_0003,64'h0000_0002,64'h0000_0001,64'h0000_0000};

    repeat (2) @(posedge clk);
    reset = 1'b0;
    s_arvalid = 1'b1;
    s_araddr = 32'h8000_0040;
    s_arlen = 4'd0;
    @(posedge clk);
    if (s_arready !== 1'b0)
      $fatal(1, "AXI read accepted before init_done");
    s_arvalid = 1'b0;
    init_done = 1'b1;
    h_arready = 1'b1;
    issue_read();

    // AW and W may be accepted independently; HMIC command acceptance is
    // stalled for one cycle to prove the adapter holds both registered fields.
    while (!s_awready) @(posedge clk);
    s_awid = 4'h5; s_awaddr = 32'h8000_0040; s_awlen = 4'd1; s_awvalid = 1'b1;
    while (!s_awready) @(posedge clk);
    @(posedge clk);
    s_awvalid = 1'b0;
    while (!s_wready) @(posedge clk);
    s_wdata = wbeat0; s_wstrb = {SW{1'b1}}; s_wlast = 1'b0; s_wvalid = 1'b1;
    while (!s_wready) @(posedge clk);
    @(posedge clk);
    s_wvalid = 1'b0;
    // Release the HMIC command only after the first AXI W beat is buffered;
    // the adapter must not advertise the next W beat until this command is
    // accepted downstream.
    h_awready = 1'b1;
    h_wready = 1'b1;
    while (!s_wready) @(posedge clk);
    s_wdata = wbeat1; s_wstrb = {SW{1'b1}}; s_wlast = 1'b1; s_wvalid = 1'b1;
    while (!s_wready) @(posedge clk);
    @(posedge clk);
    s_wvalid = 1'b0;
    s_bready = 1'b1;
    while (!s_bvalid) @(posedge clk);
    if (s_bid !== 4'h5 || s_bresp !== 2'b00)
      $fatal(1, "AXI write response mismatch");
    if (write_beats !== 2)
      $fatal(1, "expected two HMIC write commands, got %0d", write_beats);
    if (mem[8] !== wbeat0 || mem[12] !== wbeat1)
      $fatal(1, "HMIC write data mismatch");

    // An invalid read must be completed as a DECERR burst without emitting
    // any HMIC command.  The adapter still returns the requested beat count
    // so the upstream AXI master cannot be left waiting for RLAST.
    @(posedge clk);
    invalid_ar_before = h_ar_count;
    s_arid = 4'h6; s_araddr = 32'h7fff_ffe0; s_arlen = 4'd1; s_arvalid = 1'b1;
    while (!s_arready) @(posedge clk);
    @(posedge clk); s_arvalid = 1'b0; s_rready = 1'b1;
    invalid_r_count = 0;
    while (invalid_r_count < 2) begin
      while (!s_rvalid) @(negedge clk);
      if (s_rresp !== 2'b10 || s_rid !== 4'h6 || s_rlast !== (invalid_r_count == 1))
        $fatal(1, "invalid AXI read was not returned as DECERR beat %0d", invalid_r_count);
      if (s_rdata !== {DW{1'b0}})
        $fatal(1, "invalid AXI read returned non-zero data");
      @(posedge clk);
      invalid_r_count = invalid_r_count + 1;
    end
    if (h_ar_count !== invalid_ar_before)
      $fatal(1, "invalid AXI read unexpectedly reached HMIC");

    // An invalid write consumes all W beats and returns B/DECERR; no partial
    // write is allowed to escape onto the HMIC side.
    while (!s_awready) @(posedge clk);
    s_awid = 4'h7; s_awaddr = 32'hffff_ffe0; s_awlen = 4'd1; s_awvalid = 1'b1;
    @(posedge clk); s_awvalid = 1'b0;
    invalid_w_count = 0;
    while (invalid_w_count < 2) begin
      while (!s_wready) @(posedge clk);
      s_wdata = {DW{1'b0}}; s_wstrb = {SW{1'b1}};
      s_wlast = (invalid_w_count == 1); s_wvalid = 1'b1;
      @(posedge clk); s_wvalid = 1'b0;
      invalid_w_count = invalid_w_count + 1;
    end
    s_bready = 1'b1;
    while (!s_bvalid) @(posedge clk);
    if (s_bid !== 4'h7 || s_bresp !== 2'b10)
      $fatal(1, "invalid AXI write was not returned as DECERR");
    if (write_beats !== 2)
      $fatal(1, "invalid AXI write unexpectedly reached HMIC");

    $display("PGL50H AXI4-HMIC adapter contract PASS");
    $finish;
  end
endmodule
