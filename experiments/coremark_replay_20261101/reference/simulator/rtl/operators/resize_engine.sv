`timescale 1ns/1ps

// Streaming nearest-neighbor resize stage.  Frame dimensions are snapshotted
// at enable time and the phase accumulators are local to the stream.  A single
// write-per-cycle line store is intentional: it maps cleanly to PGL50H DRM.
// Horizontal replication is serialized through ST_HWRITE, which adds source
// backpressure for expansion but keeps one-port RAM inference deterministic.
module vision_resize_nn #(
  parameter integer MAX_WIDTH = 2048,
  parameter integer MAX_REPEAT = 8
) (
  input wire clk, input wire reset, input wire enable,
  input wire [31:0] src_width, input wire [31:0] src_height,
  input wire [31:0] dst_width, input wire [31:0] dst_height,
  input wire [31:0] s_tdata, input wire s_tvalid, output wire s_tready,
  input wire s_tlast, input wire s_tuser,
  output wire [31:0] m_tdata, output wire m_tvalid, input wire m_tready,
  output wire m_tlast, output wire m_tuser, output reg config_error
);
  localparam integer BANK_DEPTH = MAX_WIDTH;
  localparam [2:0] ST_IDLE=3'd0, ST_READ=3'd1, ST_HWRITE=3'd2,
                   ST_WRITE=3'd3, ST_BYPASS=3'd4, ST_PREP=3'd5;
  reg [2:0] state;
  reg [31:0] src_width_q, src_height_q, dst_width_q, dst_height_q;
  reg [31:0] source_x, write_count, read_count;
  reg [31:0] h_phase, h_repeat_current, v_phase, replay_remaining;
  reg [31:0] pending_data, pending_index, pending_repeat, pending_write_end;
  reg [31:0] pending_v_repeat, pending_v_phase_next;
  reg pending_last;
  reg first_output_pending;
  reg [31:0] line_mem [0:BANK_DEPTH-1];
  reg bypass_valid;
  reg [31:0] bypass_data;
  reg bypass_last, bypass_user;

  function automatic [31:0] calc_repeat;
    input [31:0] phase, numerator, denominator;
    reg [63:0] temp; integer k;
    begin
      temp={32'd0,phase}+{32'd0,numerator}; calc_repeat=0;
      if (denominator!=0)
        for(k=0;k<MAX_REPEAT;k=k+1)
          if(temp>={32'd0,denominator}) begin temp=temp-{32'd0,denominator}; calc_repeat=calc_repeat+1'b1; end
    end
  endfunction
  function automatic [31:0] calc_phase;
    input [31:0] phase, numerator, denominator;
    reg [63:0] temp; integer k;
    begin
      temp={32'd0,phase}+{32'd0,numerator};
      if (denominator!=0)
        for(k=0;k<MAX_REPEAT;k=k+1)
          if(temp>={32'd0,denominator}) temp=temp-{32'd0,denominator};
      calc_phase=temp[31:0];
    end
  endfunction

  wire bypass_ready=!bypass_valid || m_tready;
  assign s_tready = !enable ? bypass_ready : ((state==ST_READ) && !config_error);
  assign m_tvalid = !enable ? bypass_valid : (state==ST_WRITE);
  assign m_tdata = !enable ? bypass_data : ((read_count<MAX_WIDTH) ? line_mem[read_count] : 32'd0);
  assign m_tlast = !enable ? bypass_last : ((state==ST_WRITE) && (dst_width_q!=0) && (read_count==dst_width_q-1'b1));
  assign m_tuser = !enable ? bypass_user : ((state==ST_WRITE) && first_output_pending && (read_count==0));

  wire [31:0] current_x = s_tuser ? 0 : source_x;
  wire [31:0] current_write_count = s_tuser ? 0 : write_count;
  wire [31:0] current_write_end = current_write_count + h_repeat_current;
  wire [31:0] h_phase_after = calc_phase(h_phase,dst_width_q,src_width_q);
  wire [31:0] current_v_repeat = calc_repeat(v_phase,dst_height_q,src_height_q);
  wire [31:0] next_v_phase = calc_phase(v_phase,dst_height_q,src_height_q);
  wire frame_cfg_invalid = (src_width==0)||(src_height==0)||(dst_width==0)||(dst_height==0)||
                            (src_width>MAX_WIDTH)||(dst_width>MAX_WIDTH)||
                            (dst_width>(src_width*MAX_REPEAT))||(dst_height>(src_height*MAX_REPEAT));

  always @(posedge clk) begin
    if(reset) begin
      state<=ST_IDLE; src_width_q<=0; src_height_q<=0; dst_width_q<=0; dst_height_q<=0;
      source_x<=0; write_count<=0; read_count<=0; h_phase<=0; h_repeat_current<=0;
      v_phase<=0; replay_remaining<=0; pending_data<=0; pending_index<=0; pending_repeat<=0;
      pending_write_end<=0; pending_v_repeat<=0; pending_v_phase_next<=0; pending_last<=0;
      first_output_pending<=0; bypass_valid<=0; bypass_data<=0; bypass_last<=0; bypass_user<=0;
      config_error<=1'b0;
    end else if(!enable) begin
      if(bypass_ready) begin
        bypass_valid<=s_tvalid;
        if(s_tvalid) begin bypass_data<=s_tdata; bypass_last<=s_tlast; bypass_user<=s_tuser; end
      end
      state<=ST_BYPASS; config_error<=1'b0;
    end else if((state==ST_IDLE)||(state==ST_BYPASS)) begin
      src_width_q<=src_width; src_height_q<=src_height; dst_width_q<=dst_width; dst_height_q<=dst_height;
      source_x<=0; write_count<=0; read_count<=0; h_phase<=0;
      h_repeat_current<=calc_repeat(0,dst_width,src_width); v_phase<=0; replay_remaining<=0;
      first_output_pending<=0; bypass_valid<=0; config_error<=frame_cfg_invalid; state<=ST_READ;
    end else if(state==ST_READ) begin
      if(s_tvalid && s_tready) begin
        pending_data<=s_tdata; pending_index<=current_write_count; pending_repeat<=h_repeat_current;
        pending_write_end<=current_write_end; pending_last<=s_tlast;
        pending_v_repeat<=current_v_repeat; pending_v_phase_next<=next_v_phase;
        source_x<=current_x+1'b1; h_phase<=h_phase_after;
        if(s_tuser) first_output_pending<=1'b1;
        if(h_repeat_current>MAX_REPEAT) config_error<=1'b1;
        if(h_repeat_current!=0) begin
          state<=ST_HWRITE;
        end else if(s_tlast) begin
          if(current_write_end!=dst_width_q) config_error<=1'b1;
          v_phase<=next_v_phase; source_x<=0; write_count<=0; h_phase<=0;
          h_repeat_current<=calc_repeat(0,dst_width_q,src_width_q);
          if(current_v_repeat!=0) begin replay_remaining<=current_v_repeat; read_count<=0; state<=ST_WRITE; end
        end else state<=ST_PREP;
      end
    end else if(state==ST_PREP) begin
      // The preceding accepted pixel emitted no output.  Compute the next
      // replication count from the already registered phase in this cycle.
      h_repeat_current<=calc_repeat(h_phase,dst_width_q,src_width_q);
      state<=ST_READ;
    end else if(state==ST_HWRITE) begin
      // Exactly one procedural write is visible to the mapper in this state.
      if(pending_index<MAX_WIDTH) line_mem[pending_index]<=pending_data;
      h_repeat_current<=calc_repeat(h_phase,dst_width_q,src_width_q);
      if(pending_repeat>1) begin
        pending_repeat<=pending_repeat-1'b1; pending_index<=pending_index+1'b1;
      end else begin
        pending_repeat<=0; write_count<=pending_write_end;
        if(pending_last) begin
          if(pending_write_end!=dst_width_q) config_error<=1'b1;
          v_phase<=pending_v_phase_next; source_x<=0; write_count<=0; h_phase<=0;
          h_repeat_current<=calc_repeat(0,dst_width_q,src_width_q);
          if(pending_v_repeat!=0) begin replay_remaining<=pending_v_repeat; read_count<=0; state<=ST_WRITE; end
          else state<=ST_READ;
        end else begin state<=ST_READ; end
      end
    end else if(state==ST_WRITE) begin
      if(m_tvalid && m_tready) begin
        if(m_tuser) first_output_pending<=1'b0;
        if(m_tlast) begin
          read_count<=0;
          if(replay_remaining>1) replay_remaining<=replay_remaining-1'b1;
          else begin replay_remaining<=0; state<=ST_READ; end
        end else read_count<=read_count+1'b1;
      end
    end
  end
endmodule
