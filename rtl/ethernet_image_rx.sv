`timescale 1ns/1ps
`default_nettype none
// One complete UDP payload is quarantined before exposing its image header.
// NGV1 header: network byte order; image body: little-endian RGB565/Gray8.
module ethernet_image_rx #(parameter MAX_BODY=1400)(
 input wire clk,reset,flush,
 input wire [79:0] s_desc,input wire s_desc_valid,output wire s_desc_ready,
 input wire [31:0] s_data,input wire [3:0] s_keep,input wire s_valid,
 output wire s_ready,input wire s_last,s_bad,
 output wire header_valid,input wire header_ready,
 output wire [31:0] frame_id,offset,total,peer_ip,
 output wire [15:0] width,height,chunk_bytes,
 output wire rgb565,last_chunk,
 output wire [31:0] m_data,output wire [3:0] m_keep,
 output wire m_valid,input wire m_ready,output wire m_last,
 output reg rejected,output wire idle
);
 localparam WORDS=(MAX_BODY+35)/4;
 localparam ADDR_W=$clog2(WORDS);
 localparam [ADDR_W:0] WORD_LIMIT=WORDS;
 localparam [ADDR_W-1:0] FINAL_WORD=WORDS-1,FIRST_BODY=8;
 localparam RXD=0,RXB=1,CHECK=2,HDR=3,PRIME=4,BODY=5,DRAIN=6;
 reg [2:0] state;reg [31:0] mem[0:WORDS-1];
 reg [31:0] h[0:7],q;reg [15:0] expected,count,body_left;
 reg [ADDR_W-1:0] wr,rd;reg bad;reg [31:0] ip;
 function automatic [31:0] be(input [31:0] x);be={x[7:0],x[15:8],x[23:16],x[31:24]};endfunction
 wire [2:0] n=s_keep==15?4:s_keep==7?3:s_keep==3?2:s_keep==1?1:0;
 wire [15:0] count_next=count+{13'd0,n};
 wire malformed=n==0 || (!s_last && n!=4) || count_next>expected || (s_last && count_next!=expected);
 assign s_desc_ready=state==RXD;assign s_ready=state==RXB || state==DRAIN;
 assign header_valid=state==HDR;assign idle=state==RXD;
 assign frame_id=h[2];assign offset=h[3];assign total=h[4];assign peer_ip=ip;
 assign width=h[5][31:16];assign height=h[5][15:0];assign chunk_bytes=h[6][31:16];
 assign rgb565=h[1][8];assign last_chunk=h[1][0];
 assign m_valid=state==BODY;assign m_data=q;assign m_last=body_left<=4;
 assign m_keep=body_left>=4?15:body_left==3?7:body_left==2?3:1;
 always @(posedge clk)begin
  if(state==RXB && s_valid && s_ready && {1'b0,wr}<WORD_LIMIT)mem[wr]<=s_data;
  if(state==PRIME || (state==BODY && m_ready && !m_last))q<=mem[state==PRIME?FIRST_BODY:rd+1'b1];
 end
 integer i;
 always @(posedge clk)begin
  if(reset || flush)begin
   state<=RXD;expected<=0;count<=0;body_left<=0;wr<=0;rd<=0;bad<=0;ip<=0;rejected<=0;
   for(i=0;i<8;i=i+1)h[i]<=0;
  end else begin
   rejected<=0;
   case(state)
    RXD:if(s_desc_valid)begin
     expected<=s_desc[79:64];ip<=s_desc[31:0];count<=0;wr<=0;bad<=0;
     if(s_desc[79:64]<33 || s_desc[79:64]>MAX_BODY+32)begin state<=DRAIN;rejected<=1;end else state<=RXB;
    end
    RXB:if(s_valid)begin
     if(wr<8)h[wr[2:0]]<=be(s_data);
     count<=count_next;bad<=bad || s_bad || malformed;wr<=wr+1'b1;
     if(s_last)state<=CHECK;
     else if(count_next>=expected || wr==FINAL_WORD)begin state<=DRAIN;rejected<=1;end
    end
    CHECK:begin
     if(bad || h[0]!=32'h4e475631 || (h[1]&32'hfffffefe)!=32'h01010000 ||
        h[6][15:0]!=0 || chunk_bytes==0 || chunk_bytes>MAX_BODY ||
        expected!=chunk_bytes+32 || width==0 || height==0 || total==0 ||
        (rgb565 && (chunk_bytes[0] || offset[0] || total[0])))begin state<=RXD;rejected<=1;end
     else state<=HDR;
    end
    HDR:if(header_ready)begin body_left<=chunk_bytes;rd<=8;state<=PRIME;end
    PRIME:state<=BODY;
    BODY:if(m_ready)begin
     if(m_last)state<=RXD;else begin body_left<=body_left-4;rd<=rd+1'b1;end
    end
    DRAIN:if(s_valid && s_last)state<=RXD;
    default:state<=RXD;
   endcase
  end
 end
endmodule
`default_nettype wire
