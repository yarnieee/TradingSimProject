`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// bot_trader: the computer player the user competes against.
//
// *** STUB - TRICIA FILLS IN THE STRATEGY ***
// This is Tricia's part (team plan, Component C: "a bot trader with its own
// ledger trades an 8-day moving-average momentum rule"). Only the ports are
// defined here, so the rest of the build is wired and the sw[1] bot view
// works. Every output is tied to a safe default (no trades, starting cash),
// and `active` is 0, so both bot screens show "NO BOT YET".
//
// What the display expects from the outputs:
//   active        1 once the bot is running (the screens then show its numbers)
//   cash          bot's cash in cents (starts at START_CASH, $10,000 like the player)
//   pos0..3       bot's shares of each stock
//   cb0..3        bot's cost basis per stock in cents (for its profit/loss)
//   value         cash + shares x price, in cents
//   signal        per stock [2k+1:2k]: 1 = buy signal, 2 = sell signal, 0 = none
//                 (shown as an up / down arrow)
//   trades        number of trades so far
//   log_*         the last 5 trades, newest first: entry n is bits [n] (valid,
//                 side: 0 buy / 1 sell), [2n+1:2n] (stock), [16n+15:16n] (price,
//                 cents), [8n+7:8n] (trading day)
// Inputs available: tick (one pulse per trading day), game_live (game running),
// day (trading day number), price0..3 (cents), and each stock's last 30 daily
// prices (samplesK, 30 x 16 bits, newest at [479:464]).
// The bot keeps its own ledger: it never sends fills to the order engine.
module bot_trader #(
    parameter [31:0] START_CASH = 32'd1_000_000   // cents ($10,000), as the player
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         tick,
    input  wire         game_live,
    input  wire [7:0]   day,
    input  wire [15:0]  price0,
    input  wire [15:0]  price1,
    input  wire [15:0]  price2,
    input  wire [15:0]  price3,
    input  wire [479:0] samples0,
    input  wire [479:0] samples1,
    input  wire [479:0] samples2,
    input  wire [479:0] samples3,
    output wire         active,
    output wire [31:0]  cash,
    output wire [9:0]   pos0,
    output wire [9:0]   pos1,
    output wire [9:0]   pos2,
    output wire [9:0]   pos3,
    output wire [31:0]  cb0,
    output wire [31:0]  cb1,
    output wire [31:0]  cb2,
    output wire [31:0]  cb3,
    output wire [31:0]  value,
    output wire [7:0]   signal,
    output wire [7:0]   trades,
    output wire [4:0]   log_valid,
    output wire [4:0]   log_side,
    output wire [9:0]   log_stock,
    output wire [79:0]  log_price,
    output wire [39:0]  log_day
);
    // Safe defaults until the strategy is written.
    assign active    = 1'b0;
    assign cash      = START_CASH;
    assign value     = START_CASH;
    assign pos0      = 10'd0;
    assign pos1      = 10'd0;
    assign pos2      = 10'd0;
    assign pos3      = 10'd0;
    assign cb0       = 32'd0;
    assign cb1       = 32'd0;
    assign cb2       = 32'd0;
    assign cb3       = 32'd0;
    assign signal    = 8'd0;
    assign trades    = 8'd0;
    assign log_valid = 5'd0;
    assign log_side  = 5'd0;
    assign log_stock = 10'd0;
    assign log_price = 80'd0;
    assign log_day   = 40'd0;
endmodule

`default_nettype wire
