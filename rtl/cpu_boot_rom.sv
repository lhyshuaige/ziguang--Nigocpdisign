// Two independent, backpressured native cache-line refill ports.
// Each accepted request returns eight 64-bit words, in order. Only the
// 0x80000000..0x80007fff read window is selected by the enclosing mux.
module cpu_boot_rom #(
  parameter INIT_FILE = "firmware/build/boot64.hex"
) (
  input wire clk, reset,
  input wire i_cmd_valid, output wire i_cmd_ready, input wire [31:0] i_cmd_address,
  output wire i_rsp_valid, input wire i_rsp_ready, output wire [63:0] i_rsp_data,
  input wire d_cmd_valid, output wire d_cmd_ready, input wire [31:0] d_cmd_address,
  input wire d_cmd_id, output wire d_rsp_valid, input wire d_rsp_ready,
  output wire [63:0] d_rsp_data, output reg d_rsp_id
);
  (* ram_style = "block" *) reg [63:0] contents [0:4095];
  initial $readmemh(INIT_FILE,contents);
  reg [1:0] i_state,d_state;
  reg [11:0] i_address,d_address;
  reg [2:0] i_word,d_word;
  reg [63:0] i_data,d_data;
  // Separate synchronous read ports permit simultaneous instruction and
  // read-only data refills. Data/address hold while the CPU applies pressure.
  always @(posedge clk) begin
    if(i_state==1) i_data<=contents[i_address];
    if(d_state==1) d_data<=contents[d_address];
  end
  assign i_cmd_ready=(i_state==0);
  assign d_cmd_ready=(d_state==0);
  assign i_rsp_valid=(i_state==2);
  assign d_rsp_valid=(d_state==2);
  assign i_rsp_data=i_data;
  assign d_rsp_data=d_data;
  always @(posedge clk) begin
    if(reset) begin i_state<=0;d_state<=0;i_address<=0;d_address<=0;i_word<=0;d_word<=0;d_rsp_id<=0;end
    else begin
      case(i_state)
        0:if(i_cmd_valid) begin i_address<={i_cmd_address[14:6],3'b000};i_word<=0;i_state<=1;end
        1:i_state<=2;
        2:if(i_rsp_ready) begin
          if(i_word==7)i_state<=0;
          else begin i_word<=i_word+1'b1;i_address<=i_address+1'b1;i_state<=1;end
        end
      endcase
      case(d_state)
        0:if(d_cmd_valid) begin d_address<={d_cmd_address[14:6],3'b000};d_word<=0;d_rsp_id<=d_cmd_id;d_state<=1;end
        1:d_state<=2;
        2:if(d_rsp_ready) begin
          if(d_word==7)d_state<=0;
          else begin d_word<=d_word+1'b1;d_address<=d_address+1'b1;d_state<=1;end
        end
      endcase
    end
  end
endmodule
