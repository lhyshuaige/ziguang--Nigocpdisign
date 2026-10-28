`timescale 1ns/1ps

// Frame-aware AXI4-Stream source selector.  Camera and DDR replay share the
// Vision Pipeline input; selection changes are committed only after the
// currently selected frame has ended.  Both inputs are in the same system
// clock domain by the time they reach this module.
module vision_input_mux #(
  parameter integer DATA_WIDTH = 32,
  parameter integer FRAME_HEIGHT_WIDTH = 32
) (
  input  wire                         clk,
  input  wire                         reset,
  input  wire                         input_sel_req,       // 0=DDR replay, 1=Camera
  input  wire                         switch_request,
  input  wire [FRAME_HEIGHT_WIDTH-1:0] frame_height,

  input  wire [DATA_WIDTH-1:0]         camera_tdata,
  input  wire [DATA_WIDTH/8-1:0]       camera_tkeep,
  input  wire                          camera_tvalid,
  output wire                          camera_tready,
  input  wire                          camera_tuser,
  input  wire                          camera_tlast,

  input  wire [DATA_WIDTH-1:0]         replay_tdata,
  input  wire [DATA_WIDTH/8-1:0]       replay_tkeep,
  input  wire                          replay_tvalid,
  output wire                          replay_tready,
  input  wire                          replay_tuser,
  input  wire                          replay_tlast,

  output wire [DATA_WIDTH-1:0]         m_tdata,
  output wire [DATA_WIDTH/8-1:0]       m_tkeep,
  output wire                          m_tvalid,
  input  wire                          m_tready,
  output wire                          m_tuser,
  output wire                          m_tlast,
  output reg                           active_sel,
  output reg                           switch_pending,
  output reg                           frame_active
);
  localparam integer KEEP_WIDTH = DATA_WIDTH/8;
  reg [DATA_WIDTH-1:0] data_q;
  reg [KEEP_WIDTH-1:0] keep_q;
  reg user_q, last_q, valid_q;
  reg [FRAME_HEIGHT_WIDTH-1:0] line_count_q;

  wire selected_valid = active_sel ? camera_tvalid : replay_tvalid;
  wire selected_user  = active_sel ? camera_tuser  : replay_tuser;
  wire selected_last  = active_sel ? camera_tlast  : replay_tlast;
  wire [DATA_WIDTH-1:0] selected_data = active_sel ? camera_tdata : replay_tdata;
  wire [KEEP_WIDTH-1:0] selected_keep = active_sel ? camera_tkeep : replay_tkeep;
  wire output_slot = !valid_q || m_tready;
  wire selected_fire = selected_valid && output_slot;
  assign camera_tready = active_sel && output_slot;
  assign replay_tready = !active_sel && output_slot;
  assign m_tdata = data_q;
  assign m_tkeep = keep_q;
  assign m_tvalid = valid_q;
  assign m_tuser = user_q;
  assign m_tlast = last_q;

  always @(posedge clk) begin
    if (reset) begin
      data_q <= 0; keep_q <= 0; user_q <= 0; last_q <= 0; valid_q <= 0;
      active_sel <= 1'b0;
      switch_pending <= 1'b0;
      frame_active <= 1'b0;
      line_count_q <= 0;
    end else begin
      if (switch_request && (input_sel_req != active_sel))
        switch_pending <= 1'b1;

      if (selected_fire) begin
        data_q <= selected_data;
        keep_q <= selected_keep;
        user_q <= selected_user;
        last_q <= selected_last;
        valid_q <= 1'b1;

        if (selected_user) begin
          frame_active <= 1'b1;
          line_count_q <= 0;
        end
        if (selected_last) begin
          if (frame_active && ((frame_height == 0) ||
              (line_count_q + 1'b1 >= frame_height))) begin
            frame_active <= 1'b0;
            line_count_q <= 0;
            if (switch_pending || (switch_request && input_sel_req != active_sel)) begin
              active_sel <= input_sel_req;
              switch_pending <= 1'b0;
            end
          end else begin
            line_count_q <= line_count_q + 1'b1;
          end
        end
      end else if (output_slot) begin
        valid_q <= 1'b0;
      end

      // Before the first frame, a requested source can be selected without
      // waiting for a frame boundary.  This is also the reset-time path used
      // by software when it prepares the first camera or replay frame.
      if (!frame_active && switch_request && (input_sel_req != active_sel) &&
          !selected_valid) begin
        active_sel <= input_sel_req;
        switch_pending <= 1'b0;
      end
    end
  end
endmodule
