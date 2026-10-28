`timescale 1ns/1ps

// One-entry elastic AXI4-Stream register.  It deliberately has no bypass
// path, so a pipeline can be built without a combinational ready chain.
module vision_stream_adapter #(
  parameter integer DATA_WIDTH = 32,
  parameter integer USER_WIDTH = 1
) (
  input  wire                    clk,
  input  wire                    reset,
  input  wire [DATA_WIDTH-1:0]   s_tdata,
  input  wire [DATA_WIDTH/8-1:0] s_tkeep,
  input  wire [USER_WIDTH-1:0]   s_tuser,
  input  wire                    s_tlast,
  input  wire                    s_tvalid,
  output wire                    s_tready,
  output wire [DATA_WIDTH-1:0]   m_tdata,
  output wire [DATA_WIDTH/8-1:0] m_tkeep,
  output wire [USER_WIDTH-1:0]   m_tuser,
  output wire                    m_tlast,
  output wire                    m_tvalid,
  input  wire                    m_tready
);
  reg [DATA_WIDTH-1:0] data_q;
  reg [DATA_WIDTH/8-1:0] keep_q;
  reg [USER_WIDTH-1:0] user_q;
  reg last_q;
  reg valid_q;

  assign s_tready = !valid_q || m_tready;
  assign m_tdata  = data_q;
  assign m_tkeep  = keep_q;
  assign m_tuser  = user_q;
  assign m_tlast  = last_q;
  assign m_tvalid = valid_q;

  always @(posedge clk) begin
    if (reset) begin
      data_q  <= {DATA_WIDTH{1'b0}};
      keep_q  <= {(DATA_WIDTH/8){1'b0}};
      user_q  <= {USER_WIDTH{1'b0}};
      last_q  <= 1'b0;
      valid_q <= 1'b0;
    end else begin
      if (s_tready) begin
        valid_q <= s_tvalid;
        if (s_tvalid) begin
          data_q <= s_tdata;
          keep_q <= s_tkeep;
          user_q <= s_tuser;
          last_q <= s_tlast;
        end
      end
    end
  end
endmodule
