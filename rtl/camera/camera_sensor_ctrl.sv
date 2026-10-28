`timescale 1ns/1ps

// Small, portable SCCB/I2C-like write engine for camera register setup.
// Software or a future init-table sequencer supplies one register/data pair
// per command.  The open-drain outputs are deliberately exposed as OE/data
// signals so the board wrapper can map them to the PGL50H IO standard.
module camera_sensor_ctrl #(
  parameter integer CLK_DIV = 500,
  parameter [7:0] DEVICE_WRITE_ADDR = 8'h42,
  parameter integer CHECK_ACK = 1
) (
  input  wire        clk,
  input  wire        reset,
  input  wire        sensor_enable,
  input  wire        sensor_pwdn_req,
  input  wire        sensor_reset_req,
  output wire        sensor_pwdn,
  output wire        sensor_reset_n,
  input  wire        cmd_valid,
  output wire        cmd_ready,
  input  wire [7:0]  cmd_reg_addr,
  input  wire [7:0]  cmd_data,
  output reg         cmd_done,
  output reg         cmd_error,
  output wire        busy,
  input  wire        sccb_scl_i,
  output wire        sccb_scl_o,
  output wire        sccb_scl_oe,
  input  wire        sccb_sda_i,
  output wire        sccb_sda_o,
  output wire        sccb_sda_oe
);
  localparam [3:0] ST_IDLE=4'd0, ST_START0=4'd1, ST_START1=4'd2,
                   ST_BIT_LOW=4'd3, ST_BIT_HIGH=4'd4,
                   ST_ACK_LOW=4'd5, ST_ACK_HIGH=4'd6,
                   ST_STOP0=4'd7, ST_STOP1=4'd8, ST_STOP2=4'd9;
  reg [3:0] state_q;
  reg [15:0] div_q;
  reg [7:0] reg_addr_q, data_q, byte_q;
  reg [2:0] bit_q;
  reg [1:0] byte_index_q;
  reg ack_error_q;
  reg sensor_pwdn_q, sensor_reset_n_q;
  wire tick = (div_q == 0);

  assign busy = (state_q != ST_IDLE);
  assign cmd_ready = (state_q == ST_IDLE);
  assign sensor_pwdn = sensor_pwdn_q;
  assign sensor_reset_n = sensor_reset_n_q;

  // Open-drain convention: oe=1 drives the line low, oe=0 releases it.
  assign sccb_scl_o = 1'b0;
  assign sccb_sda_o = 1'b0;
  assign sccb_scl_oe = (state_q == ST_START1) || (state_q == ST_BIT_LOW) ||
                       (state_q == ST_ACK_LOW) || (state_q == ST_STOP0) ||
                       (state_q == ST_STOP1);
  assign sccb_sda_oe = (state_q == ST_START0) || (state_q == ST_START1) ||
                       (state_q == ST_STOP0) || (state_q == ST_STOP1) ||
                       ((state_q == ST_BIT_LOW || state_q == ST_BIT_HIGH) &&
                        (byte_q[bit_q] == 1'b0));

  always @(posedge clk) begin
    if (reset) begin
      state_q <= ST_IDLE; div_q <= 0; reg_addr_q <= 0; data_q <= 0;
      byte_q <= 0; bit_q <= 0; byte_index_q <= 0; ack_error_q <= 0;
      cmd_done <= 1'b0; cmd_error <= 1'b0;
      sensor_pwdn_q <= 1'b1; sensor_reset_n_q <= 1'b0;
    end else begin
      cmd_done <= 1'b0;
      cmd_error <= 1'b0;
      sensor_pwdn_q <= !sensor_enable || sensor_pwdn_req;
      sensor_reset_n_q <= sensor_enable && !sensor_reset_req;

      if (!tick) div_q <= div_q - 1'b1;
      else begin
        div_q <= (CLK_DIV > 0) ? CLK_DIV-1 : 0;
        case (state_q)
          ST_IDLE: begin
            if (cmd_valid) begin
              reg_addr_q <= cmd_reg_addr;
              data_q <= cmd_data;
              byte_q <= DEVICE_WRITE_ADDR;
              bit_q <= 3'd7;
              byte_index_q <= 0;
              ack_error_q <= 1'b0;
              state_q <= ST_START0;
            end
          end
          ST_START0: state_q <= ST_START1;
          ST_START1: state_q <= ST_BIT_LOW;
          ST_BIT_LOW: state_q <= ST_BIT_HIGH;
          ST_BIT_HIGH: begin
            if (bit_q != 0) begin
              bit_q <= bit_q - 1'b1;
              state_q <= ST_BIT_LOW;
            end else state_q <= ST_ACK_LOW;
          end
          ST_ACK_LOW: state_q <= ST_ACK_HIGH;
          ST_ACK_HIGH: begin
            if (CHECK_ACK && sccb_sda_i) ack_error_q <= 1'b1;
            if (byte_index_q == 0) begin
              byte_q <= reg_addr_q; bit_q <= 3'd7; byte_index_q <= 1; state_q <= ST_BIT_LOW;
            end else if (byte_index_q == 1) begin
              byte_q <= data_q; bit_q <= 3'd7; byte_index_q <= 2; state_q <= ST_BIT_LOW;
            end else state_q <= ST_STOP0;
          end
          ST_STOP0: state_q <= ST_STOP1;
          ST_STOP1: state_q <= ST_STOP2;
          ST_STOP2: begin
            state_q <= ST_IDLE;
            cmd_done <= 1'b1;
            cmd_error <= ack_error_q | (CHECK_ACK && sccb_sda_i);
          end
          default: state_q <= ST_IDLE;
        endcase
      end
    end
  end
endmodule
