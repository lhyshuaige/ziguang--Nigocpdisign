// Fits the four existing QSPI CSRs. CONTROL ticket[7:0], op[15:8], chip[16].
// Each new ticket is accepted once. Software waits for !busy before issuing.
// SET_ADDRESS=1 READ32=2 PROGRAM32=3 ERASE4K=4 JEDEC_ID=5 READ_SR1=6.
// ABI2 adds PAGE_BEGIN=7 (length 1..256), PAGE_DATA=8 (up to 4 bytes), ABORT=9.
// One page program holds CS across CPU gaps; bytes reside in software RAM.
// Configuration protection is structural: no raw opcode/status-write/chip-erase.
module flash_controller #(
 parameter integer HALF_PERIOD=5,
 parameter integer POLL_LIMIT=2000000,
 parameter integer STREAM_LIMIT=100000000,
 parameter [23:0] WRITE_FLOOR=24'h800000
)(
 input wire clk,reset,input wire [31:0] control,txdata,
 output wire [31:0] status,output reg [31:0] rxdata,
 input wire [1:0] flash_miso,output wire [1:0] flash_cs_n,
 output wire flash_sck,output wire flash_mosi
);
 localparam IDLE=0,LAUNCH=1,WAIT_XFER=2,GAP=3;
 localparam DIRECT=0,WREN=1,CHECK_WEL=2,MUTATE=3,POLL=4,PAGE_SEND=5;
 reg [1:0] state;
 reg [2:0] phase;
 reg [7:0] seen,active_ticket,ack,op;
 reg chip,done,error,busy;
 reg [3:0] error_code;
 reg [23:0] address,active_address;
 reg [31:0] payload,polls;
 reg [63:0] serial_tx;
 reg [6:0] serial_bits;
 reg serial_start;
 reg serial_keep,serial_release,page_active,page_chip;
 reg [8:0] page_remaining;
 reg [2:0] gap_count;
 wire serial_done,serial_busy;
 wire [63:0] serial_rx;
 assign status={ack,8'h02,8'h00,error_code,1'b0,error,done,busy};
 spi_transfer #(.HALF_PERIOD(HALF_PERIOD)) u_spi(
  .clk(clk),.reset(reset),.start(serial_start),.chip(chip),
  .keep_cs(serial_keep),.release_cs(serial_release),
  .bit_count(serial_bits),.tx(serial_tx),.miso(flash_miso),
  .cs_n(flash_cs_n),.sck(flash_sck),.mosi(flash_mosi),
  .busy(serial_busy),.done(serial_done),.rx(serial_rx));
 task finish;
  input failed;
  input [3:0] code;
  begin busy<=0;done<=1;error<=failed;error_code<=code;ack<=active_ticket;state<=IDLE;end
 endtask
 // SET_ADDRESS is accepted only outside a page stream. The stream timeout
 // therefore cannot affect this load. Keep its comparator out of the
 // address register's enable/data cone without changing command latency.
 wire load_address = state==IDLE && !page_active && control[7:0]!=seen &&
                     control[31:17]==0 && control[15:8]==1 && txdata[31:24]==0;
 wire completed_poll_write = state==WAIT_XFER && serial_done &&
                             phase==POLL && !serial_rx[0] && op==3;
 // Match the original final else branch, including unused phase encodings.
 wire completed_direct_read = state==WAIT_XFER && serial_done &&
                              phase!=PAGE_SEND && phase!=WREN &&
                              phase!=CHECK_WEL && phase!=MUTATE && phase!=POLL &&
                              op==2 && active_address!=24'hfffffc;
 wire advance_address = completed_poll_write || completed_direct_read;
 // Byte-local adders bound the device carry/CE chain. Carry into each byte
 // is computed directly from the old address, never through another byte.
 // This is exactly the original modulo-24-bit +4, including unaligned inputs.
 wire carry_byte1 = &active_address[7:2];
 wire carry_byte2 = &active_address[15:2];
 always @(posedge clk) begin
  if(reset) address[7:0]<=0;
  else if(load_address) address[7:0]<=txdata[7:0];
  else if(advance_address) address[7:0]<=active_address[7:0]+8'd4;
 end
 always @(posedge clk) begin
  if(reset) address[15:8]<=0;
  else if(load_address) address[15:8]<=txdata[15:8];
  else if(advance_address) address[15:8]<=active_address[15:8]+{7'b0,carry_byte1};
 end
 always @(posedge clk) begin
  if(reset) address[23:16]<=0;
  else if(load_address) address[23:16]<=txdata[23:16];
  else if(advance_address) address[23:16]<=active_address[23:16]+{7'b0,carry_byte2};
 end
 always @(posedge clk) begin
  if(reset) begin
   state<=IDLE;phase<=DIRECT;seen<=0;active_ticket<=0;ack<=0;
   op<=0;chip<=0;done<=0;error<=0;busy<=0;error_code<=0;
   active_address<=0;payload<=0;polls<=0;
   serial_tx<=0;serial_bits<=0;serial_start<=0;rxdata<=0;
   serial_keep<=0;serial_release<=0;page_active<=0;page_chip<=0;page_remaining<=0;
   gap_count<=0;
  end else begin
   serial_start<=0;serial_release<=0;
   if(state!=GAP)gap_count<=0;
   // Send-idle and WIP polling are mutually exclusive. Reuse the existing
   // counter instead of adding a second 32-bit hardware timeout counter.
   if(page_active && !busy)polls<=polls+1'b1;
   // Busy writes are discarded, never replayed after completion.
   if(control[7:0]!=seen) seen<=control[7:0];
   case(state)
    IDLE: if(page_active && polls>=STREAM_LIMIT-1) begin
     // Ending CS may launch a partial NOR program. Drain its WIP before
     // reporting starvation, so a following command cannot overlap it.
     serial_release<=1;page_active<=0;chip<=page_chip;op<=9;
     phase<=POLL;busy<=1;error_code<=6;polls<=0;state<=GAP;
    end else if(control[7:0]!=seen) begin
     active_ticket<=control[7:0];ack<=control[7:0];
     op<=control[15:8];chip<=control[16];payload<=txdata;
     active_address<=address;polls<=0;done<=0;error<=0;error_code<=0;
     if(control[31:17]!=0) begin done<=1;error<=1;error_code<=1;end
     else if(page_active && control[15:8]!=8 && control[15:8]!=9) begin done<=1;error<=1;error_code<=7;end
     else if(control[15:8]==9) begin
      serial_release<=1;page_active<=0;
      if(page_active)begin phase<=POLL;busy<=1;state<=GAP;chip<=page_chip;end
      else done<=1;
     end else if(control[15:8]==8) begin
      if(!page_active || control[16]!=page_chip)begin done<=1;error<=1;error_code<=7;end
      else begin busy<=1;phase<=PAGE_SEND;state<=LAUNCH;end
     end
     else if(control[15:8]==1) begin
      if(txdata[31:24]!=0) begin done<=1;error<=1;error_code<=2;end
      else done<=1;
     end else if(control[15:8]<2 || control[15:8]>7) begin
      done<=1;error<=1;error_code<=1;
     end else if((control[15:8]==2 || control[15:8]==3) && address[1:0]!=0) begin
      done<=1;error<=1;error_code<=2;
     end else if(control[15:8]==4 && address[11:0]!=0) begin
      done<=1;error<=1;error_code<=2;
     end else if((control[15:8]==3 || control[15:8]==4 || control[15:8]==7) && address<WRITE_FLOOR) begin
      done<=1;error<=1;error_code<=3;
     end else if(control[15:8]==7 && (txdata<1 || txdata>256 || {1'b0,address[7:0]}+txdata>256)) begin
      done<=1;error<=1;error_code<=2;
     end else begin
      if(control[15:8]==7)begin page_remaining<=txdata[8:0];page_chip<=control[16];end
      busy<=1;phase<=(control[15:8]==3 || control[15:8]==4 || control[15:8]==7)?WREN:DIRECT;
      state<=LAUNCH;
     end
    end
    LAUNCH: begin
     serial_start<=1;serial_keep<=0;state<=WAIT_XFER;
     if(phase==PAGE_SEND)begin
      serial_tx<={payload[7:0],payload[15:8],payload[23:16],payload[31:24],32'h0};
      serial_bits<=page_remaining>=4?7'd32:{1'b0,page_remaining[2:0],3'b000};
      serial_keep<=page_remaining>4;
     end else if(phase==WREN) begin serial_tx<=64'h0600000000000000;serial_bits<=8;end
     else if(phase==CHECK_WEL || phase==POLL || op==6) begin serial_tx<=64'h0500000000000000;serial_bits<=16;end
     else if(phase==MUTATE && op==7) begin serial_tx<={8'h02,active_address,32'h0};serial_bits<=32;serial_keep<=1;end
     else if(phase==MUTATE && op==4) begin serial_tx<={8'h20,active_address,32'h0};serial_bits<=32;end
     else if(phase==MUTATE) begin
      serial_tx<={8'h02,active_address,payload[7:0],payload[15:8],payload[23:16],payload[31:24]};serial_bits<=64;
     end else if(op==5) begin serial_tx<=64'h9f00000000000000;serial_bits<=32;end
     else begin serial_tx<={8'h03,active_address,32'h0};serial_bits<=64;end
    end
    WAIT_XFER: if(serial_done) begin
     if(phase==PAGE_SEND)begin
      if(page_remaining>4)begin page_remaining<=page_remaining-9'd4;finish(0,0);end
      else begin page_active<=0;page_remaining<=0;phase<=POLL;state<=GAP;end
     end else if(phase==WREN) begin phase<=CHECK_WEL;state<=GAP;end
     else if(phase==CHECK_WEL) begin
      if(serial_rx[0] || !serial_rx[1]) finish(1,4);
      else begin phase<=MUTATE;state<=GAP;end
     end else if(phase==MUTATE && op==7)begin page_active<=1;finish(0,0);end
     else if(phase==MUTATE) begin phase<=POLL;state<=GAP;end
     else if(phase==POLL) begin
      if(!serial_rx[0]) begin
       if(op==9 && error_code==6)finish(1,6);else finish(0,0);
      end else if(polls>=POLL_LIMIT-1) finish(1,5);
      else begin polls<=polls+1'b1;state<=GAP;end
     end else begin
      if(op==2) begin
       rxdata<={serial_rx[7:0],serial_rx[15:8],serial_rx[23:16],serial_rx[31:24]};
       // The independent address block prevents wrap into configuration.
      end else if(op==5) rxdata<={8'h0,serial_rx[23:0]};
      else rxdata<={24'h0,serial_rx[7:0]};
      finish(0,0);
     end
    end
    // W25Q128JV tSHSL2 >=50ns. The former one-cycle GAP gave only
    // 40ns at 100MHz. This gap guarantees >=60ns even after explicit release.
    GAP: if(gap_count==4)state<=LAUNCH;else gap_count<=gap_count+1'b1;
    default: state<=IDLE;
   endcase
  end
 end
endmodule
