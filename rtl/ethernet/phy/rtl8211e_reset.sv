`timescale 1ns/1ps
`default_nettype none
// RTL8211E datasheet rev 1.6, section 7.16: >=10 ms low, then 30 ms settle.
// clk is a local management clock, never the PHY receive clock.
module rtl8211e_reset #(
    parameter integer RESET_CYCLES = 1000000,
    parameter integer SETTLE_CYCLES = 3000000
)(
    input wire clk,
    input wire reset,
    input wire clocks_ready,
    input wire restart,
    output wire phy_reset_n,
    output wire management_ready
);
    localparam integer LIMIT = RESET_CYCLES > SETTLE_CYCLES ? RESET_CYCLES : SETTLE_CYCLES;
    localparam integer CW = LIMIT > 1 ? $clog2(LIMIT) : 1;
    localparam [CW-1:0] RESET_LAST=RESET_CYCLES-1,SETTLE_LAST=SETTLE_CYCLES-1;
    localparam [1:0] HOLD_RESET=0, SETTLING=1, READY=2;
    reg [1:0] state;
    reg [CW-1:0] count;

    assign phy_reset_n = !reset && clocks_ready && (state != HOLD_RESET);
    assign management_ready = phy_reset_n && (state == READY) && !restart;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= HOLD_RESET;
            count <= 0;
        end else if (!clocks_ready || restart) begin
            state <= HOLD_RESET;
            count <= 0;
        end else begin
            case (state)
                HOLD_RESET: if (count == RESET_LAST) begin
                    state <= SETTLING;
                    count <= 0;
                end else count <= count + 1'b1;
                SETTLING: if (count == SETTLE_LAST) begin
                    state <= READY;
                    count <= 0;
                end else count <= count + 1'b1;
                READY: count <= 0;
                default: begin state <= HOLD_RESET; count <= 0; end
            endcase
        end
    end
endmodule
`default_nettype wire
