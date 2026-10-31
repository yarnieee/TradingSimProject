`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_display_numbers: every field of display_numbers against hand-worked
// values: money, prices, P/L signs, order totals (buy and sell), net P/L,
// and the 99999999 limit.
module tb_display_numbers;
    reg clk = 0;
    always #5 clk = ~clk;

    reg        rst = 1;
    reg [31:0] cash = 32'd842_350, pv = 32'd1_307_950;
    reg [15:0] pr0 = 21345, pr1 = 30510, pr2 = 18275, pr3 = 2490;
    reg [9:0]  p0 = 10, p1 = 5, p2 = 0, p3 = 40;
    // profit/loss per stock as Tricia's risk_metrics gives it (shares x price - cost basis)
    reg signed [31:0] u0 = 8450, u1 = -7450, u2 = 0, u3 = 1600;
    reg [1:0]  sel = 1;
    reg [15:0] ref = 31500;
    reg [13:0] qty = 12;
    reg [31:0] days = 17;
    reg        sell = 0;
    reg [1:0]  otype = `OT_MKT;
    reg [15:0] otrig = 16'd30000;
    reg [31:0] bcash = 32'd950_000, bval = 32'd1_012_345;
    reg [9:0]  bp0 = 10, bp1 = 0, bp2 = 0, bp3 = 0;
    reg signed [31:0] bu0 = -6550, bu1 = 0, bu2 = 0, bu3 = 0;
    reg [79:0] lpx = {16'd0, 16'd0, 16'd0, 16'd21000, 16'd21350};
    reg [39:0] lday = {8'd0, 8'd0, 8'd0, 8'd4, 8'd9};
    wire [`DN_N*32-1:0] bcd;
    wire [`DN_N-1:0]    neg;

    display_numbers dut (
        .clk(clk), .rst(rst), .cash(cash), .portfolio_value(pv),
        .price0(pr0), .price1(pr1), .price2(pr2), .price3(pr3),
        .pos0(p0), .pos1(p1), .pos2(p2), .pos3(p3),
        .upnl0(u0), .upnl1(u1), .upnl2(u2), .upnl3(u3),
        .sel_stock(sel), .sel_ref_price(ref), .quantity(qty), .days_left(days),
        .sell(sell), .order_type(otype), .order_trig(otrig), .sel_sl(16'd28990), .sel_tp(16'd0),
        .bot_cash(bcash), .bot_value(bval), .bot_pos0(bp0), .bot_pos1(bp1), .bot_pos2(bp2), .bot_pos3(bp3),
        .bot_upnl0(bu0), .bot_upnl1(bu1), .bot_upnl2(bu2), .bot_upnl3(bu3),
        .log_price(lpx), .log_day(lday),
        .book_qty({48'd0, 8'd5, 8'd12}), .book_trig({96'd0, 16'd21743, 16'd29704}),
        .ret_bp(-32'sd81), .max_dd_bp(32'd91), .bot_ret_bp(32'sd1579),
        .bcd(bcd), .neg(neg)
    );

    integer n_pass = 0, n_fail = 0;
    task check;
        input [5:0]    f;
        input [31:0]   want_bcd;
        input          want_neg;
        input [8*40:1] name;
        begin
            if (bcd[32*f +: 32] === want_bcd && neg[f] === want_neg) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("FAIL: %0s: got %h neg %b, want %h neg %b", name, bcd[32*f +: 32], neg[f], want_bcd, want_neg);
            end
        end
    endtask

    task refresh;            // one full pass over all fields
        begin repeat (`DN_N * 36) @(posedge clk); #1; end
    endtask

    initial begin
        repeat (3) @(posedge clk); rst = 0;
        refresh;
        check(`DN_CASH,    32'h00842350, 0, "cash 8423.50");
        check(`DN_NET,     32'h01307950, 0, "net 13079.50");
        check(`DN_PX0,     32'h00021345, 0, "price AMD 213.45");
        check(`DN_PX0 + 3, 32'h00002490, 0, "price GME 24.90");
        check(`DN_POS0,    32'h00000010, 0, "AMD shares 10");
        check(`DN_POS0 + 3,32'h00000040, 0, "GME shares 40");
        check(`DN_PNL0,    32'h00008450, 0, "AMD P/L +84.50");
        check(`DN_PNL0 + 1,32'h00007450, 1, "MCD P/L -74.50");
        check(`DN_PNL0 + 2,32'h00000000, 0, "NVDA P/L 0");
        check(`DN_CHG,     32'h00000990, 1, "MCD change -9.90");
        check(`DN_QTY,     32'h00000012, 0, "quantity 12");
        check(`DN_DAYS,    32'h00000017, 0, "days left 17");
        check(`DN_ORDPX,   32'h00030515, 0, "buy at ask 305.15");
        check(`DN_ORDTOT,  32'h00366280, 0, "buy total 12 x 305.15 + 1.00");
        check(`DN_NETPNL,  32'h00307950, 0, "net P/L +3079.50");
        check(`DN_TRIG,    32'h00030000, 0, "trigger 300.00");
        check(`DN_SL,      32'h00028990, 0, "stop-loss level 289.90");
        check(`DN_TP,      32'h00000000, 0, "no take-profit: 0");
        check(`DN_BCASH,   32'h00950000, 0, "bot cash 9500.00");
        check(`DN_BNETPNL, 32'h00012345, 0, "bot P/L +123.45");
        check(`DN_BPOS0,   32'h00000010, 0, "bot AMD shares 10");
        check(`DN_BPNL0,   32'h00006550, 1, "bot AMD P/L -65.50");
        check(`DN_LOGPX0,  32'h00021350, 0, "bot log newest price 213.50");
        check(`DN_LOGPX0+1,32'h00021000, 0, "bot log second price 210.00");
        check(`DN_LOGDAY0, 32'h00000009, 0, "bot log newest day 9");
        check(`DN_SLQ0,    32'h00000012, 0, "book slot 0 quantity 12");
        check(`DN_SLT0,    32'h00029704, 0, "book slot 0 price 297.04");
        check(`DN_SLT0+1,  32'h00021743, 0, "book slot 1 price 217.43");
        check(`DN_RET,     32'h00000081, 1, "return -0.81% (basis points)");
        check(`DN_MAXDD,   32'h00000091, 0, "max drawdown 0.91%");
        check(`DN_BRET,    32'h00001579, 0, "bot return +15.79%");

        otype = `OT_LMT; qty = 2;
        refresh;
        check(`DN_ORDPX,   32'h00030000, 0, "limit order shows its trigger 300.00");
        check(`DN_ORDTOT,  32'h00060100, 0, "limit buy total 2 x 300.00 + 1.00");
        otype = `OT_MKT;

        sell = 1; pv = 32'd950_000; qty = 0; cash = 32'hFFFF_FFFF;
        refresh;
        check(`DN_ORDPX,   32'h00030505, 0, "sell at bid 305.05");
        check(`DN_ORDTOT,  32'h00000100, 1, "sell 0 shares: -1.00 (fee)");
        check(`DN_NETPNL,  32'h00050000, 1, "net P/L -500.00");
        check(`DN_CASH,    32'h99999999, 0, "huge value shows 99999999");

        if (n_fail == 0) $display("PASS: tb_display_numbers (%0d checks)", n_pass);
        else             $display("FAIL: tb_display_numbers (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
