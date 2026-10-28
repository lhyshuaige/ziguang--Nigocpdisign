`timescale 1ns/1ps

// Camera control/status register bank.  The command interface mirrors the
// existing single-outstanding SoC CSR fabric and can also be wrapped by an
// AXI4-Lite slave without changing the camera datapath.
module camera_regs (
  input  wire        clk,
  input  wire        reset,
  input  wire        csr_valid,
  input  wire        csr_write,
  input  wire [11:0] csr_addr,
  input  wire [31:0] csr_wdata,
  input  wire [3:0]  csr_wstrb,
  output wire        csr_ready,
  output wire        csr_rsp_valid,
  output wire [31:0] csr_rdata,
  output wire        csr_error,
  input  wire        frame_active_i,
  input  wire        fifo_overflow_i,
  input  wire        frame_drop_i,
  input  wire        fifo_full_i,
  input  wire [31:0] fifo_level_i,
  input  wire [31:0] frame_count_i,
  input  wire [31:0] pixel_count_i,
  output wire        enable_o,
  output wire        soft_reset_pulse_o,
  output wire [1:0]  format_o,
  output wire [31:0] width_o,
  output wire [31:0] height_o
);
  reg [31:0] control_q, format_q, width_q, height_q;
  reg rsp_valid_q, rsp_error_q;
  reg [31:0] rsp_data_q;
  reg soft_reset_q;

  function [31:0] merge_wstrb;
    input [31:0] old_value, new_value;
    input [3:0] strobe;
    begin
      merge_wstrb = old_value;
      if (strobe[0]) merge_wstrb[7:0] = new_value[7:0];
      if (strobe[1]) merge_wstrb[15:8] = new_value[15:8];
      if (strobe[2]) merge_wstrb[23:16] = new_value[23:16];
      if (strobe[3]) merge_wstrb[31:24] = new_value[31:24];
    end
  endfunction

  assign csr_ready = !rsp_valid_q;
  assign csr_rsp_valid = rsp_valid_q;
  assign csr_rdata = rsp_data_q;
  assign csr_error = rsp_error_q;
  assign enable_o = control_q[0];
  assign soft_reset_pulse_o = soft_reset_q;
  assign format_o = format_q[1:0];
  assign width_o = width_q;
  assign height_o = height_q;

  always @(posedge clk) begin
    if (reset) begin
      control_q <= 0; format_q <= 0; width_q <= 0; height_q <= 0;
      rsp_valid_q <= 0; rsp_error_q <= 0; rsp_data_q <= 0; soft_reset_q <= 0;
    end else begin
      rsp_valid_q <= 1'b0;
      rsp_error_q <= 1'b0;
      soft_reset_q <= 1'b0;
      if (csr_valid && csr_ready) begin
        rsp_valid_q <= 1'b1;
        rsp_data_q <= 0;
        if (csr_write) begin
          case (csr_addr)
            12'h000: begin
              control_q <= merge_wstrb(control_q, csr_wdata, csr_wstrb);
              if (csr_wstrb[0] && csr_wdata[1]) soft_reset_q <= 1'b1;
            end
            12'h008: format_q <= merge_wstrb(format_q, csr_wdata, csr_wstrb);
            12'h00c: width_q <= merge_wstrb(width_q, csr_wdata, csr_wstrb);
            12'h010: height_q <= merge_wstrb(height_q, csr_wdata, csr_wstrb);
            12'h02c: begin end // write-one-to-clear is handled by integration status logic
            default: rsp_error_q <= 1'b1;
          endcase
        end else begin
          case (csr_addr)
            12'h000: rsp_data_q <= control_q;
            12'h004: rsp_data_q <= {27'h0, fifo_full_i, frame_drop_i, fifo_overflow_i,
                                    frame_active_i, enable_o};
            12'h008: rsp_data_q <= format_q;
            12'h00c: rsp_data_q <= width_q;
            12'h010: rsp_data_q <= height_q;
            12'h014: rsp_data_q <= fifo_level_i;
            12'h018: rsp_data_q <= frame_count_i;
            12'h01c: rsp_data_q <= pixel_count_i;
            default: begin rsp_data_q <= 0; rsp_error_q <= 1'b1; end
          endcase
        end
      end
    end
  end
endmodule
