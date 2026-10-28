`timescale 1ns/1ps
`default_nettype none
// Held-data request/acknowledge mailbox. Source holds all bits until ack.
// Global resets must cover both clocks; datapath reset must NOT reset mailbox.
module ethernet_config_cdc #(
    parameter [143:0] DEFAULT_CONFIG={32'hffffff00,32'hc0a80101,32'hc0a80132,48'h020000000032}
)(
    input wire s_clk,s_reset,input wire [143:0] s_config,input wire commit,
    output wire busy,output reg done,
    input wire m_clk,m_reset,output reg [143:0] m_config,output wire pending,
    input wire apply
);
    reg request,acknowledge;reg [143:0] held;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg [1:0] req_sync,ack_sync;
    assign busy=request!=ack_sync[1];assign pending=req_sync[1]!=acknowledge;
    always @(posedge s_clk)begin
        if(s_reset)begin request<=0;held<=DEFAULT_CONFIG;ack_sync<=0;done<=0;end
        else begin
            ack_sync<={ack_sync[0],acknowledge};done<=busy && ack_sync[0]==request;
            if(commit && !busy)begin held<=s_config;request<=!request;end
        end
    end
    always @(posedge m_clk)begin
        if(m_reset)begin req_sync<=0;acknowledge<=0;m_config<=DEFAULT_CONFIG;end
        else begin
            req_sync<={req_sync[0],request};
            if(pending && apply)begin m_config<=held;acknowledge<=req_sync[1];end
        end
    end
endmodule
`default_nettype wire
