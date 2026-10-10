// PDS board implementation of the clock/reset boundary.
//
// The RTL/simulation boundary intentionally has a primitive-free fallback in
// pgl50h_clock_reset.v.  This variant is selected only by the PDS project and
// binds the already-generated 50 MHz -> 100 MHz Logos PLL.  Keeping the
// binding in a separate source file avoids requiring a global preprocessor
// define (and makes the generated-IP dependency explicit in the project
// manifest).

module pgl50h_clock_reset #(
  parameter integer RESET_SYNC_STAGES = 2
) (
  input  wire clk_50m,
  input  wire reset_ext_n,
  input  wire ddr_init_done,
  input  wire clk_sys_ext,
  input  wire ext_pll_locked,
  input  wire use_external_clk,
  output wire clk_sys,
  output wire pll_locked,
  output wire soc_reset,
  output wire soc_reset_n
);

  wire pll_clk;
  wire pll_lock;

  pgl50h_pds_pll_wrapper u_pgl50h_pll (
    .clk_in (clk_50m),
    .reset_n(reset_ext_n),
    .clk_out(pll_clk),
    .locked (pll_lock)
  );

  // A real DDR build may use the HMIC user clock.  The standalone PDS
  // implementation uses the generated 100 MHz PLL unless that external
  // clock is explicitly selected by the top-level DDR configuration.
  wire selected_clk = use_external_clk ? clk_sys_ext : pll_clk;
  wire selected_lock = use_external_clk ? (pll_lock & ext_pll_locked) : pll_lock;
  assign clk_sys    = selected_clk;
  assign pll_locked = selected_lock;

  reg [RESET_SYNC_STAGES-1:0] reset_pipe;

  // Asynchronous assertion, synchronous release.  DDR init_done is sampled
  // in the selected system-clock domain and therefore keeps the CPU quiescent
  // until the generated HMIC PHY has completed training.
  always @(posedge clk_sys or negedge reset_ext_n) begin
    if (!reset_ext_n) begin
      reset_pipe <= {RESET_SYNC_STAGES{1'b0}};
    end else if (!selected_lock || !ddr_init_done) begin
      reset_pipe <= {RESET_SYNC_STAGES{1'b0}};
    end else begin
      reset_pipe <= {reset_pipe[RESET_SYNC_STAGES-2:0], 1'b1};
    end
  end

  assign soc_reset_n = reset_pipe[RESET_SYNC_STAGES-1];
  assign soc_reset   = !soc_reset_n;

endmodule
