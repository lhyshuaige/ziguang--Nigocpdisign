`timescale 1ns/1ps

// Single-outstanding 32-bit peripheral CSR fabric.
//
// The CPU peripheralBus has no response-ready signal, so a response is held
// for exactly one cycle after an accepted command.  Registering both sides of
// the boundary keeps the decode and the peripheral state updates off the
// CPU's ready/valid combinational path.
module pgl50h_csr_fabric (
  input  wire        clk,
  input  wire        reset,
  input  wire        cmd_valid,
  input  wire        cmd_write,
  input  wire [31:0] cmd_addr,
  input  wire [31:0] cmd_wdata,
  input  wire  [3:0] cmd_wstrb,
  output wire        cmd_ready,
  output wire        rsp_valid,
  output wire [31:0] rsp_rdata,
  output wire        rsp_error,

  input  wire  [7:0] keys,
  output wire  [7:0] leds,
  output wire        timer_irq,
  output wire [63:0] mtime_value,

  input  wire [31:0] ai_status,
  output wire        ai_start,
  output wire [31:0] ai_control,
  output wire [31:0] ai_src_addr,
  output wire [31:0] ai_dst_addr,
  output wire [31:0] ai_length,
  output wire [31:0] ai_channels,
  output wire [31:0] ai_scale,

  input  wire [31:0] dma_status,
  output wire        dma_start,
  output wire [31:0] dma_control,
  output wire [31:0] dma_src_addr,
  output wire [31:0] dma_dst_addr,
  output wire [31:0] dma_length,
  output wire [31:0] dma_stride,
  output wire [31:0] dma_src_stride,
  output wire [31:0] dma_dst_stride,
  output wire [31:0] dma_image_width,
  output wire [31:0] dma_image_height,
  output wire [31:0] dma_output_width,
  output wire [31:0] dma_output_height,

  input  wire [31:0] qspi_status,
  input  wire [31:0] qspi_rxdata,
  output wire [31:0] qspi_control,
  output wire [31:0] qspi_txdata,

  output wire  [5:0] irq_enable,
  output wire  [5:0] irq_clear,
  input  wire  [5:0] irq_pending
);

  reg [7:0]  leds_reg;
  reg [63:0] mtime_reg;
  reg [63:0] mtimecmp_reg;
  reg [31:0] ai_control_reg;
  reg [31:0] ai_src_addr_reg;
  reg [31:0] ai_dst_addr_reg;
  reg [31:0] ai_length_reg;
  reg [31:0] ai_channels_reg;
  reg [31:0] ai_scale_reg;
  reg [31:0] dma_control_reg;
  reg [31:0] dma_src_addr_reg;
  reg [31:0] dma_dst_addr_reg;
  reg [31:0] dma_length_reg;
  reg [31:0] dma_stride_reg;
  reg [31:0] dma_src_stride_reg;
  reg [31:0] dma_dst_stride_reg;
  reg [31:0] dma_image_width_reg;
  reg [31:0] dma_image_height_reg;
  reg [31:0] dma_output_width_reg;
  reg [31:0] dma_output_height_reg;
  reg [31:0] qspi_control_reg;
  reg [31:0] qspi_txdata_reg;
  reg  [5:0] irq_enable_reg;
  reg  [5:0] irq_clear_reg;
  reg        ai_start_reg;
  reg        dma_start_reg;

  reg        rsp_valid_reg;
  reg [31:0] rsp_rdata_reg;
  reg        rsp_error_reg;

  function [31:0] merge_wstrb;
    input [31:0] old_value;
    input [31:0] new_value;
    input  [3:0] strobe;
    begin
      merge_wstrb = old_value;
      if (strobe[0]) merge_wstrb[7:0]   = new_value[7:0];
      if (strobe[1]) merge_wstrb[15:8]  = new_value[15:8];
      if (strobe[2]) merge_wstrb[23:16] = new_value[23:16];
      if (strobe[3]) merge_wstrb[31:24] = new_value[31:24];
    end
  endfunction

  wire [15:0] addr_hi = cmd_addr[31:16];
  wire [3:0]  addr_page = cmd_addr[15:12];
  wire        is_gpio = ((addr_hi == 16'h1000) && (addr_page == 4'h0)) ||
                        (addr_hi == 16'h4000);
  wire        is_qspi = (addr_hi == 16'h1000) && (addr_page == 4'h1);
  wire        is_ai = ((addr_hi == 16'h1001) && (addr_page == 4'h0)) ||
                     ((addr_hi == 16'h4001) && (addr_page == 4'h0));
  wire        is_dma = ((addr_hi == 16'h1001) && (addr_page == 4'h1)) ||
                      ((addr_hi == 16'h4001) && (addr_page == 4'h1));
  // DMA control bit 5 is reserved for the Vision input selector: zero keeps
  // DDR MM2S replay active, one enables the OV7670 DVP camera source.
  // Keep the software-visible CLINT aliases used by the bare-metal CoreMark
  // port.  The compact CSR map above remains the native PGL50H map, while
  // these addresses provide the standard NaxRiscv simulation/firmware view.
  wire        is_clint = (cmd_addr == 32'h1001_4000) ||
                         (cmd_addr == 32'h1001_4004) ||
                         (cmd_addr == 32'h1001_bff8) ||
                         (cmd_addr == 32'h1001_bffc);
  // AI/DMA status bit zero is the architectural busy bit.  Once a descriptor
  // is running, all descriptor writes (including a second start) are rejected
  // with a CSR error; reads remain safe and observable by software.
  wire        ai_busy = ai_status[0];
  wire        dma_busy = dma_status[0];

  assign cmd_ready   = !rsp_valid_reg;
  assign rsp_valid   = rsp_valid_reg;
  assign rsp_rdata   = rsp_rdata_reg;
  assign rsp_error   = rsp_error_reg;
  assign leds        = leds_reg;
  assign timer_irq   = (mtime_reg >= mtimecmp_reg);
  assign mtime_value = mtime_reg;

  assign ai_start    = ai_start_reg;
  assign ai_control  = ai_control_reg;
  assign ai_src_addr = ai_src_addr_reg;
  assign ai_dst_addr = ai_dst_addr_reg;
  assign ai_length   = ai_length_reg;
  assign ai_channels = ai_channels_reg;
  assign ai_scale    = ai_scale_reg;

  assign dma_start    = dma_start_reg;
  assign dma_control  = dma_control_reg;
  assign dma_src_addr = dma_src_addr_reg;
  assign dma_dst_addr = dma_dst_addr_reg;
  assign dma_length   = dma_length_reg;
  assign dma_stride   = dma_stride_reg;
  // Expose the raw source override.  The DMA descriptor boundary resolves
  // source override > legacy stride > automatic aligned stride.
  assign dma_src_stride = dma_src_stride_reg;
  assign dma_dst_stride = dma_dst_stride_reg;
  assign dma_image_width = dma_image_width_reg;
  assign dma_image_height = dma_image_height_reg;
  assign dma_output_width = dma_output_width_reg;
  assign dma_output_height = dma_output_height_reg;

  assign qspi_control = qspi_control_reg;
  assign qspi_txdata  = qspi_txdata_reg;
  assign irq_enable   = irq_enable_reg;
  assign irq_clear    = irq_clear_reg;

  always @(posedge clk) begin
    if (reset) begin
      leds_reg        <= 8'h00;
      mtime_reg       <= 64'h0000_0000_0000_0000;
      mtimecmp_reg    <= 64'hffff_ffff_ffff_ffff;
      ai_control_reg  <= 32'h0;
      ai_src_addr_reg <= 32'h0;
      ai_dst_addr_reg <= 32'h0;
      ai_length_reg   <= 32'h0;
      ai_channels_reg <= 32'h1;
      ai_scale_reg    <= 32'h0000_0100;
      dma_control_reg <= 32'h0;
      dma_src_addr_reg <= 32'h0;
      dma_dst_addr_reg <= 32'h0;
      dma_length_reg  <= 32'h0;
      dma_stride_reg  <= 32'h0;
      dma_src_stride_reg <= 32'h0;
      dma_dst_stride_reg <= 32'h0;
      dma_image_width_reg <= 32'h0;
      dma_image_height_reg <= 32'h0;
      dma_output_width_reg <= 32'h0;
      dma_output_height_reg <= 32'h0;
      qspi_control_reg <= 32'h0;
      qspi_txdata_reg <= 32'h0;
      irq_enable_reg  <= 6'h00;
      irq_clear_reg   <= 6'h00;
      ai_start_reg    <= 1'b0;
      dma_start_reg   <= 1'b0;
      rsp_valid_reg   <= 1'b0;
      rsp_rdata_reg   <= 32'h0;
      rsp_error_reg   <= 1'b0;
    end else begin
      mtime_reg      <= mtime_reg + 64'd1;
      ai_start_reg   <= 1'b0;
      dma_start_reg  <= 1'b0;
      irq_clear_reg  <= 6'h00;
      rsp_valid_reg  <= 1'b0;

      if (cmd_valid && cmd_ready) begin
        rsp_valid_reg <= 1'b1;
        rsp_rdata_reg <= 32'h0000_0000;
        rsp_error_reg <= 1'b0;

        if (is_gpio) begin
          if (cmd_write) begin
            case (cmd_addr[11:0])
              12'h000: if (cmd_wstrb[0]) leds_reg <= cmd_wdata[7:0];
              12'h008: mtime_reg[31:0] <= merge_wstrb(mtime_reg[31:0], cmd_wdata, cmd_wstrb);
              12'h00c: mtime_reg[63:32] <= merge_wstrb(mtime_reg[63:32], cmd_wdata, cmd_wstrb);
              12'h010: mtimecmp_reg[31:0] <= merge_wstrb(mtimecmp_reg[31:0], cmd_wdata, cmd_wstrb);
              12'h014: mtimecmp_reg[63:32] <= merge_wstrb(mtimecmp_reg[63:32], cmd_wdata, cmd_wstrb);
              12'h024: if (cmd_wstrb[0]) irq_enable_reg <= cmd_wdata[5:0];
              12'h028: if (cmd_wstrb[0]) irq_clear_reg <= cmd_wdata[5:0];
              default: rsp_error_reg <= 1'b1;
            endcase
          end else begin
            case (cmd_addr[11:0])
              12'h000: rsp_rdata_reg <= {24'h0, leds_reg};
              12'h004: rsp_rdata_reg <= {24'h0, keys};
              12'h008: rsp_rdata_reg <= mtime_reg[31:0];
              12'h00c: rsp_rdata_reg <= mtime_reg[63:32];
              12'h010: rsp_rdata_reg <= mtimecmp_reg[31:0];
              12'h014: rsp_rdata_reg <= mtimecmp_reg[63:32];
              12'h018: rsp_rdata_reg <= {31'h0, timer_irq};
              12'h020: rsp_rdata_reg <= {26'h0, irq_pending};
              12'h024: rsp_rdata_reg <= {26'h0, irq_enable_reg};
              default: begin rsp_rdata_reg <= 32'h0; rsp_error_reg <= 1'b1; end
            endcase
          end
        end else if (is_qspi) begin
          if (cmd_write) begin
            case (cmd_addr[11:0])
              12'h000: qspi_control_reg <= merge_wstrb(qspi_control_reg, cmd_wdata, cmd_wstrb);
              12'h008: qspi_txdata_reg <= merge_wstrb(qspi_txdata_reg, cmd_wdata, cmd_wstrb);
              default: rsp_error_reg <= 1'b1;
            endcase
          end else begin
            case (cmd_addr[11:0])
              12'h000: rsp_rdata_reg <= qspi_control_reg;
              12'h004: rsp_rdata_reg <= qspi_status;
              12'h00c: rsp_rdata_reg <= qspi_rxdata;
              default: begin rsp_rdata_reg <= 32'h0; rsp_error_reg <= 1'b1; end
            endcase
          end
        end else if (is_ai) begin
          if (cmd_write) begin
            if (ai_busy) begin
              rsp_error_reg <= 1'b1;
            end else begin
              case (cmd_addr[11:0])
                12'h000: begin
                  ai_control_reg <= merge_wstrb(ai_control_reg, cmd_wdata, cmd_wstrb);
                  if (cmd_wstrb[0] && cmd_wdata[0]) ai_start_reg <= 1'b1;
                end
                12'h008: ai_src_addr_reg <= merge_wstrb(ai_src_addr_reg, cmd_wdata, cmd_wstrb);
                12'h00c: ai_dst_addr_reg <= merge_wstrb(ai_dst_addr_reg, cmd_wdata, cmd_wstrb);
                12'h010: ai_length_reg <= merge_wstrb(ai_length_reg, cmd_wdata, cmd_wstrb);
                12'h014: ai_channels_reg <= merge_wstrb(ai_channels_reg, cmd_wdata, cmd_wstrb);
                12'h018: ai_scale_reg <= merge_wstrb(ai_scale_reg, cmd_wdata, cmd_wstrb);
                default: rsp_error_reg <= 1'b1;
              endcase
            end
          end else begin
            case (cmd_addr[11:0])
              12'h000: rsp_rdata_reg <= ai_control_reg;
              12'h004: rsp_rdata_reg <= ai_status;
              12'h008: rsp_rdata_reg <= ai_src_addr_reg;
              12'h00c: rsp_rdata_reg <= ai_dst_addr_reg;
              12'h010: rsp_rdata_reg <= ai_length_reg;
              12'h014: rsp_rdata_reg <= ai_channels_reg;
              12'h018: rsp_rdata_reg <= ai_scale_reg;
              default: begin rsp_rdata_reg <= 32'h0; rsp_error_reg <= 1'b1; end
            endcase
          end
        end else if (is_dma) begin
          if (cmd_write) begin
            if (dma_busy) begin
              rsp_error_reg <= 1'b1;
            end else begin
              case (cmd_addr[11:0])
                12'h000: begin
                  dma_control_reg <= merge_wstrb(dma_control_reg, cmd_wdata, cmd_wstrb);
                  if (cmd_wstrb[0] && cmd_wdata[0]) dma_start_reg <= 1'b1;
                end
                12'h008: dma_src_addr_reg <= merge_wstrb(dma_src_addr_reg, cmd_wdata, cmd_wstrb);
                12'h00c: dma_dst_addr_reg <= merge_wstrb(dma_dst_addr_reg, cmd_wdata, cmd_wstrb);
                12'h010: dma_length_reg <= merge_wstrb(dma_length_reg, cmd_wdata, cmd_wstrb);
                12'h014: dma_stride_reg <= merge_wstrb(dma_stride_reg, cmd_wdata, cmd_wstrb);
                12'h018: dma_src_stride_reg <= merge_wstrb(dma_src_stride_reg, cmd_wdata, cmd_wstrb);
                12'h01c: dma_dst_stride_reg <= merge_wstrb(dma_dst_stride_reg, cmd_wdata, cmd_wstrb);
                12'h020: dma_image_width_reg <= merge_wstrb(dma_image_width_reg, cmd_wdata, cmd_wstrb);
                12'h024: dma_image_height_reg <= merge_wstrb(dma_image_height_reg, cmd_wdata, cmd_wstrb);
                12'h028: dma_output_width_reg <= merge_wstrb(dma_output_width_reg, cmd_wdata, cmd_wstrb);
                12'h02c: dma_output_height_reg <= merge_wstrb(dma_output_height_reg, cmd_wdata, cmd_wstrb);
                default: rsp_error_reg <= 1'b1;
              endcase
            end
          end else begin
            case (cmd_addr[11:0])
              12'h000: rsp_rdata_reg <= dma_control_reg;
              12'h004: rsp_rdata_reg <= dma_status;
              12'h008: rsp_rdata_reg <= dma_src_addr_reg;
              12'h00c: rsp_rdata_reg <= dma_dst_addr_reg;
              12'h010: rsp_rdata_reg <= dma_length_reg;
              12'h014: rsp_rdata_reg <= dma_stride_reg;
              12'h018: rsp_rdata_reg <= dma_src_stride_reg;
              12'h01c: rsp_rdata_reg <= dma_dst_stride_reg;
              12'h020: rsp_rdata_reg <= dma_image_width_reg;
              12'h024: rsp_rdata_reg <= dma_image_height_reg;
              12'h028: rsp_rdata_reg <= dma_output_width_reg;
              12'h02c: rsp_rdata_reg <= dma_output_height_reg;
              default: begin rsp_rdata_reg <= 32'h0; rsp_error_reg <= 1'b1; end
            endcase
          end
        end else if (is_clint) begin
          if (cmd_write) begin
            case (cmd_addr)
              32'h1001_4000: mtimecmp_reg[31:0] <= merge_wstrb(mtimecmp_reg[31:0], cmd_wdata, cmd_wstrb);
              32'h1001_4004: mtimecmp_reg[63:32] <= merge_wstrb(mtimecmp_reg[63:32], cmd_wdata, cmd_wstrb);
              default: rsp_error_reg <= 1'b1;
            endcase
          end else begin
            case (cmd_addr)
              32'h1001_4000: rsp_rdata_reg <= mtimecmp_reg[31:0];
              32'h1001_4004: rsp_rdata_reg <= mtimecmp_reg[63:32];
              32'h1001_bff8: rsp_rdata_reg <= mtime_reg[31:0];
              32'h1001_bffc: rsp_rdata_reg <= mtime_reg[63:32];
              default: begin rsp_rdata_reg <= 32'h0; rsp_error_reg <= 1'b1; end
            endcase
          end
        end else begin
          rsp_error_reg <= 1'b1;
        end
      end
    end
  end

endmodule
