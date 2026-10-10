`timescale 1ns/1ps

module pgl50h_ddr_cdc_reset_tb;
  reg sys_clk = 1'b0;
  always #5 sys_clk = ~sys_clk;

  reg ddr_clk = 1'b0;
  always #7 ddr_clk = ~ddr_clk;

  reg soc_reset = 1'b0;
  reg ddr_init_done = 1'b1;
  wire ddr_cdc_reset;

  pgl50h_ddr_cdc_reset dut (
    .ddr_clk(ddr_clk),
    .async_reset(soc_reset | !ddr_init_done),
    .ddr_reset(ddr_cdc_reset)
  );

  task expect_reset;
    input expected;
    begin
      if (ddr_cdc_reset !== expected) begin
        $display("DDR_CDC_RESET_FAIL time=%0t expected=%b actual=%b", $time, expected, ddr_cdc_reset);
        $fatal(1);
      end
    end
  endtask

  task release_after_two_edges;
    begin
      #1 expect_reset(1'b1);
      @(posedge ddr_clk); #1 expect_reset(1'b1);
      @(posedge ddr_clk); #1 expect_reset(1'b0);
    end
  endtask

  initial begin
    // Assert between DDR edges, then release between edges.
    #2 soc_reset = 1'b1;
    #1 expect_reset(1'b1);
    @(negedge sys_clk) soc_reset = 1'b0;
    release_after_two_edges();

    // HMIC training loss must assert immediately and release locally.
    #2 ddr_init_done = 1'b0;
    #1 expect_reset(1'b1);
    #2 ddr_init_done = 1'b1;
    release_after_two_edges();

    // The system reset must still be independently able to assert it.
    @(negedge sys_clk) soc_reset = 1'b1;
    #1 expect_reset(1'b1);
    @(negedge sys_clk) soc_reset = 1'b0;
    release_after_two_edges();

    $display("DDR_CDC_RESET_PASS");
    $finish;
  end
endmodule
