`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 26.10.2026 11:40:21
// Design Name: 
// Module Name: C_portfolio_top
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


// C_portfolio_top.v: top of Component C 
// Player: fills from B -> ledger -> risk_metrics (every tick) -> numbers for B and D.
// D draws the Portfolio page from these numbers.
// Bot: bot_trader -> its own ledger -> its own risk_metrics. The bot's risk_metrics
// runs on the bot's tick_done (not the raw tick), so its equity includes that day's trades.
module C_portfolio_top #(
    // Kept configurable for A/B resource measurements; enabled on Basys3.
    parameter integer ENABLE_BOT = 1
) (
    input  wire        clk,                 // 100 MHz
    input  wire        sys_reset,           // from D: new game
    input  wire        bot_run,             // from D: 1 while the game is PLAYING
    // price bus from A
    input  wire        tick,
    input  wire [15:0] price0, price1, price2, price3,
    // fill bus from B
    input  wire        fill,
    input  wire [1:0]  fill_stock,
    input  wire        fill_side,
    input  wire [7:0]  fill_qty,
    input  wire [15:0] fill_price,
    input  wire [15:0] fill_fee,
    // ---- to B (and D) ----
    output wire [31:0] cash,                // cents
    output wire [9:0]  pos0, pos1, pos2, pos3,
    output wire        ledger_busy,
    output wire        err,
    // ---- to D: player numbers for the Portfolio page / result screen / 7-seg ----
    output wire signed [31:0] upnl0, upnl1, upnl2, upnl3,   // unrealised P&L per stock (cents)
    output wire signed [31:0] realised,     // realised P&L (cents)
    output wire [31:0] equity,              // cents
    output wire signed [31:0] pnl,          // equity - start (cents)
    output wire signed [31:0] ret_bp,       // return, basis points (+312 = +3.12%)
    output wire [31:0] max_dd_bp,           // max drawdown, basis points
    // ---- to D: bot numbers ----
    output wire [31:0] bot_cash,
    output wire [9:0]  bot_pos0, bot_pos1, bot_pos2, bot_pos3,
    output wire signed [31:0] bot_upnl0, bot_upnl1, bot_upnl2, bot_upnl3,
    output wire signed [31:0] bot_realised,
    output wire [31:0] bot_equity,
    output wire signed [31:0] bot_pnl,
    output wire signed [31:0] bot_ret_bp,
    output wire [31:0] bot_max_dd_bp,
    // bot's most recent trade
    output wire        bot_last_valid,
    output wire [1:0]  bot_last_stock,
    output wire        bot_last_side,       // 0 = buy, 1 = sell
    output wire [7:0]  bot_last_qty,
    output wire [15:0] bot_last_price,      // cents
    output wire        bot_trade_event,    // actual one-clock fill pulse
    output wire [7:0]  bot_signal
);
    // ---------------- player ----------------
    wire [31:0] cb0, cb1, cb2, cb3;

    ledger u_ledger (
        .clk(clk), .rst(sys_reset),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .cb0(cb0), .cb1(cb1), .cb2(cb2), .cb3(cb3),
        .realised(realised), .ledger_busy(ledger_busy), .err(err)
    );

    wire [31:0] peak, dd_bp;
    wire        mtm_done;

    // the player's return % and max drawdown are on the monitor: dividers on (the
    // moving-average bot's below stay off, no screen shows them)
    risk_metrics #(.ENABLE_DIVIDERS(1)) u_risk (
        .clk(clk), .rst(sys_reset), .tick(tick),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .cb0(cb0), .cb1(cb1), .cb2(cb2), .cb3(cb3),
        .equity(equity), .pnl(pnl), .ret_bp(ret_bp),
        .upnl0(upnl0), .upnl1(upnl1), .upnl2(upnl2), .upnl3(upnl3),
        .peak(peak), .dd_bp(dd_bp), .max_dd_bp(max_dd_bp), .mtm_done(mtm_done)
    );

    // ---------------- optional bot ----------------
    wire        bfill, bfill_side, bot_busy, bot_err, bot_tick_done;
    wire [1:0]  bfill_stock;
    wire [7:0]  bfill_qty;
    wire [15:0] bfill_price, bfill_fee;
    wire [31:0] bcb0, bcb1, bcb2, bcb3;

    wire [31:0] bot_peak, bot_dd_bp;
    wire        bot_mtm_done;

    generate
        if (ENABLE_BOT) begin : gen_bot_enabled
            assign bot_trade_event = bfill;
            bot_trader u_bot (
                .clk(clk), .rst(sys_reset), .run(bot_run), .tick(tick),
                .price0(price0), .price1(price1), .price2(price2), .price3(price3),
                .cash(bot_cash), .pos0(bot_pos0), .pos1(bot_pos1), .pos2(bot_pos2), .pos3(bot_pos3),
                .ledger_busy(bot_busy),
                .fill(bfill), .fill_stock(bfill_stock), .fill_side(bfill_side),
                .fill_qty(bfill_qty), .fill_price(bfill_price), .fill_fee(bfill_fee),
                .last_valid(bot_last_valid), .last_stock(bot_last_stock), .last_side(bot_last_side),
                .last_qty(bot_last_qty), .last_price(bot_last_price), .tick_done(bot_tick_done),
                .signals(bot_signal)
            );

            ledger u_bot_ledger (
                .clk(clk), .rst(sys_reset),
                .fill(bfill), .fill_stock(bfill_stock), .fill_side(bfill_side),
                .fill_qty(bfill_qty), .fill_price(bfill_price), .fill_fee(bfill_fee),
                .cash(bot_cash), .pos0(bot_pos0), .pos1(bot_pos1), .pos2(bot_pos2), .pos3(bot_pos3),
                .cb0(bcb0), .cb1(bcb1), .cb2(bcb2), .cb3(bcb3),
                .realised(bot_realised), .ledger_busy(bot_busy), .err(bot_err)
            );

            risk_metrics #(.ENABLE_DIVIDERS(0)) u_bot_risk (
                .clk(clk), .rst(sys_reset), .tick(bot_tick_done),
                .price0(price0), .price1(price1), .price2(price2), .price3(price3),
                .cash(bot_cash), .pos0(bot_pos0), .pos1(bot_pos1), .pos2(bot_pos2), .pos3(bot_pos3),
                .cb0(bcb0), .cb1(bcb1), .cb2(bcb2), .cb3(bcb3),
                .equity(bot_equity), .pnl(bot_pnl), .ret_bp(bot_ret_bp),
                .upnl0(bot_upnl0), .upnl1(bot_upnl1), .upnl2(bot_upnl2), .upnl3(bot_upnl3),
                .peak(bot_peak), .dd_bp(bot_dd_bp), .max_dd_bp(bot_max_dd_bp), .mtm_done(bot_mtm_done)
            );
        end else begin : gen_bot_disabled
            assign bot_trade_event = 1'b0;
            assign bot_signal = 8'd0;
            assign bot_cash       = 32'd0;
            assign bot_pos0       = 10'd0;
            assign bot_pos1       = 10'd0;
            assign bot_pos2       = 10'd0;
            assign bot_pos3       = 10'd0;
            assign bot_upnl0      = 32'sd0;
            assign bot_upnl1      = 32'sd0;
            assign bot_upnl2      = 32'sd0;
            assign bot_upnl3      = 32'sd0;
            assign bot_realised   = 32'sd0;
            assign bot_equity     = 32'd0;
            assign bot_pnl        = 32'sd0;
            assign bot_ret_bp     = 32'sd0;
            assign bot_max_dd_bp  = 32'd0;
            assign bot_last_valid = 1'b0;
            assign bot_last_stock = 2'd0;
            assign bot_last_side  = 1'b0;
            assign bot_last_qty   = 8'd0;
            assign bot_last_price = 16'd0;
        end
    endgenerate
endmodule
