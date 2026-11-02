`timescale 1ns/1ps
`default_nettype none
// sys100 domain. claim/grant arbitrate the SINGLE existing DMA against TX/Vision.
// Config is trusted CPU input, never an address supplied by an Ethernet packet.
module ethernet_rx_frame_reassembler #(
 parameter integer MAX_WIDTH=640,MAX_HEIGHT=480,TIMEOUT_CYCLES=10000000
)(
 input wire clk,reset,network_ready,cancel,
 input wire arm_valid,output wire arm_ready,
 input wire [31:0] cfg_base0,cfg_base1,cfg_capacity,cfg_stride,cfg_id,cfg_peer_ip,
 input wire [15:0] cfg_width,cfg_height,input wire cfg_rgb565,
 output wire dma_claim,input wire dma_grant,
 output reg dma_start,output wire [1:0] dma_mode,
 output reg [31:0] dma_base,dma_stride,
 output reg [15:0] dma_width,dma_height,
 input wire [31:0] dma_status,input wire dma_done_irq,dma_error_irq,
 input wire dma_awvalid,dma_awready,dma_wvalid,dma_bvalid,dma_bready,
 output wire [31:0] dma_tdata,output wire [3:0] dma_tkeep,
 output wire dma_tvalid,input wire dma_tready,output wire dma_tlast,dma_tuser,
 input wire [79:0] s_desc,input wire s_desc_valid,output wire s_desc_ready,
 input wire [31:0] s_data,input wire [3:0] s_keep,input wire s_valid,
 output wire s_ready,input wire s_last,s_bad,
 output wire frame_valid,input wire frame_take,output wire frame_slot,
 output wire [31:0] frame_base,frame_id,frame_stride,
 output wire [15:0] frame_width,frame_height,output wire frame_rgb565,
 input wire release_valid,release_slot,
 output wire busy,output wire [3:0] buffer_states,
 output reg frame_done,frame_error,config_error,output reg [31:0] expected_offset,
 output reg [31:0] frames_ok,frames_bad,packets_ok,packets_bad,
 output wire ownership_error
);
 localparam IDLE=0,WAIT_PACKET=1,SEND=2,DROP=3,WAIT_DMA=4,FAIL=5;
 reg [2:0] state;reg slot,failed,started,done_seen,engine_seen;
 reg [31:0] layout_base0,layout_base1,layout_capacity;
 reg [31:0] timer,id,peer,total,chunk;
 reg rgb;reg [31:0] bases[0:1],ids[0:1],strides[0:1];
 reg [15:0] widths[0:1],heights[0:1];reg formats[0:1];
 reg [7:0] outstanding;
 reg bad_packet_event_q;
 wire alloc_available,alloc_slot,finish,finish_failed;
 wire header_valid,header_ready,prgb,plast,pidle,packet_rejected;
 wire [31:0] pid,poffset,ptotal,ppeer,pdata;wire [15:0] pw,ph,plen;
 wire [3:0] pkeep;wire pv,pr,pl;
 wire [31:0] udata;wire [3:0] ukeep;wire uv,ur,ul,uu,upl,uidle;
 wire gen_done,adapter_ready;
 // ARM preparation never owns the shared DMA. CSR pending keeps every cfg_*
 // input immutable until the final arm_valid/arm_ready handshake or cancel.
 // Each arithmetic stage ends at FFs; no multiplier/range cone feeds TX grant.
 localparam [2:0] PREP_IDLE=0,PREP_DERIVE=1,PREP_ACCUM=2,
                  PREP_CHECK=3,PREP_DECIDE=4,PREP_WAIT=5;
 reg [2:0] prep_state;
 reg [3:0] prep_step;
 reg [15:0] prep_rows;
 reg [31:0] row_bytes_q,stride_q,pixel_acc,pixel_term,prepared_total;
 reg [47:0] span_acc,span_term;
 reg [32:0] end0_q,end1_q;
 reg bad_fields_q,bad_stride_q,bad_span_q,bad_ends_q,bad_cfg_q,claim_q;
 wire [31:0] stride_value=cfg_stride==0?((row_bytes_q+32'd31)&32'hffffffe0):cfg_stride;
 wire layout_changed=buffer_states!=0 &&
  (cfg_base0!=layout_base0 || cfg_base1!=layout_base1 || cfg_capacity!=layout_capacity);
 assign busy=state!=IDLE;
 assign dma_claim=busy || claim_q;
 assign arm_ready=state==IDLE && pidle && uidle && prep_state==PREP_WAIT &&
  !cancel && network_ready && (bad_cfg_q || (claim_q && alloc_available && dma_grant && quiet));
 wire arm=arm_valid && arm_ready;
 wire accepted_arm=arm && !bad_cfg_q;
 wire quiet=!dma_status[0] && !dma_awvalid && !dma_wvalid && outstanding==0;
 always @(posedge clk)begin
  if(reset)begin
   prep_state<=PREP_IDLE;prep_step<=0;prep_rows<=0;
   row_bytes_q<=0;stride_q<=0;pixel_acc<=0;pixel_term<=0;prepared_total<=0;
   span_acc<=0;span_term<=0;end0_q<=0;end1_q<=0;
   bad_fields_q<=0;bad_stride_q<=0;bad_span_q<=0;bad_ends_q<=0;bad_cfg_q<=0;claim_q<=0;
  end else if(!arm_valid || cancel || !network_ready || busy || arm)begin
   // arm_valid already masks a CSR CANCEL on its write_fire edge. Clear all
   // validity here, so a later ARM cannot inherit an old result or DMA request.
   prep_state<=PREP_IDLE;bad_cfg_q<=0;claim_q<=0;
  end else begin
   claim_q<=prep_state==PREP_WAIT && !bad_cfg_q && alloc_available;
   case(prep_state)
    PREP_IDLE:begin
     row_bytes_q<={16'd0,cfg_width}<<2;
     prep_rows<=cfg_height-16'd1;prep_step<=0;
     end0_q<={1'b0,cfg_base0}+{1'b0,cfg_capacity};
     end1_q<={1'b0,cfg_base1}+{1'b0,cfg_capacity};
     bad_fields_q<=layout_changed || cfg_width==0 || cfg_height==0 ||
      {16'd0,cfg_width}>MAX_WIDTH || {16'd0,cfg_height}>MAX_HEIGHT ||
      cfg_base0[4:0]!=0 || cfg_base1[4:0]!=0 || cfg_capacity==0 ||
      cfg_base0<32'h80000000 || cfg_base1<32'h80000000;
     prep_state<=PREP_DERIVE;
    end
    PREP_DERIVE:begin
     stride_q<=stride_value;span_term<={16'd0,stride_value};
     span_acc<={16'd0,row_bytes_q};
     pixel_acc<={16'd0,cfg_width};pixel_term<={16'd0,cfg_width};
     prep_state<=PREP_ACCUM;
    end
    PREP_ACCUM:begin
     // Both products use (height-1): initialize with one row / one width.
     // Fixed single-bit shifts are wiring, not a variable barrel shifter.
     if(prep_rows[0])begin span_acc<=span_acc+span_term;pixel_acc<=pixel_acc+pixel_term;end
     prep_rows<=prep_rows>>1;span_term<=span_term<<1;pixel_term<=pixel_term<<1;
     prep_step<=prep_step+1'b1;
     if(prep_step==15)prep_state<=PREP_CHECK;
    end
    PREP_CHECK:begin
     // The last nonblocking accumulator update completed on the prior edge.
     bad_stride_q<=stride_q[4:0]!=0 || stride_q<row_bytes_q;
     bad_span_q<=span_acc>{16'd0,cfg_capacity};
     bad_ends_q<=end0_q>33'hc0000000 || end1_q>33'hc0000000 ||
      !(end0_q<={1'b0,cfg_base1} || end1_q<={1'b0,cfg_base0});
     prepared_total<=cfg_rgb565?(pixel_acc<<1):pixel_acc;
     prep_state<=PREP_DECIDE;
    end
    PREP_DECIDE:begin
     bad_cfg_q<=bad_fields_q || bad_stride_q || bad_span_q || bad_ends_q;
     prep_state<=PREP_WAIT;
    end
    PREP_WAIT:begin end
    default:begin prep_state<=PREP_IDLE;claim_q<=0;end
   endcase
  end
 end
 wire fail_now=cancel || !network_ready || (started && dma_error_irq) ||
  (engine_seen && dma_status[2]) || packet_rejected ||
  (timer==TIMEOUT_CYCLES-1);
 assign finish=busy && ((state==WAIT_DMA && done_seen && quiet) ||
  (state==FAIL && (!started || (engine_seen && quiet))));
 assign finish_failed=failed || state==FAIL || fail_now;
 frame_buffer_manager buffers(.clk(clk),.reset(reset),.allocate(accepted_arm),.available(alloc_available),
  .allocation_slot(alloc_slot),.finish(finish),.failed(finish_failed),.finish_slot(slot),
  .take(frame_take),.ready_valid(frame_valid),.ready_slot(frame_slot),
  .release_valid(release_valid),.release_slot(release_slot),.protocol_error(ownership_error),.states(buffer_states));
 assign frame_base=bases[frame_slot];assign frame_id=ids[frame_slot];assign frame_stride=strides[frame_slot];
 assign frame_width=widths[frame_slot];assign frame_height=heights[frame_slot];assign frame_rgb565=formats[frame_slot];
 assign dma_mode=2;
 // network_ready must share the upstream RX FIFO/protocol flush contract.
 // No software cancel flushes the packet parser midway through a record.
 ethernet_image_rx parser(.clk(clk),.reset(reset),.flush(!network_ready),
  .s_desc(s_desc),.s_desc_valid(s_desc_valid),.s_desc_ready(s_desc_ready),
  .s_data(s_data),.s_keep(s_keep),.s_valid(s_valid),.s_ready(s_ready),.s_last(s_last),.s_bad(s_bad),
  .header_valid(header_valid),.header_ready(header_ready),.frame_id(pid),.offset(poffset),.total(ptotal),
  .peer_ip(ppeer),.width(pw),.height(ph),.chunk_bytes(plen),.rgb565(prgb),.last_chunk(plast),
  .m_data(pdata),.m_keep(pkeep),.m_valid(pv),.m_ready(pr),.m_last(pl),.rejected(packet_rejected),.idle(pidle));
 wire [32:0] packet_end={1'b0,poffset}+{17'd0,plen};
 wire correct_header=pid==id && ppeer==peer && pw==dma_width && ph==dma_height && prgb==rgb &&
  ptotal==total && poffset==expected_offset && packet_end<={1'b0,total} && plast==(packet_end=={1'b0,total});
 assign header_ready=state==WAIT_PACKET || state==IDLE || state==FAIL;
 wire header_fire=header_valid && header_ready;
 wire first_packet=header_fire && state==WAIT_PACKET && correct_header && !started;
 assign pr=state==SEND?ur:1'b1;
 ethernet_pixel_unpacker unpack(.clk(clk),.reset(reset),.clear(finish),.start(accepted_arm),
  .rgb565(rgb),.width(dma_width),.s_data(pdata),.s_keep(pkeep),.s_valid(pv && state==SEND),.s_ready(ur),.s_last(pl),
  .m_data(udata),.m_keep(ukeep),.m_valid(uv),.m_ready(state==SEND?adapter_ready:1'b1),
  .m_last(ul),.m_user(uu),.m_packet_last(upl),.idle(uidle));
 ethernet_rx_dma_adapter adapter(.clk(clk),.reset(reset),.clear(finish),.start(first_packet),.pad(failed),
  .width(dma_width),.height(dma_height),.s_data(udata),.s_valid(uv && state==SEND),.s_ready(adapter_ready),
  .m_data(dma_tdata),.m_keep(dma_tkeep),.m_valid(dma_tvalid),.m_ready(dma_tready),
  .m_last(dma_tlast),.m_user(dma_tuser),.all_generated(gen_done));
 always @(posedge clk)begin
  if(reset)outstanding<=0;
  else case({dma_awvalid && dma_awready,dma_bvalid && dma_bready})
   2'b10:outstanding<=outstanding+1'b1;
   2'b01:outstanding<=outstanding-1'b1;
   default:;
  endcase
 end
 // Retire exactly the original per-cycle counter event one cycle later.
 // State transitions and failure draining keep their original timing.
 wire bad_packet_event=(header_fire && state==WAIT_PACKET && !correct_header) ||
  (busy && state!=FAIL && fail_now && packet_rejected);
 always @(posedge clk)begin
  if(reset)bad_packet_event_q<=0;
  else bad_packet_event_q<=bad_packet_event;
 end
 integer i;
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;slot<=0;failed<=0;started<=0;done_seen<=0;engine_seen<=0;
   layout_base0<=0;layout_base1<=0;layout_capacity<=0;timer<=0;id<=0;peer<=0;total<=0;chunk<=0;rgb<=0;
   dma_start<=0;dma_base<=0;dma_stride<=0;dma_width<=0;dma_height<=0;
   frame_done<=0;frame_error<=0;config_error<=0;expected_offset<=0;frames_ok<=0;frames_bad<=0;packets_ok<=0;packets_bad<=0;
   for(i=0;i<2;i=i+1)begin bases[i]<=0;ids[i]<=0;strides[i]<=0;widths[i]<=0;heights[i]<=0;formats[i]<=0;end
  end else begin
   dma_start<=0;frame_done<=0;frame_error<=0;config_error<=0;
   if(bad_packet_event_q)packets_bad<=packets_bad+1'b1;
   if(busy)begin
    if(started && dma_status[0])engine_seen<=1;
    if((state==WAIT_PACKET && header_fire) || (state==SEND && uv && adapter_ready))timer<=0;
    else if(timer!=TIMEOUT_CYCLES-1)timer<=timer+1'b1;
    if(dma_done_irq)done_seen<=1;
   end
   if(arm)begin
    if(bad_cfg_q)config_error<=1;
    else begin
     slot<=alloc_slot;state<=WAIT_PACKET;failed<=0;started<=0;done_seen<=0;engine_seen<=0;timer<=0;expected_offset<=0;
     layout_base0<=cfg_base0;layout_base1<=cfg_base1;layout_capacity<=cfg_capacity;
     id<=cfg_id;peer<=cfg_peer_ip;rgb<=cfg_rgb565;total<=prepared_total;
     dma_base<=alloc_slot?cfg_base1:cfg_base0;dma_stride<=stride_q;dma_width<=cfg_width;dma_height<=cfg_height;
     bases[alloc_slot]<=alloc_slot?cfg_base1:cfg_base0;ids[alloc_slot]<=cfg_id;strides[alloc_slot]<=stride_q;
     widths[alloc_slot]<=cfg_width;heights[alloc_slot]<=cfg_height;formats[alloc_slot]<=cfg_rgb565;
    end
   end
   if(header_fire && state==WAIT_PACKET)begin
    if(correct_header)begin
     chunk<={16'd0,plen};state<=SEND;
     if(!started)begin started<=1;dma_start<=1;end
    end else begin state<=FAIL;failed<=1;end
   end
   if(state==SEND && uv && adapter_ready && upl)begin
    expected_offset<=expected_offset+chunk;packets_ok<=packets_ok+1'b1;
    state<=expected_offset+chunk==total?WAIT_DMA:WAIT_PACKET;
   end
   if(busy && state!=FAIL && fail_now)begin state<=FAIL;failed<=1;end
   if(finish)begin
    state<=IDLE;
    if(finish_failed)begin frame_error<=1;frames_bad<=frames_bad+1'b1;end
    else begin frame_done<=1;frames_ok<=frames_ok+1'b1;end
   end
  end
 end
endmodule
`default_nettype wire
