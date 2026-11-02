// Original portable mode-0 SPI engine. All state uses clk; sck is an output only.
module spi_transfer # (parameter integer HALF_PERIOD=5) (
 input wire clk,reset,input wire start,input wire chip,
 input wire keep_cs,release_cs,
 input wire [6:0] bit_count,input wire [63:0] tx,
 input wire [1:0] miso,output reg [1:0] cs_n,
 output reg sck,output wire mosi,output reg busy,done,output reg [63:0] rx
);
 localparam CW=(HALF_PERIOD<2)?1:$clog2(HALF_PERIOD);
 localparam [CW-1:0] LAST_DIV=HALF_PERIOD-1;
 reg [CW-1:0] divider;
 reg [63:0] shift;
 reg [6:0] remaining;
 reg selected,hold_after;
 assign mosi=shift[63];
 always @(posedge clk) begin
  if(reset) begin
   cs_n<=2'b11;sck<=0;busy<=0;done<=0;rx<=0;shift<=0;
   divider<=0;remaining<=0;selected<=0;hold_after<=0;
  end else begin
   done<=0;
   if(!busy) begin
    sck<=0;
    if(release_cs)cs_n<=2'b11;
    if(start && bit_count!=0 && bit_count<=64) begin
     busy<=1;cs_n<=chip?2'b01:2'b10;selected<=chip;
     hold_after<=keep_cs;
     shift<=tx;remaining<=bit_count;rx<=0;divider<=0;
    end
   end else if(divider==LAST_DIV) begin
    divider<=0;
    if(remaining==0) begin busy<=0;done<=1;if(!hold_after)cs_n<=2'b11;end
    else if(!sck) begin sck<=1;rx<={rx[62:0],miso[selected]};end
    else begin
     sck<=0;shift<={shift[62:0],1'b0};
     remaining<=remaining-1'b1;
    end
   end else divider<=divider+1'b1;
  end
 end
endmodule
