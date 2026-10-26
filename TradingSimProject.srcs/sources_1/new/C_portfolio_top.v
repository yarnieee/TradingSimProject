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
// The bot's copy (bot_trader + second ledger + risk_metrics) is added in week 11;
// until then the bot outputs hold their starting values.
module C_portfolio_top (
    input  wire        clk,                 // 100 MHz
    input  wire        sys_reset,           // from D: new game
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
    // ---- to D: bot numbers (week 11) ----
    output wire [31:0] bot_cash,
    output wire [9:0]  bot_pos0, bot_pos1, bot_pos2, bot_pos3,
    output wire signed [31:0] bot_upnl0, bot_upnl1, bot_upnl2, bot_upnl3,
    output wire [31:0] bot_equity,
    output wire signed [31:0] bot_ret_bp,
    output wire [31:0] bot_max_dd_bp
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

    risk_metrics u_risk (
        .clk(clk), .rst(sys_reset), .tick(tick),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .cb0(cb0), .cb1(cb1), .cb2(cb2), .cb3(cb3),
        .equity(equity), .pnl(pnl), .ret_bp(ret_bp),
        .upnl0(upnl0), .upnl1(upnl1), .upnl2(upnl2), .upnl3(upnl3),
        .peak(peak), .dd_bp(dd_bp), .max_dd_bp(max_dd_bp), .mtm_done(mtm_done)
    );

    // ---------------- bot (week 11: replace with bot_trader + ledger + risk_metrics) ----------------
    assign bot_cash      = 32'd1_000_000;
    assign bot_pos0 = 10'd0; assign bot_pos1 = 10'd0; assign bot_pos2 = 10'd0; assign bot_pos3 = 10'd0;
    assign bot_upnl0 = 32'sd0; assign bot_upnl1 = 32'sd0; assign bot_upnl2 = 32'sd0; assign bot_upnl3 = 32'sd0;
    assign bot_equity    = 32'd1_000_000;
    assign bot_ret_bp    = 32'sd0;
    assign bot_max_dd_bp = 32'd0;
endmodule