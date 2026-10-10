// PDS-only fallback-memory copy. The real HMIC build does not instantiate this\n// branch, but keeping the elaboration-safe size below the Fabric Compiler loop\n// expansion limit allows mixed legacy configurations to synthesize.\n// Small synchronous fallback memory used for RTL smoke tests and early
// bring-up.  The external DDR3/AXI implementation is deliberately kept
// behind the pgl50h_ddr3_boundary module so the CPU adapters remain stable.

module pgl50h_mem_fabric #(
  parameter integer MEM_WORDS = 1024
) (
  input  wire        clk,
  input  wire        reset,

  input  wire        if_cmd_valid,
  output wire        if_cmd_ready,
  input  wire [31:0] if_cmd_address,
  output wire        if_rsp_valid,
  input  wire        if_rsp_ready,
  output wire [63:0] if_rsp_data,
  output wire        if_rsp_error,

  input  wire        d_read_cmd_valid,
  output wire        d_read_cmd_ready,
  input  wire  [0:0] d_read_cmd_id,
  input  wire [31:0] d_read_cmd_address,
  output wire        d_read_rsp_valid,
  input  wire        d_read_rsp_ready,
  output wire  [0:0] d_read_rsp_id,
  output wire [63:0] d_read_rsp_data,
  output wire        d_read_rsp_error,

  input  wire        d_write_cmd_valid,
  output wire        d_write_cmd_ready,
  input  wire        d_write_cmd_last,
  input  wire [31:0] d_write_cmd_address,
  input  wire [63:0] d_write_cmd_data,
  input  wire  [0:0] d_write_cmd_id,
  output wire        d_write_rsp_valid,
  input  wire        d_write_rsp_ready,
  output wire  [0:0] d_write_rsp_id,
  output wire        d_write_rsp_error
);

  reg [63:0] memory [0:MEM_WORDS-1];
  reg        if_rsp_valid_reg;
  reg [63:0] if_rsp_data_reg;
  reg        d_read_rsp_valid_reg;
  reg  [0:0] d_read_rsp_id_reg;
  reg [63:0] d_read_rsp_data_reg;
  reg        d_write_rsp_valid_reg;
  reg  [0:0] d_write_rsp_id_reg;
  integer i;

  function [63:0] read_word;
    input [31:0] address;
    integer word_index;
    begin
      word_index = (address - 32'h8000_0000) >> 3;
      if ((address >= 32'h8000_0000) && (word_index >= 0) && (word_index < MEM_WORDS))
        read_word = memory[word_index];
      else
        read_word = 64'h0000_0000_0000_0000;
    end
  endfunction

  task write_word;
    input [31:0] address;
    input [63:0] data;
    integer word_index;
    begin
      word_index = (address - 32'h8000_0000) >> 3;
      if ((address >= 32'h8000_0000) && (word_index >= 0) && (word_index < MEM_WORDS))
        memory[word_index] <= data;
    end
  endtask

  assign if_cmd_ready       = !if_rsp_valid_reg || if_rsp_ready;
  assign if_rsp_valid       = if_rsp_valid_reg;
  assign if_rsp_data        = if_rsp_data_reg;
  assign if_rsp_error       = 1'b0;

  assign d_read_cmd_ready  = !d_read_rsp_valid_reg || d_read_rsp_ready;
  assign d_read_rsp_valid  = d_read_rsp_valid_reg;
  assign d_read_rsp_id     = d_read_rsp_id_reg;
  assign d_read_rsp_data   = d_read_rsp_data_reg;
  assign d_read_rsp_error  = 1'b0;

  assign d_write_cmd_ready = !d_write_rsp_valid_reg || d_write_rsp_ready;
  assign d_write_rsp_valid = d_write_rsp_valid_reg;
  assign d_write_rsp_id    = d_write_rsp_id_reg;
  assign d_write_rsp_error = 1'b0;

  always @(posedge clk) begin
    if (reset) begin
      if_rsp_valid_reg       <= 1'b0;
      if_rsp_data_reg        <= 64'h0;
      d_read_rsp_valid_reg   <= 1'b0;
      d_read_rsp_id_reg      <= 1'b0;
      d_read_rsp_data_reg    <= 64'h0;
      d_write_rsp_valid_reg  <= 1'b0;
      d_write_rsp_id_reg     <= 1'b0;
      for (i = 0; i < MEM_WORDS; i = i + 1)
        memory[i] <= 64'h0;
    end else begin
      if (if_rsp_valid_reg && if_rsp_ready)
        if_rsp_valid_reg <= 1'b0;
      if (d_read_rsp_valid_reg && d_read_rsp_ready)
        d_read_rsp_valid_reg <= 1'b0;
      if (d_write_rsp_valid_reg && d_write_rsp_ready)
        d_write_rsp_valid_reg <= 1'b0;

      if (if_cmd_valid && if_cmd_ready) begin
        if_rsp_data_reg  <= read_word(if_cmd_address);
        if_rsp_valid_reg <= 1'b1;
      end

      if (d_read_cmd_valid && d_read_cmd_ready) begin
        d_read_rsp_id_reg    <= d_read_cmd_id;
        d_read_rsp_data_reg  <= read_word(d_read_cmd_address);
        d_read_rsp_valid_reg <= 1'b1;
      end

      if (d_write_cmd_valid && d_write_cmd_ready) begin
        write_word(d_write_cmd_address, d_write_cmd_data);
        d_write_rsp_id_reg     <= d_write_cmd_id;
        d_write_rsp_valid_reg  <= 1'b1;
      end
    end
  end

endmodule


