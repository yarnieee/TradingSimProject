`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.10.2026 12:16:40
// Design Name: 
// Module Name: seq_divider
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// seq_divider.v: unsigned restoring divider, one quotient bit per clock (W cycles)
// Pulse `start` with dividend/divisor ready. `done` pulses when quotient/remainder are valid.
module seq_divider #(parameter W = 32) (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [W-1:0] dividend,
    input  wire [W-1:0] divisor,
    output reg  [W-1:0] quotient,
    output reg  [W-1:0] remainder,
    output reg          busy,
    output reg          done
);
    reg [W-1:0] q;      // shifts in quotient bits (starts as dividend)
    reg [W-1:0] rem;    // partial remainder
    reg [W-1:0] d;      // latched divisor
    reg [6:0]   count;  // bits left to process

    wire [W:0] shifted = {rem, q[W-1]};
    wire       ge      = (shifted >= {1'b0, d});
    wire [W:0] sub     = shifted - {1'b0, d};
    wire [W-1:0] rem_next = ge ? sub[W-1:0] : shifted[W-1:0];
    wire [W-1:0] q_next   = {q[W-2:0], ge};

    always @(posedge clk) begin
        done <= 1'b0;                       // done is a 1-cycle pulse
        if (rst) begin
            busy <= 1'b0;
            quotient <= 0;
            remainder <= 0;
        end else if (start && !busy) begin
            if (divisor == 0) begin         // divide by zero, return 0, finish at once
                quotient  <= 0;
                remainder <= dividend;
                done      <= 1'b1;
            end else begin
                q     <= dividend;
                rem   <= 0;
                d     <= divisor;
                count <= W;
                busy  <= 1'b1;
            end
        end else if (busy) begin
            q     <= q_next;
            rem   <= rem_next;
            count <= count - 1;
            if (count == 1) begin           // last bit done
                busy      <= 1'b0;
                done      <= 1'b1;
                quotient  <= q_next;
                remainder <= rem_next;
            end
        end
    end
endmodule