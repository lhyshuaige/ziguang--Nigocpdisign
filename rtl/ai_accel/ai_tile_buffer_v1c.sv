module ai_tile_buffer_v1c #(
  parameter integer DEPTH = 6,
  parameter integer DATA_WIDTH = 216,
  parameter integer ADDR_BITS = (DEPTH > 1) ? $clog2(DEPTH) : 1
) (
  input  wire                   clk,
  input  wire                   write_bank,
  input  wire                   write_valid,
  input  wire [ADDR_BITS-1:0]   write_addr,
  input  wire [DATA_WIDTH-1:0]  write_data,
  input  wire                   read_bank,
  input  wire [ADDR_BITS-1:0]   read_addr,
  output wire [DATA_WIDTH-1:0]  read_data
);
  // Separate banks let the AXI loader write the next tile while the core
  // reads the current tile. No data reset is needed: validity lives outside.
  reg [DATA_WIDTH-1:0] bank0 [0:DEPTH-1];
  reg [DATA_WIDTH-1:0] bank1 [0:DEPTH-1];
  reg [DATA_WIDTH-1:0] bank0_read_q, bank1_read_q;
  reg read_bank_q;

  assign read_data = read_bank_q ? bank1_read_q : bank0_read_q;

  always @(posedge clk) begin
    if (write_valid && !write_bank)
      bank0[write_addr] <= write_data;
    if (write_valid && write_bank)
      bank1[write_addr] <= write_data;
    bank0_read_q <= bank0[read_addr];
    bank1_read_q <= bank1[read_addr];
    read_bank_q <= read_bank;
  end
endmodule
