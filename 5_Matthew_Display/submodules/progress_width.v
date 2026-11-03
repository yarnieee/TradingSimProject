`timescale 1ns / 1ps
`default_nettype none

// progress_width: the game-progress bar's width, days_gone x WIDTH / DAYS pixels,
// worked out with one quotient bit a clock (32 clocks, over and over) instead of
// a divide in one clock. days_gone changes once a trading day, so the bar is
// never more than 34 clocks behind. DAYS must be below 65,536.
module progress_width #(
    parameter integer DAYS  = 120,         // all the game's days
    parameter integer WIDTH = 96,          // the full bar, pixels
    parameter integer W     = 7            // bits of width
) (
    input  wire          clk,
    input  wire          rst,
    input  wire [31:0]   days_gone,        // 0..DAYS
    output reg  [W-1:0]  width
);
    localparam [16:0] D17 = DAYS;
    reg  [31:0] q;                          // the dividend, shifted into the quotient
    reg  [16:0] rem;                        // below DAYS
    reg  [5:0]  cnt;                        // 0: load, 1..32: one quotient bit each
    wire [17:0] rem_sh = {rem, q[31]};
    wire        fits   = (rem_sh >= {1'b0, D17});
    wire [31:0] dg     = (days_gone > DAYS) ? DAYS : days_gone;

    always @(posedge clk) begin
        if (rst) begin
            cnt   <= 6'd0;
            width <= {W{1'b0}};
        end else if (cnt == 6'd0) begin
            q   <= dg[15:0] * WIDTH;
            rem <= 17'd0;
            cnt <= 6'd1;
        end else begin
            rem <= fits ? rem_sh - {1'b0, D17} : rem_sh[16:0];
            q   <= {q[30:0], fits};
            if (cnt == 6'd32) begin
                width <= (DAYS == 0) ? {W{1'b0}} : {q[30:0], fits};
                cnt   <= 6'd0;
            end else
                cnt <= cnt + 6'd1;
        end
    end
endmodule

`default_nettype wire
