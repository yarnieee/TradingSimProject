`timescale 1ns / 1ps
`include "trading_defs.vh"
`include "ticket_layout.vh"

// tb_B_order_top: spec section 10 scenarios, end to end, through the real UI
// path (clicks, scroll, buttons) with stub_market and stub_ledger standing in
// for A and C. stub_ledger stops the sim with FAIL if cash or a position ever
// goes out of range, or if a fill arrives while ledger_busy.
//
// Run order is 1-7, 9-12, 8, 13 so the book is empty where a scenario needs
// it: scenario 8 fills the book, and 13 (reset mid-scan) is what clears it.
module tb_B_order_top;
    reg clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------ stimulus
    reg        sys_reset = 1;
    reg [1:0]  game_state = `GS_PLAYING;
    reg [1:0]  sel_stock = 0;
    reg        page_R = `PG_R_TICKET;
    reg        ui_click = 0;
    reg [1:0]  ui_screen = `SCR_RIGHT;
    reg [6:0]  ui_x = 0;
    reg [5:0]  ui_y = 0;
    reg [3:0]  qty_delta = 0;
    reg [4:0]  btn_pulse = 0;
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
        .ui_click(ui_click), .ui_screen(ui_screen), .ui_x(ui_x), .ui_y(ui_y),
        .qty_delta(qty_delta), .btn_pulse(btn_pulse),
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

    task click;
        input [6:0] x;
        input [5:0] y;
        begin
            ui_x = x; ui_y = y; ui_screen = `SCR_RIGHT;
            ui_click = 1; step(1); ui_click = 0; step(2);
        end
    endtask

    task scroll;
        input integer n;    // -8..7
        begin
            qty_delta = n; step(1); qty_delta = 0; step(2);   // non-zero for one clock
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
    // centre of a layout box
    `define CX(a, b) (((a) + (b)) / 2)

    task set_side;
        input s;
        begin
            if (s == `SIDE_BUY) click(`CX(`TK_BUY_X0, `TK_BUY_X1),   `CX(`TK_BTN_Y0, `TK_BTN_Y1));
            else                click(`CX(`TK_SELL_X0, `TK_SELL_X1), `CX(`TK_BTN_Y0, `TK_BTN_Y1));
        end
    endtask

    task set_type;
        input [1:0] t;
        integer k;
        begin
            for (k = 0; k < 3 && u_dut.u_entry.otype != t; k = k + 1)
                click(`CX(`TK_TYPE_X0, `TK_TYPE_X1), `CX(`TK_BTN_Y0, `TK_BTN_Y1));
        end
    endtask

    // focus qty with the [+] button, then scroll to the target
    task set_qty;
        input integer q;
        integer d, k;
        begin
            click(`CX(`TK_PLUS_X0, `TK_PLUS_X1), `CX(`TK_QTY_Y0, `TK_QTY_Y1));
            for (k = 0; k < 100 && u_dut.u_entry.qty != q; k = k + 1) begin
                d = q - u_dut.u_entry.qty;
                if (d > 7)  d = 7;
                if (d < -8) d = -8;
                scroll(d);
            end
            if (u_dut.u_entry.qty != q) $display("NOTE: set_qty(%0d) stopped at %0d", q, u_dut.u_entry.qty);
        end
    endtask

    // focus trig with the [+] button, then scroll (5 c per notch) to the target
    task set_trig;
        input integer t;
        integer d, k;
        begin
            click(`CX(`TK_PLUS_X0, `TK_PLUS_X1), `CX(`TK_TRG_Y0, `TK_TRG_Y1));
            for (k = 0; k < 2000 && u_dut.u_entry.trig != t; k = k + 1) begin
                d = t - u_dut.u_entry.trig;    // signed difference first,
                d = d / 5;                     // then divide (unsigned divide otherwise)
                if (d > 7)  d = 7;
                if (d < -8) d = -8;
                if (d == 0) k = 2000;
                else        scroll(d);
            end
            if (u_dut.u_entry.trig != t) $display("NOTE: set_trig(%0d) stopped at %0d", t, u_dut.u_entry.trig);
        end
    endtask

    task submit;
        begin
            click(`CX(`TK_SUB_X0, `TK_SUB_X1), `CX(`TK_SUB_Y0, `TK_SUB_Y1));
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
        set_qty(5);
        scroll(-8);
        check(u_dut.u_entry.qty == 1, "S4 scroll below 1 clamps to 1");
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
        scenario("11 click SELL, TYPE twice, SUBMIT");
        set_type(`OT_MKT);
        set_qty(5);
        set_trig(10000);                               // below bid, so it rests
        click(`CX(`TK_SELL_X0, `TK_SELL_X1), 6'd0);   // y = 0: off the ticket, no effect
        ui_screen = `SCR_LEFT;                         // left OLED: ignored
        ui_x = `CX(`TK_SELL_X0, `TK_SELL_X1); ui_y = `CX(`TK_BTN_Y0, `TK_BTN_Y1);
        ui_click = 1; step(1); ui_click = 0; step(2); ui_screen = `SCR_RIGHT;
        page_R = `PG_R_PORTFOLIO;                      // Portfolio page showing: ignored
        click(`CX(`TK_SELL_X0, `TK_SELL_X1), `CX(`TK_BTN_Y0, `TK_BTN_Y1));
        press(K_CENTER);                               // focus is trig: would cycle MKT -> LMT
        page_R = `PG_R_TICKET;
        check(u_dut.u_entry.side == `SIDE_BUY, "S11 off-ticket, left-screen and Portfolio-page clicks ignored");
        check(u_dut.u_entry.focus == 1 && u_dut.u_entry.otype == `OT_MKT, "S11 button ignored on Portfolio page");
        mark;
        click(`CX(`TK_SELL_X0, `TK_SELL_X1), `CX(`TK_BTN_Y0, `TK_BTN_Y1));
        click(`CX(`TK_TYPE_X0, `TK_TYPE_X1), `CX(`TK_BTN_Y0, `TK_BTN_Y1));
        click(`CX(`TK_TYPE_X0, `TK_TYPE_X1), `CX(`TK_BTN_Y0, `TK_BTN_Y1));
        submit; settle;
        check(u_dut.u_entry.side == `SIDE_SELL && u_dut.u_entry.otype == `OT_STP, "S11 side SELL, type STP");
        check(pending_count == 1 && u_dut.u_book.valid[0] && u_dut.u_book.s_side[0] == `SIDE_SELL
              && u_dut.u_book.s_type[0] == `OT_STP && u_dut.u_book.s_qty[0] == 5
              && u_dut.u_book.s_trig[0] == 10000, "S11 STP SELL 5 @ 100.00 in slot 0");
        check(n_fill == b_fill && n_rej == b_rej, "S11 no fill or reject");

        // ------------------------------------------------ 12
        scenario("12 scroll +3 with focus on qty");
        set_qty(10);
        scroll(3);
        check(u_dut.u_entry.qty == 13, "S12 qty 10 -> 13");
        set_qty(254);
        scroll(3);
        check(u_dut.u_entry.qty == 255, "S12 qty 254 -> 255 (clamped)");
        // button fallback on the same field
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
        sys_reset = 1; step(2); sys_reset = 0;         // global reset: B and the ledger
        check(pending_count == 0, "S13 book cleared");
        check(u_dut.u_book.state == 0 && u_dut.u_exec.state == 0 && !u_dut.u_book.trq,
              "S13 book and exec FSMs idle");
        b_fill = n_fill; b_rej = n_rej;
        step(1000);
        check(n_fill == b_fill && n_rej == b_rej, "S13 no stray fill or reject after reset");
        check(cash == 1000000 && u_dut.u_entry.qty == 1 && u_dut.u_entry.otype == `OT_MKT,
              "S13 ledger and ticket back to defaults");

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
