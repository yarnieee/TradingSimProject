`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_B_order_top: spec section 10 scenarios, end to end, through the real UI
// path (the five buttons; no mouse) with stub_market and stub_ledger standing in
// for Yi An's market and Tricia's ledger. stub_ledger stops the sim with FAIL if cash or a position ever
// goes out of range, or if a fill arrives while ledger_busy.
//
// Run order is 1-7, 9-12, 8, 13 so the book is empty where a scenario needs
// it: scenario 8 fills the book, and 13 (reset mid-scan) is what clears it.
// 14-15: orders from Matthew's confirm screen, closed stocks.
// 16-21: stop-loss / take-profit, cancelling from the ORDERS view, and the
// ticket's own stock selector.
module tb_B_order_top;
    reg clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------ stimulus
    reg        sys_reset = 1;
    reg [1:0]  game_state = `GS_PLAYING;
    reg [1:0]  sel_stock = 0;
    reg        page_R = `PG_R_TICKET;
    reg [4:0]  btn_pulse = 0;
    reg        ord_req = 0, ord_side = 0;
    reg [1:0]  ord_type = 0;
    reg [13:0] ord_qty = 0;
    reg [15:0] ord_trig = 0;
    reg [1:0]  ord_brk = 0;
    reg [6:0]  xR = 0;
    reg [5:0]  yR = 0;

    reg [1:0]  mkt_mode = 0;
    reg        tick_req = 0;
    reg        force_en = 0;
    reg [1:0]  force_stock = 0;
    reg [15:0] force_price = 0;

    // ------------------------------------------------------------ wiring
    wire [15:0] price0, price1, price2, price3;
    wire        tick;
    wire [31:0] cash;
    wire [9:0]  pos0, pos1, pos2, pos3;
    wire        ledger_busy;
    wire        fill, fill_side, reject;
    wire [1:0]  fill_stock;
    wire [7:0]  fill_qty;
    wire [15:0] fill_price, fill_fee, ticket_pixel;
    wire [2:0]  reject_code;
    wire [3:0]  pending_count;

    stub_market #(.P0(10000), .P1(4520), .P2(8800), .P3(1230), .TICK_DIV(0)) u_mkt (
        .clk(clk), .sys_reset(sys_reset), .mode(mkt_mode), .tick_req(tick_req),
        .force_en(force_en), .force_stock(force_stock), .force_price(force_price),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3), .tick(tick)
    );

    stub_ledger #(.START_CASH(1000000), .BUSY_CYCLES(40)) u_led (
        .clk(clk), .sys_reset(sys_reset),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy)
    );

    B_order_top #(.REJ_SHOW_CYCLES(1000)) u_dut (
        .clk(clk), .sys_reset(sys_reset), .game_state(game_state),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3), .tick(tick),
        .sel_stock(sel_stock), .page_R(page_R),
        .btn_pulse(btn_pulse),
        .ord_req(ord_req), .ord_side(ord_side), .ord_type(ord_type), .ord_qty(ord_qty), .ord_trig(ord_trig), .ord_brk(ord_brk),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy), .xR(xR), .yR(yR),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .reject(reject), .reject_code(reject_code), .pending_count(pending_count),
        .ticket_pixel(ticket_pixel)
    );

    // ------------------------------------------------------------ event log
    integer    n_fill = 0, n_rej = 0;
    reg [2:0]  last_rej = 0;
    integer    f_time [0:63];
    reg [1:0]  f_stock [0:63];
    reg        f_side  [0:63];
    reg [7:0]  f_qty   [0:63];
    reg [15:0] f_price [0:63];

    always @(posedge clk) begin
        if (fill) begin
            f_time[n_fill]  = $time;
            f_stock[n_fill] = fill_stock;
            f_side[n_fill]  = fill_side;
            f_qty[n_fill]   = fill_qty;
            f_price[n_fill] = fill_price;
            n_fill = n_fill + 1;
        end
        if (reject) begin
            last_rej = reject_code;
            n_rej = n_rej + 1;
        end
    end

    // ------------------------------------------------------------ checking
    integer n_pass = 0, n_fail = 0;

    task check;
        input          cond;
        input [8*64:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("FAIL: %0s (t=%0t)", name, $time);
            end
        end
    endtask

    task scenario;
        input [8*64:1] name;
        begin
            $display("---- %0s", name);
        end
    endtask

    // ------------------------------------------------------------ low-level drivers
    task step;
        input integer n;
        begin
            repeat (n) @(posedge clk);
            #1;
        end
    endtask

    task settle;            // long enough for 8 back-to-back fills
        begin
            step(600);
        end
    endtask

    localparam K_UP = `BTN_U, K_DOWN = `BTN_D, K_LEFT = `BTN_L, K_RIGHT = `BTN_R, K_CENTER = `BTN_C;
    task press;
        input integer k;
        begin
            btn_pulse = 5'b00001 << k;
            step(1);
            btn_pulse = 0;
            step(2);
        end
    endtask

    task set_stock;
        input [1:0] s;
        begin
            sel_stock = s; step(3);
        end
    endtask

    task set_price;
        input [1:0]  s;
        input [15:0] p;
        begin
            force_stock = s; force_price = p; force_en = 1; step(1); force_en = 0; step(1);
        end
    endtask

    task do_tick;
        begin
            tick_req = 1; step(1); tick_req = 0; step(1);
        end
    endtask

    // ------------------------------------------------------------ UI-level helpers
    // Buttons only (no mouse). Focus: 0 qty, 1 trig, 2 submit, 3 SL/TP, 4 ORDERS, 5 stock.
    localparam F_QTY = 0, F_TRG = 1, F_SUB = 2, F_BRK = 3, F_ORD = 4, F_STK = 5;
    task focus_to;
        input [2:0] f;
        integer k;
        begin
            for (k = 0; k < 6 && u_dut.u_entry.focus != f; k = k + 1) press(K_RIGHT);
        end
    endtask

    task set_brk;                  // up/down on the SL/TP field
        input [1:0] b;
        integer k;
        begin
            focus_to(F_BRK);
            for (k = 0; k < 4 && u_dut.u_entry.brk != b; k = k + 1) press(K_UP);
        end
    endtask

    task cancel_slot;              // ORDERS view: move the cursor, centre cancels
        input [2:0] slot;
        integer k;
        begin
            focus_to(F_ORD);
            for (k = 0; k < 8 && u_dut.u_entry.ord_sel != slot; k = k + 1) press(K_DOWN);
            press(K_CENTER);
            step(3);
        end
    endtask

    task set_side;                 // centre on the qty field toggles BUY/SELL
        input s;
        begin
            focus_to(F_QTY);
            if (u_dut.u_entry.side != s) press(K_CENTER);
        end
    endtask

    task set_type;                 // centre on the trig field cycles MKT/LMT/STP
        input [1:0] t;
        integer k;
        begin
            focus_to(F_TRG);
            for (k = 0; k < 3 && u_dut.u_entry.otype != t; k = k + 1) press(K_CENTER);
        end
    endtask

    task set_qty;                  // up/down, 1 per press
        input integer q;
        integer k;
        begin
            focus_to(F_QTY);
            for (k = 0; k < 300 && u_dut.u_entry.qty != q; k = k + 1)
                press(q > u_dut.u_entry.qty ? K_UP : K_DOWN);
            if (u_dut.u_entry.qty != q) $display("NOTE: set_qty(%0d) stopped at %0d", q, u_dut.u_entry.qty);
        end
    endtask

    task set_trig;                 // up/down, 5 c per press
        input integer t;
        integer k;
        begin
            focus_to(F_TRG);
            for (k = 0; k < 3000 && u_dut.u_entry.trig != t; k = k + 1)
                press(t > u_dut.u_entry.trig ? K_UP : K_DOWN);
            if (u_dut.u_entry.trig != t) $display("NOTE: set_trig(%0d) stopped at %0d", t, u_dut.u_entry.trig);
        end
    endtask

    task submit;
        begin
            focus_to(F_SUB);
            press(K_CENTER);
        end
    endtask

    task send_ord;                 // what Matthew's confirm screen does
        input        sd;
        input integer q;
        begin
            ord_side = sd; ord_type = `OT_MKT; ord_qty = q; ord_trig = 0;
            ord_req = 1; step(1); ord_req = 0;
            settle;
        end
    endtask

    // one call to place an order through the UI
    task order;
        input        s;
        input [1:0]  t;
        input integer q;
        input integer tr;      // ignored for MKT
        begin
            set_side(s);
            set_type(t);
            set_qty(q);
            if (t != `OT_MKT) set_trig(tr);
            submit;
            settle;
        end
    endtask

    // ------------------------------------------------------------ scenarios
    integer b_fill, b_rej, b_cash, k, ask_now, fired, need;
    reg [9:0] b_pos0;

    task mark;
        begin
            b_fill = n_fill; b_rej = n_rej; b_cash = cash; b_pos0 = pos0;
        end
    endtask

    initial begin
        step(5);
        sys_reset = 0;
        step(5);

        // ------------------------------------------------ 1
        scenario("1 MKT BUY 10 at price 12300");
        set_price(0, 12300);
        mark;
        order(`SIDE_BUY, `OT_MKT, 10, 0);
        check(n_fill == b_fill + 1, "S1 one fill");
        check(f_stock[b_fill] == 0 && f_side[b_fill] == `SIDE_BUY && f_qty[b_fill] == 10, "S1 fill fields");
        check(f_price[b_fill] == 12305 && fill_fee == 100, "S1 fill at ask 12305, fee 100");
        check(cash == 876850 && pos0 == 10, "S1 cash 876,850 and pos0 10");

        // ------------------------------------------------ 2
        scenario("2 MKT BUY 255 costs more than cash");
        mark;
        order(`SIDE_BUY, `OT_MKT, 255, 0);
        check(n_rej == b_rej + 1 && last_rej == `RJ_NO_CASH, "S2 RJ_NO_CASH");
        check(n_fill == b_fill && cash == b_cash, "S2 no fill, cash unchanged");

        // ------------------------------------------------ 3
        scenario("3 MKT SELL 5 with position 0");
        set_stock(1);
        mark;
        order(`SIDE_SELL, `OT_MKT, 5, 0);
        check(n_rej == b_rej + 1 && last_rej == `RJ_NO_POS && n_fill == b_fill, "S3 RJ_NO_POS");

        // ------------------------------------------------ 4
        scenario("4 submit with qty 0");
        // The UI clamps qty to 1..255, so 0 cannot be dialled in:
        set_qty(2);
        repeat (3) press(K_DOWN);
        check(u_dut.u_entry.qty == 1, "S4 key_down below 1 clamps to 1");
        // ...so force the register to exercise the downstream path anyway.
        mark;
        force u_dut.u_entry.qty = 8'd0;
        submit; settle;
        release u_dut.u_entry.qty;
        check(n_rej == b_rej + 1 && last_rej == `RJ_BAD_QTY && n_fill == b_fill, "S4 RJ_BAD_QTY");

        // ------------------------------------------------ 5
        scenario("5 submit while game_state is not PLAYING");
        set_stock(0);
        game_state = `GS_MENU;
        mark;
        order(`SIDE_BUY, `OT_MKT, 1, 0);
        check(n_rej == b_rej + 1 && last_rej == `RJ_NOT_LIVE && n_fill == b_fill, "S5 RJ_NOT_LIVE");
        game_state = `GS_PLAYING;

        // ------------------------------------------------ 6
        scenario("6 LMT BUY 10 @ 12000, price ramps down");
        check(u_dut.u_entry.trig == 12300, "S6 stock change re-centred trig on 12300");
        mark;
        order(`SIDE_BUY, `OT_LMT, 10, 12000);
        check(pending_count == 1 && n_fill == b_fill && n_rej == b_rej, "S6 order resting in book");
        mkt_mode = 2;                                  // ramp down ~1 %/tick
        fired = 0;
        for (k = 0; k < 10 && !fired; k = k + 1) begin
            do_tick;
            ask_now = price0 + 5;
            step(100);
            if (ask_now <= 12000) begin
                fired = 1;
                check(n_fill == b_fill + 1, "S6 fills on first tick with ask <= 12000");
                check(f_price[b_fill] == ask_now && f_side[b_fill] == `SIDE_BUY, "S6 fills at that ask");
                $display("     filled at ask %0d after %0d ticks", ask_now, k + 1);
            end else begin
                check(n_fill == b_fill, "S6 no fill while ask > 12000");
            end
        end
        check(fired && pending_count == 0, "S6 triggered and slot cleared");
        mkt_mode = 0;
        settle;

        // ------------------------------------------------ 7
        scenario("7 STP SELL 10 @ 11000, price gaps 11500 -> 10500");
        set_price(0, 11500);
        mark;
        order(`SIDE_SELL, `OT_STP, 10, 11000);
        check(pending_count == 1, "S7 stop resting");
        do_tick; step(100);
        check(n_fill == b_fill, "S7 no fill at 11500");
        set_price(0, 10500);
        do_tick; settle;
        check(n_fill == b_fill + 1 && f_price[b_fill] == 10495 && f_side[b_fill] == `SIDE_SELL
              && f_qty[b_fill] == 10, "S7 fills at bid 10495 (gap slippage)");
        check(pending_count == 0 && pos0 == b_pos0 - 10, "S7 slot cleared, pos0 down 10");

        // ------------------------------------------------ 9
        scenario("9 three slots trigger on the same tick");
        set_price(0, 11500);
        mark;
        order(`SIDE_BUY, `OT_LMT, 1, 11000);
        order(`SIDE_BUY, `OT_LMT, 2, 11000);
        order(`SIDE_BUY, `OT_LMT, 3, 11000);
        check(pending_count == 3 && n_fill == b_fill, "S9 three resting");
        set_price(0, 10900);                           // ask 10905
        do_tick; settle;
        check(n_fill == b_fill + 3, "S9 three fills");
        check(f_qty[b_fill] == 1 && f_qty[b_fill+1] == 2 && f_qty[b_fill+2] == 3, "S9 in slot order");
        check(f_time[b_fill+1] - f_time[b_fill] > 400 && f_time[b_fill+2] - f_time[b_fill+1] > 400,
              "S9 each fill waited for ledger_busy to drop");
        check(pending_count == 0, "S9 book empty");

        // ------------------------------------------------ 10
        scenario("10 pending LMT BUY triggers after cash was spent");
        set_price(0, 11500);
        mark;
        need = 60 * 11000 + 100;
        check(cash >= need, "S10 precondition: affordable at submit");
        order(`SIDE_BUY, `OT_LMT, 60, 11000);
        check(pending_count == 1, "S10 resting");
        set_stock(3);                                  // MEM, ask 12.35
        order(`SIDE_BUY, `OT_MKT, 255, 0);             // spend ~315k
        set_stock(0);
        need = 60 * 10905 + 100;
        check(cash < need, "S10 precondition: no longer affordable at 10905");
        mark;
        set_price(0, 10900);
        do_tick; settle;
        check(n_rej == b_rej + 1 && last_rej == `RJ_TRIG_FAIL, "S10 RJ_TRIG_FAIL");
        check(n_fill == b_fill && pos0 == b_pos0 && pending_count == 0, "S10 no fill, slot cleared");

        // ------------------------------------------------ 11
        scenario("11 SELL, type to STP, SUBMIT (buttons)");
        set_type(`OT_MKT);
        set_qty(5);
        set_trig(10000);                               // below bid, so it rests
        page_R = `PG_R_PORTFOLIO;                      // Portfolio page showing: buttons ignored
        press(K_CENTER);                               // focus is trig: would cycle MKT -> LMT
        press(K_LEFT);                                 // would move focus to qty
        page_R = `PG_R_TICKET;
        check(u_dut.u_entry.focus == 1 && u_dut.u_entry.otype == `OT_MKT, "S11 buttons ignored on Portfolio page");
        mark;
        focus_to(F_QTY); press(K_CENTER);                  // qty field: BUY -> SELL
        focus_to(F_TRG); press(K_CENTER); press(K_CENTER); // trig field: MKT -> LMT -> STP
        submit; settle;
        check(u_dut.u_entry.side == `SIDE_SELL && u_dut.u_entry.otype == `OT_STP, "S11 side SELL, type STP");
        check(pending_count == 1 && u_dut.u_book.valid[0] && u_dut.u_book.s_side[0] == `SIDE_SELL
              && u_dut.u_book.s_type[0] == `OT_STP && u_dut.u_book.s_qty[0] == 5
              && u_dut.u_book.s_trig[0] == 10000, "S11 STP SELL 5 @ 100.00 in slot 0");
        check(n_fill == b_fill && n_rej == b_rej, "S11 no fill or reject");

        // ------------------------------------------------ 12
        scenario("12 qty +3 with key_up, clamped at 255");
        set_qty(10);
        repeat (3) press(K_UP);
        check(u_dut.u_entry.qty == 13, "S12 qty 10 -> 13");
        set_qty(254);
        repeat (3) press(K_UP);
        check(u_dut.u_entry.qty == 255, "S12 qty 254 -> 255 (clamped)");
        press(K_DOWN);
        check(u_dut.u_entry.qty == 254, "S12 key_down -> 254");
        press(K_RIGHT); press(K_UP);                   // focus trig, +5c
        check(u_dut.u_entry.focus == 1 && u_dut.u_entry.trig == 10005, "S12 key_right, key_up on trig");
        press(K_LEFT);
        check(u_dut.u_entry.focus == 0, "S12 key_left back to qty");

        // ------------------------------------------------ 8
        scenario("8 nine pending orders");
        set_side(`SIDE_BUY);
        set_type(`OT_LMT);
        set_qty(1);
        set_trig(100);                                 // $1.00, far below market
        mark;
        for (k = 0; k < 8 && pending_count < 8; k = k + 1) begin
            submit; settle;
        end
        check(pending_count == 8 && n_rej == b_rej, "S8 book fills to 8 without rejects");
        submit; settle;
        check(n_rej == b_rej + 1 && last_rej == `RJ_BOOK_FULL && pending_count == 8, "S8 9th -> RJ_BOOK_FULL");

        // ------------------------------------------------ 13
        scenario("13 reset in the middle of a scan");
        set_price(0, 90);                              // ask 95: all 8 orders trigger
        mark;
        do_tick;
        wait (n_fill == b_fill + 1);                   // first fill out, rest queued
        step(5);
        sys_reset = 1; step(2); sys_reset = 0;         // global reset: order engine and ledger
        check(pending_count == 0, "S13 book cleared");
        check(u_dut.u_book.state == 0 && u_dut.u_exec.state == 0 && !u_dut.u_book.trq,
              "S13 book and exec FSMs idle");
        b_fill = n_fill; b_rej = n_rej;
        step(1000);
        check(n_fill == b_fill && n_rej == b_rej, "S13 no stray fill or reject after reset");
        check(cash == 1000000 && u_dut.u_entry.qty == 1 && u_dut.u_entry.otype == `OT_MKT,
              "S13 ledger and ticket back to defaults");

        // ------------------------------------------------ 14
        scenario("14 order from Matthew's confirm screen (ord_req)");
        set_stock(0); set_price(0, 12300);
        page_R = `PG_R_PORTFOLIO;                      // Matthew owns the buttons: the order engine's own entry is off
        mark;
        send_ord(`SIDE_BUY, 7);
        check(n_fill == b_fill + 1 && f_qty[b_fill] == 7 && f_side[b_fill] == `SIDE_BUY
              && f_price[b_fill] == 12305 && pos0 == 7, "S14 ord_req MKT BUY 7 fills at the ask");
        check(u_dut.u_entry.qty == 7 && u_dut.u_entry.side == `SIDE_BUY, "S14 ticket shows the order Matthew sent");
        mark;
        send_ord(`SIDE_SELL, 3);
        check(n_fill == b_fill + 1 && f_side[b_fill] == `SIDE_SELL && pos0 == 4, "S14 ord_req SELL 3");
        mark;
        send_ord(`SIDE_BUY, 300);
        check(n_rej == b_rej + 1 && last_rej == `RJ_BAD_QTY && n_fill == b_fill, "S14 qty 300 (> 255) -> RJ_BAD_QTY");
        send_ord(`SIDE_BUY, 0);
        check(n_rej == b_rej + 2 && last_rej == `RJ_BAD_QTY && n_fill == b_fill, "S14 qty 0 -> RJ_BAD_QTY");
        page_R = `PG_R_TICKET;

        // ------------------------------------------------ 15
        scenario("15 stock with no price is closed");
        set_price(2, 0);
        set_stock(2);
        mark;
        order(`SIDE_BUY, `OT_MKT, 1, 0);
        check(n_rej == b_rej + 1 && last_rej == `RJ_NOT_LIVE && n_fill == b_fill, "S15 MKT buy on a 0 price -> RJ_NOT_LIVE");
        set_stock(0);

        // ------------------------------------------------ 16
        scenario("16 MKT BUY 10 with SL/TP 5%, then the stop-loss fills");
        set_stock(0); set_price(0, 10000);
        set_brk(`BRK_5);
        check(u_dut.u_entry.brk == `BRK_5, "S16 SL/TP field set to 5% with the buttons");
        mark;
        order(`SIDE_BUY, `OT_MKT, 10, 0);
        // fill at ask 100.05; distance 10005 * 3280 >> 16 = 500 -> SL 95.05, TP 105.05
        check(n_fill == b_fill + 1 && f_price[b_fill] == 10005, "S16 buy fills at 100.05");
        check(pending_count == 2, "S16 SL/TP pair placed");
        check(u_dut.u_book.s_type[0] == `OT_STP && u_dut.u_book.s_side[0] == `SIDE_SELL
              && u_dut.u_book.s_qty[0] == 10 && u_dut.u_book.s_trig[0] == 9505, "S16 slot 0: stop-loss STP SELL 10 @ 95.05");
        check(u_dut.u_book.s_type[1] == `OT_LMT && u_dut.u_book.s_side[1] == `SIDE_SELL
              && u_dut.u_book.s_qty[1] == 10 && u_dut.u_book.s_trig[1] == 10505, "S16 slot 1: take-profit LMT SELL 10 @ 105.05");
        b_pos0 = pos0;
        mark;
        set_price(0, 9510);                            // bid 95.05: stop-loss
        do_tick; settle;
        check(n_fill == b_fill + 1 && f_side[b_fill] == `SIDE_SELL && f_qty[b_fill] == 10
              && f_price[b_fill] == 9505, "S16 stop-loss sells 10 at 95.05");
        check(pending_count == 0 && pos0 == b_pos0 - 10, "S16 take-profit cancelled with it, position closed");

        // ------------------------------------------------ 17
        scenario("17 SL/TP again, this time the take-profit fills");
        set_price(0, 10000);
        mark;
        order(`SIDE_BUY, `OT_MKT, 10, 0);
        check(pending_count == 2, "S17 pair placed");
        mark;
        set_price(0, 10510);                           // bid 105.05: take-profit
        do_tick; settle;
        check(n_fill == b_fill + 1 && f_side[b_fill] == `SIDE_SELL && f_price[b_fill] == 10505, "S17 take-profit sells at 105.05");
        check(pending_count == 0, "S17 stop-loss cancelled with it");
        do_tick; settle;
        check(n_fill == b_fill + 1, "S17 nothing else fills on the next tick");

        // ------------------------------------------------ 18
        scenario("18 cancel pending orders from the ORDERS view");
        set_brk(`BRK_OFF);
        order(`SIDE_BUY, `OT_LMT, 1, 5000);           // slot 0
        order(`SIDE_BUY, `OT_LMT, 2, 5000);           // slot 1
        check(pending_count == 2, "S18 two orders resting");
        mark;
        cancel_slot(1);
        check(pending_count == 1 && u_dut.u_book.valid[0] && !u_dut.u_book.valid[1]
              && u_dut.u_book.s_qty[0] == 1, "S18 slot 1 cancelled, slot 0 kept");
        cancel_slot(1);                                // empty slot: nothing happens
        check(pending_count == 1 && n_rej == b_rej, "S18 cancelling an empty slot does nothing");
        press(K_UP);                                   // cursor to slot 0
        press(K_CENTER); step(3);
        check(pending_count == 0 && n_fill == b_fill && n_rej == b_rej, "S18 slot 0 cancelled, no fill or reject");

        // ------------------------------------------------ 19
        scenario("19 SL/TP 2% on a pending LMT BUY");
        set_price(0, 10000);
        set_brk(`BRK_2);
        mark;
        order(`SIDE_BUY, `OT_LMT, 4, 9000);
        check(pending_count == 1 && n_fill == b_fill, "S19 limit buy resting");
        set_price(0, 8990);                            // ask 89.95 <= 90.00
        do_tick; settle;
        // fill at 89.95; distance 8995 * 1312 >> 16 = 180 -> SL 88.15, TP 91.75
        check(n_fill == b_fill + 1 && f_price[b_fill] == 8995, "S19 limit buy fills at 89.95");
        check(pending_count == 2 && u_dut.u_book.s_trig[0] == 8815 && u_dut.u_book.s_trig[1] == 9175,
              "S19 pair placed: SL 88.15 (reuses the buy's slot), TP 91.75");
        mark;
        cancel_slot(0);                                // cancel the stop-loss...
        check(pending_count == 0 && n_fill == b_fill, "S19 ...and the take-profit goes with it");

        // ------------------------------------------------ 20
        scenario("20 the ticket picks its own stock");
        set_brk(`BRK_OFF);
        focus_to(F_STK);
        press(K_UP);                                   // AMD -> MCD
        check(u_dut.u_entry.stock == 1 && sel_stock == 0, "S20 ticket on MCD, Matthew's selection still AMD");
        check(u_dut.u_entry.trig == 4520, "S20 trig re-centred on MCD's price");
        mark;
        order(`SIDE_BUY, `OT_MKT, 3, 0);
        check(n_fill == b_fill + 1 && f_stock[b_fill] == 1 && f_price[b_fill] == 4525 && pos1 == 3,
              "S20 MKT BUY 3 MCD at 45.25");
        set_stock(2);
        check(u_dut.u_entry.stock == 2, "S20 Matthew picking a stock moves the ticket to it");
        focus_to(F_STK); press(K_DOWN); press(K_DOWN); press(K_DOWN);
        check(u_dut.u_entry.stock == 3, "S20 down wraps 2 -> 1 -> 0 -> 3");
        set_stock(0);

        // ------------------------------------------------ 21
        scenario("21 Matthew's market order with SL/TP 10% (ord_brk)");
        set_price(0, 10000);
        set_brk(`BRK_OFF);                             // the ticket's own setting is not used
        page_R = `PG_R_PORTFOLIO;
        mark;
        ord_brk = `BRK_10;
        send_ord(`SIDE_BUY, 2);
        ord_brk = `BRK_OFF;
        // fill at 100.05; distance 10005 * 6560 >> 16 = 1001 -> SL 90.04, TP 110.06
        check(n_fill == b_fill + 1 && pending_count == 2, "S21 buy fills, pair placed");
        check(u_dut.u_book.s_trig[0] == 9004 && u_dut.u_book.s_trig[1] == 11006, "S21 SL 90.04, TP 110.06");
        page_R = `PG_R_TICKET;

        // ------------------------------------------------ done
        $display("     final cash %0d, pos %0d/%0d/%0d/%0d, %0d fills, %0d rejects",
                 cash, pos0, pos1, pos2, pos3, n_fill, n_rej);
        if (n_fail == 0) $display("PASS: tb_B_order_top (%0d checks)", n_pass);
        else             $display("FAIL: tb_B_order_top (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL: tb_B_order_top timeout");
        $finish;
    end
endmodule
