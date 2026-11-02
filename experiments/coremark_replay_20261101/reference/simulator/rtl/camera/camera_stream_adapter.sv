`timescale 1ns/1ps

// Registered camera FIFO to AXI4-Stream adapter.  The output register is the
// AXI stability boundary: tdata/tkeep/tuser/tlast remain unchanged while a
// consumer holds tready low.
module camera_stream_adapter #(
  parameter integer DATA_WIDTH = 32
) (
  input  wire                   clk,
  input  wire                   reset,
  input  wire [DATA_WIDTH-1:0]  s_data,
  input  wire [DATA_WIDTH/8-1:0] s_keep,
  input  wire                   s_sof,
  input  wire                   s_eol,
  input  wire                   s_valid,
  output wire                   s_ready,
  output wire [DATA_WIDTH-1:0]  m_tdata,
  output wire [DATA_WIDTH/8-1:0] m_tkeep,
  output wire                   m_tuser,
  output wire                   m_tlast,
  output wire                   m_tvalid,
  input  wire                   m_tready
);
  reg [DATA_WIDTH-1:0] data_q;
  reg [DATA_WIDTH/8-1:0] keep_q;
  reg sof_q, eol_q, valid_q;
  assign s_ready = !valid_q || m_tready;
  assign m_tdata = data_q;
  assign m_tkeep = keep_q;
  assign m_tuser = sof_q;
  assign m_tlast = eol_q;
  assign m_tvalid = valid_q;

  always @(posedge clk) begin
    if (reset) begin
      data_q <= 0; keep_q <= 0; sof_q <= 0; eol_q <= 0; valid_q <= 0;
    end else if (s_ready) begin
      valid_q <= s_valid;
      if (s_valid) begin
        data_q <= s_data; keep_q <= s_keep; sof_q <= s_sof; eol_q <= s_eol;
      end
    end
  end
endmodule
