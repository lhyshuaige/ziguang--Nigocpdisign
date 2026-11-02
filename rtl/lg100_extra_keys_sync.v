`timescale 1ns/1ps

// KEY2..KEY4 are asynchronous, active-low board inputs. Only the input
// to meta is asynchronous; meta -> synced remains a normally timed path.
module lg100_extra_keys_sync (
  input wire clk,
  input wire reset_n,
  input wire [2:0] key_n,
  output wire [2:0] pressed
);
  (* ASYNC_REG = "TRUE" *) reg [2:0] meta;
  (* ASYNC_REG = "TRUE" *) reg [2:0] synced;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      meta <= 3'b111;
      synced <= 3'b111;
    end else begin
      meta <= key_n;
      synced <= meta;
    end
  end
  assign pressed = ~synced;
endmodule
