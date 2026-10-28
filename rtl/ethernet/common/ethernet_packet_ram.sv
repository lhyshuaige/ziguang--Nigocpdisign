`timescale 1ns/1ps
`default_nettype none
// One write port and one synchronous read port, independent clocks. Keep RAM
// storage separate from FIFO pointer/reset/control processes for PDS inference.
// No RAM clear/reset: the existing frame FIFO owns validity and commit pointers.
// A read has exactly ONE clock latency and holds its output when read_enable=0.
module ethernet_packet_ram #(
    parameter integer DATA_WIDTH=38,ADDR_WIDTH=10
)(
    input wire write_clk,write_enable,
    input wire [ADDR_WIDTH-1:0] write_address,
    input wire [DATA_WIDTH-1:0] write_data,
    input wire read_clk,read_enable,
    input wire [ADDR_WIDTH-1:0] read_address,
    output reg [DATA_WIDTH-1:0] read_data
);
    (* syn_ramstyle="block_ram", ram_style="block" *)
    reg [DATA_WIDTH-1:0] memory[0:(1<<ADDR_WIDTH)-1];
    always @(posedge write_clk)if(write_enable)memory[write_address]<=write_data;
    always @(posedge read_clk)if(read_enable)read_data<=memory[read_address];
endmodule
`default_nettype wire
