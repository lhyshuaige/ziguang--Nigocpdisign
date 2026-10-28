`timescale 1ns/1ps
`default_nettype none
// Descriptor and payload travel in ONE frame FIFO record. No parallel descriptor
// FIFO can lose alignment with a dropped/reset packet. Low byte lane goes first.
module ethernet_packet_record_tx #(
    parameter integer DATA_WIDTH=32, TIMEOUT_CYCLES=65536
)(
    input wire clk,reset,
    input wire [79:0] s_desc,input wire s_desc_valid,output wire s_desc_ready,
    input wire [DATA_WIDTH-1:0] s_data,input wire [DATA_WIDTH/8-1:0] s_keep,
    input wire s_valid,output wire s_ready,input wire s_last,s_bad,
    output wire [DATA_WIDTH-1:0] m_data,output wire [DATA_WIDTH/8-1:0] m_keep,
    output wire m_valid,input wire m_ready,output wire m_last,m_bad,
    output reg dropped
);
    localparam integer BYTES=DATA_WIDTH/8, HEAD_BEATS=12/BYTES;
    localparam [2:0] IDLE=0,HEADER=1,BODY=2,ABORT=3,DRAIN=4;
    reg [2:0] state;reg [95:0] header;reg [3:0] index;
    reg [15:0] remaining;reg [31:0] timer;reg bad_seen;
    integer k;reg [3:0] count;reg keep_ok,zero_seen;
    always @* begin
        count=0;keep_ok=1;zero_seen=0;
        for(k=0;k<BYTES;k=k+1)begin
            if(s_keep[k])begin count=count+1'b1;if(zero_seen)keep_ok=0;end
            else zero_seen=1;
        end
        if(count==0 || (!s_last && count!=BYTES))keep_ok=0;
    end
    wire length_end=count>=remaining;
    wire malformed=!keep_ok || s_bad || count>remaining || s_last!=length_end;
    assign s_desc_ready=state==IDLE;
    assign s_ready=state==DRAIN || (state==BODY && m_ready);
    assign m_valid=state==HEADER || state==ABORT || (state==BODY && s_valid);
    assign m_data=state==HEADER?header[index*DATA_WIDTH+:DATA_WIDTH]:state==BODY?s_data:0;
    assign m_keep=state==BODY?s_keep:{BYTES{1'b1}};
    assign m_last=state==ABORT || (state==BODY && (s_last || length_end));
    assign m_bad=state==ABORT || (state==BODY && (malformed || bad_seen));
    always @(posedge clk)begin
        if(reset)begin state<=IDLE;header<=0;index<=0;remaining<=0;timer<=0;dropped<=0;bad_seen<=0;end
        else begin
            dropped<=0;
            case(state)
                IDLE:if(s_desc_valid)begin
                    remaining<=s_desc[79:64];header<={16'he7a1,s_desc};index<=0;timer<=0;bad_seen<=0;
                    if(s_desc[79:64]==0 || s_desc[79:64]>1472)begin state<=DRAIN;dropped<=1;end
                    else state<=HEADER;
                end
                HEADER:if(m_ready)begin if(index==HEAD_BEATS-1)state<=BODY;else index<=index+1'b1;end
                BODY:begin
                    if(s_valid && m_ready)begin
                        timer<=0;remaining<=remaining-count;bad_seen<=bad_seen || malformed;
                        if(s_last || length_end)begin
                            state<=s_last?IDLE:DRAIN;
                            if(malformed || bad_seen)dropped<=1;
                        end
                    end else if(!s_valid)begin
                        if(timer==TIMEOUT_CYCLES-1)begin state<=ABORT;dropped<=1;end
                        else timer<=timer+1'b1;
                    end
                end
                ABORT:if(m_ready)state<=DRAIN;
                DRAIN:if(s_valid && s_last)state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule

module ethernet_packet_record_rx #(parameter integer DATA_WIDTH=32)(
    input wire clk,reset,
    input wire [DATA_WIDTH-1:0] s_data,input wire [DATA_WIDTH/8-1:0] s_keep,
    input wire s_valid,output wire s_ready,input wire s_last,s_bad,
    output wire [79:0] m_desc,output wire m_desc_valid,input wire m_desc_ready,
    output wire [DATA_WIDTH-1:0] m_data,output wire [DATA_WIDTH/8-1:0] m_keep,
    output wire m_valid,input wire m_ready,output wire m_last,m_bad
);
    localparam integer HEAD_BEATS=96/DATA_WIDTH;
    reg [1:0] state;reg [3:0] index;reg [95:0] header;
    assign s_ready=state==0 || state==3 || (state==2 && m_ready);
    assign m_desc=header[79:0];assign m_desc_valid=state==1;
    assign m_data=s_data;assign m_keep=s_keep;
    assign m_valid=state==2 && s_valid;assign m_last=s_last;assign m_bad=s_bad;
    always @(posedge clk)begin
        if(reset)begin state<=0;index<=0;header<=0;end
        else case(state)
            0:if(s_valid)begin
                header[index*DATA_WIDTH+:DATA_WIDTH]<=s_data;
                if(s_last)begin index<=0;state<=0;end
                else if(index==HEAD_BEATS-1)begin index<=0;state<=1;end
                else index<=index+1'b1;
            end
            1:if(header[95:80]!=16'he7a1)state<=3;else if(m_desc_ready)state<=2;
            2:if(s_valid && m_ready && s_last)state<=0;
            3:if(s_valid && s_last)state<=0;
            default:state<=0;
        endcase
    end
endmodule
`default_nettype wire
