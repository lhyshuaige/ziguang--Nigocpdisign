`timescale 1ns/1ps
`default_nettype none
// Supplemental validation: upstream verifies IPv4 header/FCS but not UDP RX
// checksum. Commit into a frame FIFO only after length/checksum validation.
module ethernet_udp_rx_guard(
    input wire clk,reset,input wire [31:0] local_ip,input wire [47:0] local_mac,
    input wire hdr_valid,output wire hdr_ready,
    input wire [47:0] dest_mac,input wire [3:0] version,ihl,
    input wire [2:0] flags,input wire [12:0] fragment_offset,
    input wire [31:0] source_ip,dest_ip,
    input wire [15:0] ip_length,source_port,dest_port,udp_length,checksum,
    input wire [7:0] s_data,input wire s_valid,output wire s_ready,input wire s_last,s_bad,
    output wire [79:0] m_desc,output wire m_desc_valid,input wire m_desc_ready,
    output wire [7:0] m_data,output wire m_valid,input wire m_ready,output wire m_last,m_bad,
    output reg rejected
);
    reg [1:0] state;reg [79:0] desc;
    reg [31:0] sum;reg [15:0] count,expected;reg [7:0] high_byte;
    reg use_checksum,bad_seen;
    wire header_ok=dest_mac==local_mac && dest_ip==local_ip && version==4 && ihl==5 &&
        !flags[0] && !flags[2] && fragment_offset==0 && udp_length>=9 && udp_length<=1480 && ip_length==udp_length+16'd20;
    wire [31:0] with_byte=sum+(count[0]?{24'd0,s_data}:{16'd0,s_data,8'd0});
    wire [16:0] fold1={1'b0,with_byte[15:0]}+{1'b0,with_byte[31:16]};
    wire [16:0] fold2={1'b0,fold1[15:0]}+fold1[16];
    wire checksum_ok=!use_checksum || fold2[15:0]==16'hffff;
    assign hdr_ready=state==0;
    assign m_desc=desc;assign m_desc_valid=state==1;
    assign m_data=s_data;assign m_valid=state==2 && s_valid;
    assign m_last=s_last;assign m_bad=s_bad || bad_seen || (s_last && (count+16'd1!=expected || !checksum_ok));
    assign s_ready=state==3 || (state==2 && m_ready);
    always @(posedge clk)begin
        if(reset)begin state<=0;desc<=0;sum<=0;count<=0;expected<=0;high_byte<=0;use_checksum<=0;bad_seen<=0;rejected<=0;end
        else begin
            rejected<=0;
            case(state)
                0:if(hdr_valid)begin
                    desc<={udp_length-16'd8,source_port,dest_port,source_ip};expected<=udp_length-16'd8;count<=0;bad_seen<=0;
                    sum<={16'd0,source_ip[31:16]}+{16'd0,source_ip[15:0]}+{16'd0,dest_ip[31:16]}+{16'd0,dest_ip[15:0]}+
                         32'd17+{16'd0,udp_length}+{16'd0,source_port}+{16'd0,dest_port}+{16'd0,udp_length}+{16'd0,checksum};
                    use_checksum<=checksum!=0;
                    if(header_ok)state<=1;else begin state<=3;rejected<=1;end
                end
                1:if(m_desc_ready)state<=2;
                2:if(s_valid && s_ready)begin
                    sum<=with_byte;count<=count+1'b1;bad_seen<=bad_seen || s_bad;
                    if(s_last)begin if(m_bad)rejected<=1;state<=0;end
                end
                3:if(s_valid && s_last)state<=0;
                default:state<=0;
            endcase
        end
    end
endmodule
`default_nettype wire
