`timescale 1ns/1ps
`default_nettype none
// One outstanding Clause-22 request. All host signals use clk_mgmt.
// Reuses unmodified upstream mdio_master; adds TA detection, timeout, and
// a response for both read and write commands. MDIO tristate belongs at IO.
module ethernet_mdio #(
    parameter integer PRESCALE = 49,
    parameter integer TIMEOUT_CYCLES = 2*(PRESCALE+1)*72+32
)(
    input wire clk_mgmt,
    input wire reset,
    input wire management_ready,
    input wire cmd_valid,
    output wire cmd_ready,
    input wire cmd_read,
    input wire [4:0] cmd_phy_addr,
    input wire [4:0] cmd_reg_addr,
    input wire [15:0] cmd_wdata,
    output reg rsp_valid,
    input wire rsp_ready,
    output reg [15:0] rsp_rdata,
    output reg [1:0] rsp_error, // 0 OK, 1 read TA missing, 2 timeout
    output wire busy,
    output wire mdc,
    input wire mdio_i,
    output wire mdio_o,
    output wire mdio_t
);
    localparam integer TW = TIMEOUT_CYCLES > 1 ? $clog2(TIMEOUT_CYCLES) : 1;
    localparam [TW-1:0] TIMEOUT_LAST=TIMEOUT_CYCLES-1;
    localparam [7:0] MDC_PRESCALE=PRESCALE;
    wire core_ready, core_busy, core_read_valid;
    wire [15:0] core_read_data;
    reg inflight, transaction_read, saw_busy, saw_read_data, ta_error, abort_core;
    reg [TW-1:0] timer;
    reg [6:0] bit_index;
    reg mdc_previous;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg mdio_sync1, mdio_sync2;

    assign cmd_ready = management_ready && !reset && !inflight && !rsp_valid && !abort_core && core_ready;
    assign busy = inflight || rsp_valid;

    always @(posedge clk_mgmt) begin
        mdio_sync1 <= mdio_i;
        mdio_sync2 <= mdio_sync1;
    end

    mdio_master u_master (
        .clk(clk_mgmt), .rst(reset || !management_ready || abort_core),
        .cmd_phy_addr(cmd_phy_addr), .cmd_reg_addr(cmd_reg_addr),
        .cmd_data(cmd_wdata), .cmd_opcode(cmd_read ? 2'b10 : 2'b01),
        .cmd_valid(cmd_valid && cmd_ready), .cmd_ready(core_ready),
        .data_out(core_read_data), .data_out_valid(core_read_valid), .data_out_ready(1'b1),
        .mdc_o(mdc), .mdio_i(mdio_sync2), .mdio_o(mdio_o), .mdio_t(mdio_t),
        .busy(core_busy), .prescale(MDC_PRESCALE)
    );

    always @(posedge clk_mgmt) begin
        if (reset || !management_ready) begin
            inflight <= 0; rsp_valid <= 0; rsp_rdata <= 0; rsp_error <= 0;
            transaction_read <= 0; saw_busy <= 0; saw_read_data <= 0;
            ta_error <= 0; abort_core <= 0; timer <= 0; bit_index <= 0;
            mdc_previous <= 0;
        end else begin
            mdc_previous <= mdc;
            abort_core <= 0;
            if (rsp_valid && rsp_ready) rsp_valid <= 0;
            if (cmd_valid && cmd_ready) begin
                inflight <= 1; transaction_read <= cmd_read;
                saw_busy <= 0; saw_read_data <= 0; ta_error <= 0;
                timer <= 0; bit_index <= 0; rsp_error <= 0; rsp_rdata <= 0;
            end
            if (inflight) begin
                timer <= timer + 1'b1;
                if (core_busy) saw_busy <= 1;
                if (mdc && !mdc_previous) begin
                    if (transaction_read && bit_index == 47 && mdio_sync2) ta_error <= 1;
                    bit_index <= bit_index + 1'b1;
                end
                if (core_read_valid) begin
                    rsp_rdata <= core_read_data;
                    saw_read_data <= 1;
                end
                if (saw_busy && !core_busy) begin
                    inflight <= 0;
                    rsp_valid <= 1;
                    rsp_error <= transaction_read && (ta_error || !saw_read_data) ? 2'd1 : 2'd0;
                end else if (timer == TIMEOUT_LAST) begin
                    inflight <= 0; rsp_valid <= 1; rsp_error <= 2;
                    abort_core <= 1;
                end
            end
        end
    end
endmodule
`default_nettype wire
