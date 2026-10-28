`timescale 1ns/1ps
// P1 candidate: original one-beat AXI transaction engine, with the output beat
// register retained and ONE additional prefetch beat. At most one AR is live.
// The saved canonical RTL / SoC source list is not overwritten by this file.
module pgl50h_camera_dma_stream #(
  parameter integer DATA_WIDTH=256,
  parameter integer PIXEL_WIDTH=32
) (
  input wire clk,reset,start,
  input wire [1:0] mode,
  input wire [31:0] src_addr,dst_addr,src_stride,dst_stride,
  input wire [31:0] src_width,src_height,dst_width,dst_height,
  output wire [31:0] status,
  output wire done_irq,error_irq,
  output wire [PIXEL_WIDTH-1:0] m_axis_tdata,
  output wire m_axis_tvalid,
  input wire m_axis_tready,
  output wire m_axis_tlast,m_axis_tuser,
  input wire [PIXEL_WIDTH-1:0] s_axis_tdata,
  input wire s_axis_tvalid,
  output wire s_axis_tready,
  input wire s_axis_tlast,s_axis_tuser,
  output wire [3:0] m_awid,
  output wire [31:0] m_awaddr,
  output wire [3:0] m_awlen,
  output wire m_awvalid,
  input wire m_awready,
  output wire [DATA_WIDTH-1:0] m_wdata,
  output wire [DATA_WIDTH/8-1:0] m_wstrb,
  output wire m_wlast,m_wvalid,
  input wire m_wready,
  input wire [3:0] m_bid,
  input wire [1:0] m_bresp,
  input wire m_bvalid,
  output wire m_bready,
  output wire [3:0] m_arid,
  output wire [31:0] m_araddr,
  output wire [3:0] m_arlen,
  output wire m_arvalid,
  input wire m_arready,
  input wire [3:0] m_rid,
  input wire [DATA_WIDTH-1:0] m_rdata,
  input wire [1:0] m_rresp,
  input wire m_rlast,m_rvalid,
  output wire m_rready
);
  localparam integer LANES=DATA_WIDTH/PIXEL_WIDTH;
  localparam integer COUNT_BITS=$clog2(LANES+1);
  localparam [2:0] BUS_IDLE=0,BUS_RD_CMD=1,BUS_RD_DATA=2,
                   BUS_WR_CMD=3,BUS_WR_DATA=4,BUS_WR_RESP=5;
  localparam [1:0] CFG_IDLE=0,CFG_DERIVE=1,CFG_COMMIT=2;
  reg [2:0] bus_state;
  reg arb_turn,busy_reg,done_reg,error_reg,done_irq_reg,error_irq_reg;
  reg [1:0] cfg_phase,mode_q;
  reg [31:0] src_stride_calc_q,dst_stride_calc_q,src_stride_raw_q,dst_stride_raw_q;
  reg rd_enabled,wr_enabled,rd_fetch_done,rd_frame_done,wr_frame_done;
  reg [31:0] dst_base_q,src_stride_q,dst_stride_q;
  reg [31:0] src_width_q,src_height_q,dst_width_q,dst_height_q;

  // These are FETCH coordinates. Stream markers travel in each beat's metadata
  // instead of being regenerated from a cursor which prefetch has advanced.
  reg [31:0] rd_line,rd_word,rd_line_base,rd_axi_addr;
  reg [DATA_WIDTH-1:0] rd_beat_buf,rd_prefetch_buf;
  reg [COUNT_BITS-1:0] rd_valid_words,rd_prefetch_words;
  reg [COUNT_BITS-1:0] rd_lane;
  reg rd_unpack_active,rd_prefetch_valid;
  reg rd_sof,rd_eol,rd_eof,rd_prefetch_sof,rd_prefetch_eol,rd_prefetch_eof;

  reg [31:0] wr_line,wr_word,wr_line_base,wr_axi_addr;
  reg [3:0] wr_count,wr_buf_words;
  reg wr_buf_pending,wr_buf_last;
  reg [DATA_WIDTH-1:0] wr_buf_data;

  // Reserve the free prefetch slot when choosing RD_CMD. No other read can be
  // chosen until this single transaction returns. Output can only free slots.
  wire rd_request=rd_enabled&&!rd_fetch_done&&!rd_prefetch_valid&&!error_reg;
  wire wr_request=wr_enabled&&wr_buf_pending&&!error_reg;
  wire rd_fire=(bus_state==BUS_RD_DATA)&&m_rvalid&&m_rready;
  wire rd_response_bad=(m_rid!=4'h3)||(m_rresp!=0)||!m_rlast;
  wire rd_good=rd_fire&&!rd_response_bad&&!error_reg;
  wire rd_stream_fire=m_axis_tvalid&&m_axis_tready;
  wire rd_pop=rd_stream_fire&&(rd_lane+1'b1==rd_valid_words);
  wire wr_input_fire=s_axis_tvalid&&s_axis_tready;
  wire wr_bus_fire=(bus_state==BUS_WR_DATA)&&m_wvalid&&m_wready;
  wire wr_resp_fire=(bus_state==BUS_WR_RESP)&&m_bvalid&&m_bready;
  wire [31:0] rd_remaining_words=src_width_q-rd_word;
  wire [31:0] rd_words_this_beat=(rd_remaining_words>=LANES)?LANES:rd_remaining_words;
  // rd_word <= src_width_q: the remaining count cannot underflow.
  // Avoid min(count, LANES) -> add -> compare in the address-select cone.
  wire fetch_eol=(rd_remaining_words<=LANES);
  wire fetch_eof=fetch_eol&&(rd_line+1'b1>=src_height_q);
  wire fetch_sof=(rd_line==0)&&(rd_word==0);
  wire [31:0] wr_words_after_input=wr_word+wr_count+1'b1;
  wire fault_event=(rd_fire&&rd_response_bad)||
    (wr_resp_fire&&((m_bid!=4'h3)||(m_bresp!=0)))||
    (wr_input_fire&&s_axis_tlast&&(wr_words_after_input!=dst_width_q));

  function [DATA_WIDTH/8-1:0] word_strobe;
    input [3:0] words;
    integer n;
    begin
      word_strobe=0;
      for(n=0;n<DATA_WIDTH/8;n=n+1)
        if(n<words*(PIXEL_WIDTH/8))word_strobe[n]=1'b1;
    end
  endfunction
  assign status={25'h0,wr_buf_pending,rd_unpack_active,wr_frame_done,
                 rd_frame_done,error_reg,done_reg,busy_reg};
  assign done_irq=done_irq_reg;
  assign error_irq=error_irq_reg;
  assign m_axis_tdata=(rd_lane<LANES)?rd_beat_buf[rd_lane*PIXEL_WIDTH+:PIXEL_WIDTH]:{PIXEL_WIDTH{1'b0}};
  // On a prefetch/other-direction error, already offered output remains valid
  // and stable until consumed. The job owner switches the sink to discard.
  assign m_axis_tvalid=busy_reg&&rd_enabled&&rd_unpack_active;
  assign m_axis_tlast=m_axis_tvalid&&rd_eol&&(rd_lane+1'b1==rd_valid_words);
  assign m_axis_tuser=m_axis_tvalid&&rd_sof&&(rd_lane==0);
  assign s_axis_tready=busy_reg&&wr_enabled&&!wr_buf_pending&&!wr_frame_done&&!error_reg&&(wr_count<LANES);
  assign m_awid=4'h3;
  assign m_awaddr=wr_axi_addr;
  assign m_awlen=0;
  assign m_awvalid=(bus_state==BUS_WR_CMD);
  assign m_wdata=wr_buf_data;
  assign m_wstrb=word_strobe(wr_buf_words);
  assign m_wlast=1'b1;
  assign m_wvalid=(bus_state==BUS_WR_DATA)&&wr_buf_pending;
  assign m_bready=(bus_state==BUS_WR_RESP);
  assign m_arid=4'h3;
  assign m_araddr=rd_axi_addr;
  assign m_arlen=0;
  assign m_arvalid=(bus_state==BUS_RD_CMD);
  assign m_rready=(bus_state==BUS_RD_DATA);

  always @(posedge clk) begin
    if(reset)begin
      bus_state<=BUS_IDLE;arb_turn<=0;busy_reg<=0;done_reg<=0;error_reg<=0;
      done_irq_reg<=0;error_irq_reg<=0;cfg_phase<=CFG_IDLE;mode_q<=0;
      src_stride_calc_q<=0;dst_stride_calc_q<=0;src_stride_raw_q<=0;dst_stride_raw_q<=0;
      rd_enabled<=0;wr_enabled<=0;rd_fetch_done<=0;rd_frame_done<=0;wr_frame_done<=0;
      dst_base_q<=0;src_stride_q<=0;dst_stride_q<=0;
      src_width_q<=0;src_height_q<=0;dst_width_q<=0;dst_height_q<=0;
      rd_line<=0;rd_word<=0;rd_line_base<=0;rd_axi_addr<=0;
      rd_beat_buf<=0;rd_prefetch_buf<=0;rd_valid_words<=0;rd_prefetch_words<=0;rd_lane<=0;
      rd_unpack_active<=0;rd_prefetch_valid<=0;
      rd_sof<=0;rd_eol<=0;rd_eof<=0;rd_prefetch_sof<=0;rd_prefetch_eol<=0;rd_prefetch_eof<=0;
      wr_line<=0;wr_word<=0;wr_line_base<=0;wr_axi_addr<=0;
      wr_count<=0;wr_buf_words<=0;wr_buf_pending<=0;wr_buf_last<=0;wr_buf_data<=0;
    end else begin
      done_irq_reg<=0;error_irq_reg<=0;
      if(!busy_reg&&start)begin
        mode_q<=mode;src_width_q<=src_width;src_height_q<=src_height;
        dst_width_q<=dst_width;dst_height_q<=dst_height;dst_base_q<=dst_addr;
        src_stride_raw_q<=src_stride;dst_stride_raw_q<=dst_stride;
        // Retain the original descriptor capture / derive / commit pipeline.
        cfg_phase<=CFG_DERIVE;rd_enabled<=0;wr_enabled<=0;
        rd_fetch_done<=0;rd_frame_done<=0;wr_frame_done<=0;
        rd_line<=0;rd_word<=0;rd_line_base<=src_addr;rd_axi_addr<=src_addr;
        rd_valid_words<=0;rd_prefetch_words<=0;rd_lane<=0;
        rd_unpack_active<=0;rd_prefetch_valid<=0;
        wr_line<=0;wr_word<=0;wr_line_base<=dst_addr;wr_axi_addr<=dst_addr;
        wr_count<=0;wr_buf_words<=0;wr_buf_pending<=0;wr_buf_last<=0;wr_buf_data<=0;
        done_reg<=0;error_reg<=0;bus_state<=BUS_IDLE;
        if((mode==0)||
          ((mode!=2'd2)&&((src_width==0)||(src_height==0)))||
          ((mode!=2'd1)&&((dst_width==0)||(dst_height==0)))||
          ((mode!=2'd2)&&((src_addr[4:0]!=0)||((src_stride!=0)&&(src_stride[4:0]!=0))))||
          ((mode!=2'd1)&&((dst_addr[4:0]!=0)||((dst_stride!=0)&&(dst_stride[4:0]!=0)))))begin
          error_reg<=1;error_irq_reg<=1;busy_reg<=0;cfg_phase<=CFG_IDLE;
        end else busy_reg<=1;
      end else if(busy_reg)begin
        if(cfg_phase==CFG_DERIVE)begin
          src_stride_calc_q<=(src_stride_raw_q==0)?((src_width_q*4+31)&32'hffffffe0):src_stride_raw_q;
          dst_stride_calc_q<=(dst_stride_raw_q==0)?((dst_width_q*4+31)&32'hffffffe0):dst_stride_raw_q;
          cfg_phase<=CFG_COMMIT;
        end else if(cfg_phase==CFG_COMMIT)begin
          src_stride_q<=src_stride_calc_q;dst_stride_q<=dst_stride_calc_q;
          rd_enabled<=(mode_q==1)||(mode_q==3);wr_enabled<=(mode_q==2)||(mode_q==3);
          cfg_phase<=CFG_IDLE;
        end else begin
          if(fault_event&&!error_reg)begin error_reg<=1;error_irq_reg<=1;end
          case(bus_state)
            BUS_IDLE:begin
              if(rd_request&&wr_request)begin
                if(!arb_turn)begin bus_state<=BUS_RD_CMD;arb_turn<=1;end
                else begin bus_state<=BUS_WR_CMD;arb_turn<=0;end
              end else if(rd_request)begin bus_state<=BUS_RD_CMD;arb_turn<=1;end
              else if(wr_request)begin bus_state<=BUS_WR_CMD;arb_turn<=0;end
            end
            BUS_RD_CMD:if(m_arvalid&&m_arready)bus_state<=BUS_RD_DATA;
            BUS_RD_DATA:if(rd_fire&&m_rlast)bus_state<=BUS_IDLE;
            BUS_WR_CMD:if(m_awvalid&&m_awready)bus_state<=BUS_WR_DATA;
            BUS_WR_DATA:if(wr_bus_fire)bus_state<=BUS_WR_RESP;
            BUS_WR_RESP:if(wr_resp_fire)begin
              wr_buf_pending<=0;wr_count<=0;bus_state<=BUS_IDLE;
              if(!error_reg&&(m_bid==4'h3)&&(m_bresp==0))begin
                if(wr_buf_last)begin
                  if(wr_line+1>=dst_height_q)wr_frame_done<=1;
                  else begin
                    wr_line<=wr_line+1'b1;wr_word<=0;
                    wr_line_base<=wr_line_base+dst_stride_q;wr_axi_addr<=wr_line_base+dst_stride_q;
                  end
                end else begin
                  wr_word<=wr_word+wr_buf_words;wr_axi_addr<=wr_axi_addr+wr_buf_words*(PIXEL_WIDTH/8);
                end
              end
            end
            default:bus_state<=BUS_IDLE;
          endcase

          // Output handshakes advance ONLY the output slot, never the fetch
          // address. A simultaneous good R can refill a just-consumed slot.
          if(rd_stream_fire)begin
            if(rd_pop)begin
              rd_lane<=0;rd_unpack_active<=0;
              if(rd_eof)rd_frame_done<=1;
              if(rd_prefetch_valid)begin
                rd_beat_buf<=rd_prefetch_buf;rd_valid_words<=rd_prefetch_words;
                rd_sof<=rd_prefetch_sof;rd_eol<=rd_prefetch_eol;rd_eof<=rd_prefetch_eof;
                rd_unpack_active<=1;rd_prefetch_valid<=0;
              end
            end else rd_lane<=rd_lane+1'b1;
          end
          if(rd_good)begin
            if(!rd_unpack_active||rd_pop)begin
              // Capacity reservation forbids simultaneous full prefetch slot
              // and a returning read. Thus this never overwrites that slot.
              rd_beat_buf<=m_rdata;rd_valid_words<=rd_words_this_beat[COUNT_BITS-1:0];
              rd_sof<=fetch_sof;rd_eol<=fetch_eol;rd_eof<=fetch_eof;
              rd_lane<=0;rd_unpack_active<=1;
            end else begin
              rd_prefetch_buf<=m_rdata;rd_prefetch_words<=rd_words_this_beat[COUNT_BITS-1:0];
              rd_prefetch_sof<=fetch_sof;rd_prefetch_eol<=fetch_eol;rd_prefetch_eof<=fetch_eof;
              rd_prefetch_valid<=1;
            end
            if(fetch_eof)rd_fetch_done<=1;
            else if(fetch_eol)begin
              rd_line<=rd_line+1'b1;rd_word<=0;
              rd_line_base<=rd_line_base+src_stride_q;rd_axi_addr<=rd_line_base+src_stride_q;
            end else begin
              // A non-final beat always consumes exactly LANES pixels.
            rd_word<=rd_word+LANES;rd_axi_addr<=rd_axi_addr+LANES*(PIXEL_WIDTH/8);
            end
          end
          if(wr_input_fire)begin
            if(s_axis_tuser)begin wr_line<=0;wr_word<=0;wr_line_base<=dst_base_q;wr_axi_addr<=dst_base_q;end
            wr_buf_data[wr_count*PIXEL_WIDTH+:PIXEL_WIDTH]<=s_axis_tdata;
            if((wr_count==LANES-1)||s_axis_tlast)begin
              wr_buf_words<=wr_count+1'b1;wr_buf_last<=s_axis_tlast;wr_buf_pending<=1;
            end else wr_count<=wr_count+1'b1;
          end
          // Faults inhibit new work while preserving all offered AXI payloads.
          // No outstanding transaction or held output is abandoned on error.
          if(error_reg&&(bus_state==BUS_IDLE)&&!rd_unpack_active&&!rd_prefetch_valid)begin
            busy_reg<=0;wr_buf_pending<=0;wr_count<=0;
          end else if(!error_reg&&!fault_event&&
              (((mode_q==1)&&rd_frame_done)||((mode_q==2)&&wr_frame_done)||
               ((mode_q==3)&&rd_frame_done&&wr_frame_done)))begin
            busy_reg<=0;done_reg<=1;done_irq_reg<=1;
          end
        end
      end
    end
  end
endmodule
