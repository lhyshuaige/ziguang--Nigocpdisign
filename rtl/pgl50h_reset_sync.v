// Reset-domain helpers for the PGL50H SoC.
//
// The HMIC reset input is allowed to assert asynchronously, but its release
// is deliberately registered in the 50 MHz reference domain.  APB/user
// logic uses the synchronous-release variant so that a raw board reset is not
// fanned directly into reset pins clocked by ddrphy_clkin.

module pgl50h_reset_sync #(
  parameter integer STAGES = 2
) (
  input  wire clk,
  input  wire reset_n,
  output wire reset_n_sync
);
  (* ASYNC_REG = "TRUE", syn_preserve = 1, syn_keep = 1 *)
  reg [STAGES-1:0] sync_ff;

  initial sync_ff = {STAGES{1'b0}};

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      sync_ff <= {STAGES{1'b0}};
    else if (STAGES == 1)
      sync_ff <= {STAGES{1'b1}};
    else
      sync_ff <= {sync_ff[STAGES-2:0], 1'b1};
  end

  assign reset_n_sync = sync_ff[STAGES-1];
endmodule

// Synchronous reset-release helper.  This is intended for a control/APB
// island whose clock is already running.  There is intentionally no
// asynchronous reset pin, avoiding a board-reset removal path into that
// clock domain.  Assertion takes effect on the next active clock edge.
module pgl50h_sync_release #(
  parameter integer STAGES = 2
) (
  input  wire clk,
  input  wire release_n,
  output wire reset_n_sync
);
  (* syn_preserve = 1, syn_keep = 1 *)
  reg [STAGES-1:0] sync_ff;

  initial sync_ff = {STAGES{1'b0}};

  always @(posedge clk) begin
    if (!release_n)
      sync_ff <= {STAGES{1'b0}};
    else if (STAGES == 1)
      sync_ff <= {STAGES{1'b1}};
    else
      sync_ff <= {sync_ff[STAGES-2:0], 1'b1};
  end

  assign reset_n_sync = sync_ff[STAGES-1];
endmodule
