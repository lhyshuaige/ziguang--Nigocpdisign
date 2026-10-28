`timescale 1ns/1ps
`default_nettype none
// RTL8211F only. Page transactions are exclusive; no address-0 discovery.
// All requests and responses use the management clock and one MDIO engine.
module rtl8211f_probe #(
    parameter integer POLL_CYCLES=1000000,RESCAN_CYCLES=10000000
)(
    input wire clk,reset,management_ready,
    output wire cmd_valid,input wire cmd_ready,output wire cmd_read,
    output wire [4:0] cmd_phy_addr,cmd_reg_addr,
    output wire [15:0] cmd_wdata,
    input wire rsp_valid,output wire rsp_ready,
    input wire [15:0] rsp_rdata,input wire [1:0] rsp_error,
    output reg phy_found,output reg [4:0] phy_addr,
    output reg [31:0] phy_id,output reg [15:0] phy_status,bmsr,
    output wire link_up,full_duplex,autoneg_complete,gigabit_ready,
    output wire [1:0] speed,output reg [1:0] last_error,
    output reg [31:0] error_count,scan_rounds
);
    localparam [5:0] I1C=0,I1R=1,I2C=2,I2R=3,PSC=4,PSR=5,PVC=6,PVR=7,
                     STC=8,STR=9,BSC=10,BSR=11,PRC=12,PRR=13,RVC=14,RVR=15,WAIT_POLL=16,WAIT_SCAN=17,
                     DPC=18,DPR=19,DVC=20,DVR=21,TXRC=22,TXRR=23,TXWC=24,TXWR=25,
                     TXVC=26,TXVR=27,RXRC=28,RXRR=29,RXWC=30,RXWR=31,RXVC=32,RXVR=33;
    localparam integer MAX_COUNT=POLL_CYCLES>RESCAN_CYCLES?POLL_CYCLES:RESCAN_CYCLES;
    localparam integer CW=MAX_COUNT>1?$clog2(MAX_COUNT):1;
    localparam [CW-1:0] POLL_LAST=POLL_CYCLES-1,RESCAN_LAST=RESCAN_CYCLES-1;
    reg [5:0] state;
    reg [4:0] address;
    reg [CW-1:0] timer;
    reg [15:0] pending_status,pending_bmsr;
    reg failed,delay_configured;
    reg [15:0] delay_word;
    wire command_state=(state<=RVC || (state>=DPC && state<=RXVC)) && !state[0];
    wire response_state=(state<=RVR || (state>=DPC && state<=RXVR)) && state[0];
    assign cmd_valid=management_ready && !reset && command_state;
    assign cmd_read=state!=PSC && state!=PRC && state!=DPC && state!=TXWC && state!=RXWC;
    assign cmd_phy_addr=address;
    assign cmd_reg_addr=state==I1C?5'd2:state==I2C?5'd3:state==STC?5'd26:state==BSC?5'd1:
                        (state==TXRC || state==TXWC || state==TXVC)?5'd17:
                        (state==RXRC || state==RXWC || state==RXVC)?5'd21:5'd31;
    assign cmd_wdata=state==PSC?16'h0a43:state==PRC?16'h0a42:state==DPC?16'h0d08:delay_word;
    assign rsp_ready=management_ready && response_state;
    assign speed=phy_status[5:4];
    assign link_up=phy_found && phy_status[2];
    assign full_duplex=phy_found && phy_status[3];
    assign autoneg_complete=phy_found && bmsr[5];
    assign gigabit_ready=!reset && management_ready && delay_configured && link_up && full_duplex && autoneg_complete && speed==2;
    task automatic advance_address;
        begin
            if(address==31)begin address<=1;timer<=0;state<=WAIT_SCAN;scan_rounds<=scan_rounds+1'b1;end
            else begin address<=address+1'b1;state<=I1C;end
        end
    endtask
    task automatic fail_poll(input [1:0] code);
        begin
            failed<=1;last_error<=code;error_count<=error_count+1'b1;
            phy_found<=0;phy_status<=0;bmsr<=0;delay_configured<=0;state<=PRC;
        end
    endtask
    always @(posedge clk)begin
        if(reset || !management_ready)begin
            state<=I1C;address<=1;timer<=0;failed<=0;pending_status<=0;pending_bmsr<=0;delay_configured<=0;delay_word<=0;
            phy_found<=0;phy_addr<=0;phy_id<=0;phy_status<=0;bmsr<=0;
            last_error<=0;error_count<=0;scan_rounds<=0;
        end else if(command_state)begin
            if(cmd_ready)state<=state+1'b1;
        end else case(state)
            I1R:if(rsp_valid)begin
                if(rsp_error!=0)begin last_error<=rsp_error;error_count<=error_count+1'b1;advance_address();end
                else if(rsp_rdata==16'h001c)state<=I2C;
                else advance_address();
            end
            I2R:if(rsp_valid)begin
                if(rsp_error!=0)begin last_error<=rsp_error;error_count<=error_count+1'b1;advance_address();end
                else begin
                    phy_id<={16'h001c,rsp_rdata};
                    // E/F share model bits; revision 5 must not select this F register map.
                    if(rsp_rdata==16'hc916)begin phy_found<=1;phy_addr<=address;failed<=0;state<=DPC;end
                    else advance_address();
                end
            end
            // RTL8211F RGMII-ID: page D08, TX reg11 bit8, RX reg15 bit3.
            // Read-modify-write and verify: preserve straps and unrelated fields.
            DPR:if(rsp_valid)begin if(rsp_error!=0)fail_poll(rsp_error);else state<=DVC;end
            DVR:if(rsp_valid)begin if(rsp_error!=0 || rsp_rdata!=16'h0d08)fail_poll(rsp_error!=0?rsp_error:2'd3);else state<=TXRC;end
            TXRR:if(rsp_valid)begin if(rsp_error!=0)fail_poll(rsp_error);else begin delay_word<=rsp_rdata|16'h0100;state<=TXWC;end end
            TXWR:if(rsp_valid)begin if(rsp_error!=0)fail_poll(rsp_error);else state<=TXVC;end
            TXVR:if(rsp_valid)begin if(rsp_error!=0 || rsp_rdata!=delay_word)fail_poll(rsp_error!=0?rsp_error:2'd3);else state<=RXRC;end
            RXRR:if(rsp_valid)begin if(rsp_error!=0)fail_poll(rsp_error);else begin delay_word<=rsp_rdata|16'h0008;state<=RXWC;end end
            RXWR:if(rsp_valid)begin if(rsp_error!=0)fail_poll(rsp_error);else state<=RXVC;end
            RXVR:if(rsp_valid)begin if(rsp_error!=0 || rsp_rdata!=delay_word)fail_poll(rsp_error!=0?rsp_error:2'd3);else begin delay_configured<=1;state<=PSC;end end
            PSR:if(rsp_valid)begin if(rsp_error!=0)fail_poll(rsp_error);else state<=PVC;end
            PVR:if(rsp_valid)begin
                if(rsp_error!=0)fail_poll(rsp_error);
                else if(rsp_rdata!=16'h0a43)fail_poll(2'd3);
                else state<=STC;
            end
            STR:if(rsp_valid)begin if(rsp_error!=0)fail_poll(rsp_error);else begin pending_status<=rsp_rdata;state<=BSC;end end
            BSR:if(rsp_valid)begin if(rsp_error!=0)fail_poll(rsp_error);else begin pending_bmsr<=rsp_rdata;state<=PRC;end end
            PRR:if(rsp_valid)begin
                if(rsp_error!=0)begin
                    phy_found<=0;phy_status<=0;bmsr<=0;last_error<=rsp_error;error_count<=error_count+1'b1;
                    address<=1;timer<=0;state<=WAIT_SCAN;
                end else state<=RVC;
            end
            RVR:if(rsp_valid)begin
                timer<=0;
                if(rsp_error!=0 || rsp_rdata!=16'h0a42 || failed)begin
                    phy_found<=0;phy_status<=0;bmsr<=0;address<=1;state<=WAIT_SCAN;
                    if(rsp_error!=0 || rsp_rdata!=16'h0a42)begin
                        last_error<=rsp_error!=0?rsp_error:2'd3;error_count<=error_count+1'b1;
                    end
                end else begin phy_status<=pending_status;bmsr<=pending_bmsr;last_error<=0;state<=WAIT_POLL;end
            end
            WAIT_POLL:if(timer==POLL_LAST)begin timer<=0;failed<=0;state<=PSC;end else timer<=timer+1'b1;
            WAIT_SCAN:if(timer==RESCAN_LAST)begin timer<=0;failed<=0;state<=I1C;end else timer<=timer+1'b1;
            default:begin state<=I1C;address<=1;phy_found<=0;phy_status<=0;bmsr<=0;timer<=0;end
        endcase
    end
endmodule
`default_nettype wire
