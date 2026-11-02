`timescale 1ns/1ps
`default_nettype none
// RX CSR subpage at existing Ethernet aperture +0x1800. No address-map growth.
// Reset is the shared SoC reset only; software CANCEL is always a drained abort.
module ethernet_rx_regs(
 input wire clk,reset,network_ready,
 input wire [11:0] s_awaddr,input wire s_awvalid,output wire s_awready,
 input wire [31:0] s_wdata,input wire [3:0] s_wstrb,input wire s_wvalid,output wire s_wready,
 output reg [1:0] s_bresp,output reg s_bvalid,input wire s_bready,
 input wire [11:0] s_araddr,input wire s_arvalid,output wire s_arready,
 output reg [31:0] s_rdata,output reg [1:0] s_rresp,output reg s_rvalid,input wire s_rready,
 output wire arm_valid,input wire arm_ready,output reg cancel,
 output reg [31:0] cfg_base0,cfg_base1,cfg_capacity,cfg_stride,cfg_id,cfg_peer_ip,
 output wire [15:0] cfg_width,cfg_height,output wire cfg_rgb565,
 input wire busy,frame_done,frame_error,config_error,ownership_error,
 input wire [3:0] buffer_states,input wire [31:0] expected_offset,frames_ok,frames_bad,packets_ok,packets_bad,
 input wire frame_valid,frame_slot,input wire [31:0] frame_base,frame_id,frame_stride,
 input wire [15:0] frame_width,frame_height,input wire frame_rgb565,
 output reg frame_take,release_valid,release_slot,output wire irq
);
 reg aw_hold,w_hold,pending;reg [11:0] aw;reg [31:0] wd,size_q,format_q;reg [3:0] ws;
 reg [3:0] events,mask;reg snap_valid,snap_slot;reg [31:0] snap_base,snap_stride,snap_id,snap_size,snap_format;
 wire write_fire=aw_hold && w_hold && !s_bvalid;
 wire cancel_write=write_fire && aw==12'h008 && ws[0] && wd[7:0]==2;
 wire [3:0] event_clear=write_fire && aw==12'h010 && ws[0]?wd[3:0]:0;
 wire pending_loss=pending && !network_ready;
 // Link changes asynchronously to a CPU command. Report a runtime event,
 // not a bus fault after software has just observed LINK_READY.
 wire start_link_error=write_fire && aw==12'h008 && ws[0] && wd[7:0]==1 && !busy && !pending && format_q<=1 && !network_ready;
 assign arm_valid=pending && network_ready && !cancel_write;
 assign cfg_width=size_q[15:0];assign cfg_height=size_q[31:16];assign cfg_rgb565=format_q[0];
 assign irq=|(events & mask);
 assign s_awready=!reset && !aw_hold && !s_bvalid;
 assign s_wready=!reset && !w_hold && !s_bvalid;
 assign s_arready=!reset && !s_rvalid;
 function automatic [31:0] merge(input [31:0] oldv,newv,input [3:0] st);
  begin merge=oldv;
   if(st[0])merge[7:0]=newv[7:0];
   if(st[1])merge[15:8]=newv[15:8];
   if(st[2])merge[23:16]=newv[23:16];
   if(st[3])merge[31:24]=newv[31:24];
  end
 endfunction
 always @(posedge clk)begin
  if(reset)begin
   aw_hold<=0;w_hold<=0;pending<=0;aw<=0;wd<=0;ws<=0;size_q<=0;format_q<=0;
   cfg_base0<=0;cfg_base1<=0;cfg_capacity<=0;cfg_stride<=0;cfg_id<=0;cfg_peer_ip<=32'hc0a80164;
   events<=0;mask<=0;cancel<=0;frame_take<=0;release_valid<=0;release_slot<=0;
   s_bvalid<=0;s_bresp<=0;s_rvalid<=0;s_rdata<=0;s_rresp<=0;
   snap_valid<=0;snap_slot<=0;snap_base<=0;snap_stride<=0;snap_id<=0;snap_size<=0;snap_format<=0;
  end else begin
   cancel<=0;frame_take<=0;release_valid<=0;
   events<=(events & ~event_clear) | {ownership_error,config_error,frame_error || pending_loss || start_link_error,frame_done};
   if(arm_valid && arm_ready)pending<=0;
   if(pending_loss)pending<=0;
   if(s_awvalid && s_awready)begin aw_hold<=1;aw<=s_awaddr;end
   if(s_wvalid && s_wready)begin w_hold<=1;wd<=s_wdata;ws<=s_wstrb;end
   if(s_bvalid && s_bready)s_bvalid<=0;
   if(s_rvalid && s_rready)s_rvalid<=0;
   if(write_fire)begin
    aw_hold<=0;w_hold<=0;s_bvalid<=1;s_bresp<=0;
    if(aw[1:0]!=0)s_bresp<=2;
    else if(aw>=12'h020 && aw<=12'h03c)begin
     if(busy || pending)s_bresp<=2;
     else case(aw)
      12'h020:cfg_base0<=merge(cfg_base0,wd,ws);
      12'h024:cfg_base1<=merge(cfg_base1,wd,ws);
      12'h028:cfg_capacity<=merge(cfg_capacity,wd,ws);
      12'h02c:cfg_stride<=merge(cfg_stride,wd,ws);
      12'h030:size_q<=merge(size_q,wd,ws);
      12'h034:format_q<=merge(format_q,wd,ws);
      12'h038:cfg_id<=merge(cfg_id,wd,ws);
      12'h03c:cfg_peer_ip<=merge(cfg_peer_ip,wd,ws);
      default:s_bresp<=2;
     endcase
    end else case(aw)
     12'h008:if(ws[0])begin
      case(wd[7:0])
       1:if(busy || pending || format_q>1)s_bresp<=2;else if(network_ready)pending<=1;
       2:begin pending<=0;cancel<=1;end
       4:if(!frame_valid || snap_valid)s_bresp<=2;
         else begin
          frame_take<=1;snap_valid<=1;snap_slot<=frame_slot;snap_base<=frame_base;
          snap_id<=frame_id;snap_stride<=frame_stride;snap_size<={frame_height,frame_width};snap_format<={31'd0,frame_rgb565};
         end
       8:if(!snap_valid)s_bresp<=2;
         else begin release_valid<=1;release_slot<=snap_slot;snap_valid<=0;end
       default:s_bresp<=2;
      endcase
     end
     12'h00c:if(ws[0])mask<=wd[3:0];
     12'h010:;
     default:s_bresp<=2;
    endcase
   end
   if(s_arvalid && s_arready)begin
    s_rvalid<=1;s_rresp<=0;
    case(s_araddr)
     12'h000:s_rdata<=32'h52584431;
     12'h004:s_rdata<={24'd0,ownership_error,network_ready,snap_valid,frame_valid,1'b0,arm_ready,pending,busy};
     12'h00c:s_rdata<={28'd0,mask};12'h010:s_rdata<={28'd0,events};
     12'h020:s_rdata<=cfg_base0;12'h024:s_rdata<=cfg_base1;12'h028:s_rdata<=cfg_capacity;
     12'h02c:s_rdata<=cfg_stride;12'h030:s_rdata<=size_q;12'h034:s_rdata<=format_q;
     12'h038:s_rdata<=cfg_id;12'h03c:s_rdata<=cfg_peer_ip;
     12'h040:s_rdata<={28'd0,buffer_states};12'h044:s_rdata<=expected_offset;
     12'h048:s_rdata<=frames_ok;12'h04c:s_rdata<=frames_bad;12'h050:s_rdata<=packets_ok;12'h054:s_rdata<=packets_bad;
     12'h060:s_rdata<=snap_base;12'h064:s_rdata<=snap_stride;12'h068:s_rdata<=snap_id;
     12'h06c:s_rdata<=snap_size;12'h070:s_rdata<=snap_format;12'h074:s_rdata<={30'd0,snap_valid,snap_slot};
     default:begin s_rdata<=0;s_rresp<=3;end
    endcase
   end
  end
 end
endmodule
`default_nettype wire
