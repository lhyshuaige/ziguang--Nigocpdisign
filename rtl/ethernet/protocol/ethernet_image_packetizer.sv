`timescale 1ns/1ps
`default_nettype none
// Existing Vision/DMA WORD32 pixel stream -> standard-MTU UDP packets.
// Input TLAST=EOL, TUSER=SOF. Output TLAST=packet end, TUSER=abort (always zero
// after validation). Frame size is provided by CPU, avoiding an RTL multiplier.
module ethernet_image_packetizer #(
 parameter integer CHUNK_BYTES=1400
)(
 input wire clk,reset,abort,input wire start_valid,output wire start_ready,
 input wire [15:0] image_width,image_height,input wire format_rgb565,
 input wire [31:0] frame_id,frame_bytes,timestamp,peer_ip,
 input wire [15:0] source_port,dest_port,
 input wire [31:0] s_tdata,input wire [3:0] s_tkeep,input wire s_tvalid,output wire s_tready,input wire s_tlast,s_tuser,
 output wire [79:0] m_desc,output wire m_desc_valid,input wire m_desc_ready,
 output wire [31:0] m_tdata,output wire [3:0] m_tkeep,output wire m_tvalid,input wire m_tready,output wire m_tlast,m_tuser,
 output reg frame_done,frame_error,output reg [31:0] packets_sent
);
 localparam integer WORDS=CHUNK_BYTES/4;
 localparam [2:0] IDLE=0,COLLECT=1,DESC=2,HEADER=3,BODY=4;
 reg [2:0] state;reg [15:0] width,height,x,y,chunk_size,body_remaining;
 reg rgb,first_pixel,last_chunk,abort_pending;reg [31:0] id,total,stamp,destination,offset,received;
 reg [15:0] src_port,dst_port;reg [1:0] pack_bytes;reg [31:0] pack;
 reg [31:0] memory[0:WORDS-1];reg [31:0] ram_q;reg [$clog2(WORDS)-1:0] wr_index,rd_index;
 reg [2:0] header_index;reg [31:0] header_word;
 wire [2:0] pixel_bytes=rgb?3'd2:3'd1;
 wire [31:0] packed_pixel=pack | ((rgb?{16'd0,s_tdata[15:0]}:{24'd0,s_tdata[7:0]}) << (pack_bytes*8));
 wire end_frame=x==width-1'b1 && y==height-1'b1;
 wire end_chunk=chunk_size+pixel_bytes==CHUNK_BYTES || end_frame;
 wire pixel_ok=(rgb?s_tkeep[1:0]==2'b11:s_tkeep[0]) && s_tlast==(x==width-1'b1) && s_tuser==first_pixel;
 wire write_word=state==COLLECT && s_tvalid && s_tready && pixel_ok && (pack_bytes+pixel_bytes==4 || end_chunk);
 wire read_word=(state==HEADER && m_tready && header_index==7) || (state==BODY && m_tready && !m_tlast);
 wire [$clog2(WORDS)-1:0] read_address=state==HEADER?0:rd_index+1'b1;
 always @(posedge clk)begin
  if(write_word)memory[wr_index]<=packed_pixel;
  if(read_word)ram_q<=memory[read_address];
 end
 function [31:0] lane_order;
  input [31:0] network_word;
  begin lane_order={network_word[7:0],network_word[15:8],network_word[23:16],network_word[31:24]};end
 endfunction
 always @* begin
  case(header_index)
   0:header_word=32'h4e475631; // NGV1
   1:header_word={8'd1,8'd1,7'd0,rgb,7'd0,last_chunk};
   2:header_word=id;3:header_word=offset;4:header_word=total;
   5:header_word={width,height};6:header_word={chunk_size,16'd0};7:header_word=stamp;
   default:header_word=0;
  endcase
 end
 assign start_ready=state==IDLE && !abort;assign s_tready=state==COLLECT && !abort;
 assign m_desc={chunk_size+16'd32,src_port,dst_port,destination};assign m_desc_valid=state==DESC;
 assign m_tvalid=state==HEADER || state==BODY;assign m_tdata=state==HEADER?lane_order(header_word):ram_q;
 assign m_tlast=state==BODY && body_remaining<=4;assign m_tuser=0;
 assign m_tkeep=state!=BODY || body_remaining>=4?4'hf:body_remaining==3?4'h7:body_remaining==2?4'h3:4'h1;
 // Preload while accepting the descriptor; chunk_size is stable through HEADER.
 // BODY-visible values and every external handshake retain their original cycles.
 wire a24_body_load=state==DESC && m_desc_ready;
 wire a24_body_step=state==BODY && m_tready && !m_tlast;
 always @(posedge clk)begin
  if(reset)body_remaining<=0;
  else if(a24_body_load)body_remaining<=chunk_size;
  else if(a24_body_step)body_remaining<=body_remaining-16'd4;
 end
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;width<=0;height<=0;x<=0;y<=0;chunk_size<=0;rgb<=0;first_pixel<=0;last_chunk<=0;abort_pending<=0;
   id<=0;total<=0;stamp<=0;destination<=0;offset<=0;received<=0;src_port<=0;dst_port<=0;pack_bytes<=0;pack<=0;
   wr_index<=0;rd_index<=0;header_index<=0;frame_done<=0;frame_error<=0;packets_sent<=0;
  end else begin
   frame_done<=0;frame_error<=0;
   if(abort && state!=IDLE)abort_pending<=1;
   case(state)
    IDLE:if(start_valid && !abort)begin
     if(image_width==0 || image_height==0 || frame_bytes==0)frame_error<=1;
     else begin
      width<=image_width;height<=image_height;rgb<=format_rgb565;id<=frame_id;total<=frame_bytes;stamp<=timestamp;destination<=peer_ip;
      src_port<=source_port;dst_port<=dest_port;offset<=0;received<=0;x<=0;y<=0;first_pixel<=1;chunk_size<=0;pack<=0;pack_bytes<=0;wr_index<=0;state<=COLLECT;abort_pending<=0;
     end
    end
    COLLECT:if(s_tvalid && s_tready)begin
     if(!pixel_ok || received+pixel_bytes>total || (end_frame && received+pixel_bytes!=total))begin state<=IDLE;frame_error<=1;end
     else begin
      first_pixel<=0;received<=received+pixel_bytes;chunk_size<=chunk_size+pixel_bytes;
      if(x==width-1'b1)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
      if(pack_bytes+pixel_bytes==4 || end_chunk)begin pack<=0;pack_bytes<=0;wr_index<=wr_index+1'b1;end
      else begin pack<=packed_pixel;pack_bytes<=pack_bytes+pixel_bytes;end
      if(end_chunk)begin state<=DESC;last_chunk<=end_frame;end
     end
    end
    DESC:if(m_desc_ready)begin state<=HEADER;header_index<=0;end
    HEADER:if(m_tready)begin
     if(header_index==7)begin state<=BODY;rd_index<=0;end else header_index<=header_index+1'b1;
    end
    BODY:if(m_tready)begin
     if(m_tlast)begin
      // During DESC/HEADER/BODY, received == offset + chunk_size.
      // Reuse the collected byte count; no extra offset carry chain or cycle.
      packets_sent<=packets_sent+1'b1;offset<=received;chunk_size<=0;wr_index<=0;
      if(abort_pending || abort)begin state<=IDLE;frame_error<=1;end
      else if(last_chunk)begin state<=IDLE;frame_done<=1;end else state<=COLLECT;
     end else begin rd_index<=rd_index+1'b1;end
    end
    default:state<=IDLE;
   endcase
   // Finish any already-visible UDP packet; discard only uncommitted image data.
   if(abort && state==COLLECT)begin state<=IDLE;frame_error<=1;end
  end
 end
endmodule
`default_nettype wire
