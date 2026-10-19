`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// order_validate: combinational order checks -> ok / reject_code.
//
// Checked in this order; the first that fails sets reject_code:
//   1. !game_live, or the stock has no price (0)     RJ_NOT_LIVE
//   2. qty == 0                                     RJ_BAD_QTY
//   3. new LMT/STP with trig == 0                   RJ_BAD_TRIG
//   4. new LMT/STP with no free slot                RJ_BOOK_FULL
//   5. BUY and cost_px*qty + FEE > cash             RJ_NO_CASH
//   6. BUY and pos + qty > POS_MAX                  RJ_BAD_QTY   [ASSUMPTION] see below
//   7. SELL and qty > pos[stock]                    RJ_NO_POS
//   8. SELL and cash + cost_px*qty < FEE            RJ_NO_CASH   [ASSUMPTION] see below
//
// cost_px is the trigger price for a NEW pending order (spec 5: pending buys
// are checked at the trigger price on submit) and px_exec otherwise (the bid
// or ask the order would fill at right now).
//
// retest = 1 when exec_engine re-validates a pending order that has just
// triggered. Checks 3 and 4 are skipped then: the trigger was already checked
// at submit, and the order is leaving the book, not entering it.
//
// Additions beyond the spec, both so "cash and positions can never go out of
// range" holds without help from C:
//   6. position is 10 bits; buying past 1023 would wrap C's counter. No spare
//      reject code exists, so this reuses RJ_BAD_QTY.
//   8. a sell whose proceeds are below the flat fee lowers cash; with cash
//      near zero that would go negative.
module order_validate #(
    parameter FEE     = 100,     // cents per execution [ASSUMPTION] flat $1
    parameter POS_MAX = 1023
) (
    input  wire        game_live,
    input  wire        mkt_open,     // the stock's mid price is non-zero
    input  wire        retest,
    input  wire [1:0]  stock,
    input  wire        side,
    input  wire [1:0]  otype,
    input  wire [7:0]  qty,
    input  wire [15:0] trig,
    input  wire [15:0] px_exec,
    input  wire [31:0] cash,
    input  wire [9:0]  pos0,
    input  wire [9:0]  pos1,
    input  wire [9:0]  pos2,
    input  wire [9:0]  pos3,
    input  wire        book_full,
    output reg         ok,
    output reg  [2:0]  reject_code
);
    wire        new_pending = (otype != `OT_MKT) && !retest;
    wire [15:0] cost_px     = new_pending ? trig : px_exec;

    // 16 x 8 -> 24-bit, one DSP48
    wire [23:0] value = cost_px * qty;

    reg [9:0] pos_sel;
    always @* begin
        case (stock)
            2'd0:    pos_sel = pos0;
            2'd1:    pos_sel = pos1;
            2'd2:    pos_sel = pos2;
            default: pos_sel = pos3;
        endcase
    end

    wire [32:0] buy_need   = {9'd0, value} + FEE;
    wire [32:0] sell_cash  = {1'b0, cash} + {9'd0, value};
    wire [10:0] pos_after  = {1'b0, pos_sel} + {3'd0, qty};

    wire no_cash_buy  = buy_need > {1'b0, cash};
    wire pos_overflow = pos_after > POS_MAX;
    wire no_pos_sell  = {2'd0, qty} > pos_sel;
    wire no_cash_sell = sell_cash < FEE;

    always @* begin
        ok          = 1'b0;
        reject_code = `RJ_NONE;
        if (!game_live || !mkt_open)
            reject_code = `RJ_NOT_LIVE;
        else if (qty == 8'd0)
            reject_code = `RJ_BAD_QTY;
        else if (new_pending && trig == 16'd0)
            reject_code = `RJ_BAD_TRIG;
        else if (new_pending && book_full)
            reject_code = `RJ_BOOK_FULL;
        else if (side == `SIDE_BUY && no_cash_buy)
            reject_code = `RJ_NO_CASH;
        else if (side == `SIDE_BUY && pos_overflow)
            reject_code = `RJ_BAD_QTY;
        else if (side == `SIDE_SELL && no_pos_sell)
            reject_code = `RJ_NO_POS;
        else if (side == `SIDE_SELL && no_cash_sell)
            reject_code = `RJ_NO_CASH;
        else
            ok = 1'b1;
    end
endmodule

`default_nettype wire
