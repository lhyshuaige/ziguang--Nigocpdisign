`timescale 1ns/1ps

module NaxVendorGrs;
  wire GRSNET = 1'b1;
endmodule

// Mirrors the candidate's primitive configuration so the vendor model, not
// the behavioral fallback used by SoC CoreMark, is exercised here.
module NaxApmSignedMul18Reg (
  input wire clk, input wire ce,
  input wire [17:0] x, input wire [17:0] y,
  output wire [47:0] p
);
  GTP_APM_E1 #(
    .GRS_EN("FALSE"), .ASYNC_RST(1'b0),
    .X_SIGNED(1), .Y_SIGNED(1),
    .USE_PREADD(0), .USE_POSTADD(0),
    .X_REG(0), .Y_REG(0), .Z_REG(0),
    .PREADD_REG(0), .MULT_REG(1), .P_REG(0),
    .MODEX_REG(0), .MODEY_REG(0), .MODEZ_REG(0),
    .CXO_REG(0), .CPO_REG(0), .USE_SIMD(0),
    .X_SEL(0), .XB_SEL(0), .USE_ACCLOW(0), .CIN_SEL(0),
    .Z_INIT(48'd0)
  ) u_apm (
    .P(p), .CPO(), .COUT(), .CXO(), .CXBO(),
    .X(x), .Y(y), .Z(48'd0), .CXI(18'd0), .CXBI(18'd0),
    .CPI(48'd0), .CIN(1'b0), .MODEX(1'b0),
    .MODEY(3'b000), .MODEZ(4'b0000),
    .CLK(clk), .RSTM(1'b0), .CEM(ce),
    .RSTX(1'b0), .RSTY(1'b0), .RSTZ(1'b0),
    .RSTP(1'b0), .RSTPRE(1'b0),
    .RSTMODEX(1'b0), .RSTMODEY(1'b0), .RSTMODEZ(1'b0),
    .CEX(1'b0), .CEY(1'b0), .CEZ(1'b0), .CEP(1'b0),
    .CEPRE(1'b0), .CEMODEX(1'b0), .CEMODEY(1'b0), .CEMODEZ(1'b0)
  );
endmodule

module nax_apm_mreg_vendor_tb;
  NaxVendorGrs GRS_INST();
  reg clk = 1'b0;
  reg ce = 1'b0;
  reg signed [17:0] x = 0;
  reg signed [17:0] y = 0;
  wire [47:0] p;
  reg signed [47:0] expected = 0;
  integer i;

  always #5 clk = ~clk;
  NaxApmSignedMul18Reg dut(.clk(clk), .ce(ce), .x(x), .y(y), .p(p));

  initial begin
    for (i = 0; i < 500; i = i + 1) begin
      @(negedge clk);
      x = $random;
      y = $random;
      ce = ($random & 3) != 0;
      @(posedge clk);
      if (ce) expected = x * y;
      #1;
      if (p !== expected) $fatal(1, "APM MREG mismatch i=%0d got=%h expected=%h", i, p, expected);
    end
    $display("APM_MREG_VENDOR_PASS trials=%0d", i);
    $finish;
  end
endmodule
