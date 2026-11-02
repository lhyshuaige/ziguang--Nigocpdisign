// MES2L676-CORE-V1.2, independently verified on hardware 2026-11-01.
// P18 (CS0) -> R14/R15 (spi1_dq data); F25 (CS1) -> N16/N17 (spi0_dq).
// Port names retain the original P3 constraints; logical chips follow CS order.
// Both MOSI buses broadcast identical data; only the selected NOR drives MISO.
// GTP_CFGCLK uses dedicated H13; no ordinary SCK output is added.
module pg2l100h_flash_pads(
 input wire sck,input wire mosi,input wire [1:0] cs_n,
 output wire [1:0] miso,
 output wire [1:0] spi_cs_n,
 inout wire [3:0] spi0_dq,spi1_dq
);
 GTP_CFGCLK u_config_clock(.CLKIN(sck),.CE_N(1'b0));
 assign spi_cs_n=cs_n;
 assign spi0_dq={1'b1,1'b1,1'bz,mosi};
 assign spi1_dq={1'b1,1'b1,1'bz,mosi};
 assign miso={spi0_dq[1],spi1_dq[1]};
endmodule
