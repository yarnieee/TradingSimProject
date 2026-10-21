`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_order_validate: every reject code, the check order, the price rule
// (trigger price for new pending orders, execution price otherwise), and the
// book room an SL/TP buy needs.
module tb_order_validate;
    reg        game_live;
    reg        mkt_open;
    reg        retest;
    reg [1:0]  stock;
    reg        side;
    reg [1:0]  otype;
    reg [7:0]  qty;
    reg [15:0] trig;
    reg [15:0] px_exec;
    reg [31:0] cash;
    reg [9:0]  pos0, pos1, pos2, pos3;
    reg        book_full;
    reg [1:0]  brk;
    reg [3:0]  free_cnt;
    wire       ok;
    wire [2:0] code;

    order_validate #(.FEE(100), .POS_MAX(1023)) dut (
        .game_live(game_live), .mkt_open(mkt_open), .retest(retest), .stock(stock), .side(side),
        .otype(otype), .qty(qty), .trig(trig), .px_exec(px_exec), .cash(cash),
        .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .book_full(book_full), .brk(brk), .free_cnt(free_cnt), .ok(ok), .reject_code(code)
    );

    integer n_pass = 0, n_fail = 0;

    task expect_code;
        input [2:0]     want;
        input [8*48:1]  name;
        begin
            #1;
            if (code === want && ok === (want == `RJ_NONE)) begin
                n_pass = n_pass + 1;
            end else begin
                n_fail = n_fail + 1;
                $display("FAIL: %0s: code=%0d ok=%0d, want code=%0d", name, code, ok, want);
            end
        end
    endtask

    // a valid MKT BUY 10 @ 123.05, plenty of cash
    task base;
        begin
            game_live = 1; mkt_open = 1; retest = 0; stock = 0; side = `SIDE_BUY; otype = `OT_MKT;
            qty = 10; trig = 0; px_exec = 12305; cash = 1000000;
            pos0 = 0; pos1 = 0; pos2 = 0; pos3 = 0; book_full = 0; brk = `BRK_OFF; free_cnt = 8;
        end
    endtask

    initial begin
        base; expect_code(`RJ_NONE, "mkt buy ok");

        // 1. not live wins over everything else
        base; game_live = 0; qty = 0; expect_code(`RJ_NOT_LIVE, "not live beats bad qty");

        base; mkt_open = 0; expect_code(`RJ_NOT_LIVE, "stock with no price");
        base; mkt_open = 0; retest = 1; otype = `OT_LMT; expect_code(`RJ_NOT_LIVE, "no price on retest too");

        // 2. qty 0
        base; qty = 0; expect_code(`RJ_BAD_QTY, "qty 0");
        base; qty = 0; otype = `OT_LMT; trig = 0; expect_code(`RJ_BAD_QTY, "qty 0 beats bad trig");

        // 3. trigger 0 on new pending only
        base; otype = `OT_LMT; trig = 0; expect_code(`RJ_BAD_TRIG, "lmt trig 0");
        base; otype = `OT_STP; trig = 0; expect_code(`RJ_BAD_TRIG, "stp trig 0");
        base; otype = `OT_MKT; trig = 0; expect_code(`RJ_NONE, "mkt ignores trig");
        base; otype = `OT_LMT; trig = 0; book_full = 1; expect_code(`RJ_BAD_TRIG, "bad trig beats book full");

        // 4. book full on new pending only
        base; otype = `OT_LMT; trig = 12000; book_full = 1; expect_code(`RJ_BOOK_FULL, "lmt book full");
        base; otype = `OT_MKT; book_full = 1; expect_code(`RJ_NONE, "mkt ignores book full");
        base; otype = `OT_LMT; trig = 0; book_full = 1; retest = 1; expect_code(`RJ_NONE, "retest skips trig and full");
        base; otype = `OT_LMT; trig = 12000; book_full = 1; cash = 0; expect_code(`RJ_BOOK_FULL, "book full beats no cash");

        // 4b. SL/TP on a buy needs 2 free slots, 3 if the buy itself is pending
        base; brk = `BRK_5; free_cnt = 2; expect_code(`RJ_NONE, "sltp mkt buy, 2 free");
        base; brk = `BRK_5; free_cnt = 1; expect_code(`RJ_BOOK_FULL, "sltp mkt buy, 1 free");
        base; brk = `BRK_2; otype = `OT_LMT; trig = 12000; free_cnt = 3; expect_code(`RJ_NONE, "sltp lmt buy, 3 free");
        base; brk = `BRK_2; otype = `OT_LMT; trig = 12000; free_cnt = 2; expect_code(`RJ_BOOK_FULL, "sltp lmt buy, 2 free");
        base; brk = `BRK_10; side = `SIDE_SELL; pos0 = 10; free_cnt = 0; expect_code(`RJ_NONE, "sltp ignored on a sell");
        base; brk = `BRK_10; otype = `OT_LMT; retest = 1; free_cnt = 0; expect_code(`RJ_NONE, "sltp not checked on retest");
        base; brk = `BRK_5; free_cnt = 1; cash = 0; expect_code(`RJ_BOOK_FULL, "sltp room beats no cash");

        // 5. buy cash: cost 123050 + fee 100 = 123150
        base; cash = 123150; expect_code(`RJ_NONE, "cash exactly enough");
        base; cash = 123149; expect_code(`RJ_NO_CASH, "cash 1c short");
        base; qty = 255; expect_code(`RJ_NO_CASH, "buy 255 too expensive");
        // new pending buy is checked at the trigger, not the market
        base; otype = `OT_LMT; trig = 10000; px_exec = 60000; cash = 100100; expect_code(`RJ_NONE, "lmt buy uses trig");
        base; otype = `OT_LMT; trig = 10000; px_exec = 100;   cash = 100099; expect_code(`RJ_NO_CASH, "lmt buy short at trig");
        // re-validation uses the execution price
        base; otype = `OT_LMT; retest = 1; trig = 100; px_exec = 12305; cash = 123149; expect_code(`RJ_NO_CASH, "retest uses px_exec");

        // 6. position overflow on buy
        base; pos0 = 1013; qty = 10; px_exec = 100; expect_code(`RJ_NONE, "pos to 1023 ok");
        base; pos0 = 1014; qty = 10; px_exec = 100; expect_code(`RJ_BAD_QTY, "pos past 1023");

        // 7. sell position, per stock
        base; side = `SIDE_SELL; qty = 5; expect_code(`RJ_NO_POS, "sell with pos 0");
        base; side = `SIDE_SELL; qty = 5; stock = 2; pos2 = 5; expect_code(`RJ_NONE, "sell pos2 = qty");
        base; side = `SIDE_SELL; qty = 5; stock = 2; pos2 = 4; pos0 = 100; expect_code(`RJ_NO_POS, "pos mux picks stock 2");
        base; side = `SIDE_SELL; qty = 5; stock = 3; pos3 = 5; cash = 0; expect_code(`RJ_NONE, "sell ok with zero cash");
        base; side = `SIDE_SELL; otype = `OT_STP; trig = 9000; qty = 5; pos0 = 4; expect_code(`RJ_NO_POS, "stp sell no pos");

        // 8. sell proceeds below fee with no cash
        base; side = `SIDE_SELL; qty = 1; pos0 = 1; px_exec = 95; cash = 4; expect_code(`RJ_NO_CASH, "sell would go negative");
        base; side = `SIDE_SELL; qty = 1; pos0 = 1; px_exec = 95; cash = 5; expect_code(`RJ_NONE, "sell lands on zero");

        if (n_fail == 0) $display("PASS: tb_order_validate (%0d checks)", n_pass);
        else             $display("FAIL: tb_order_validate (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
