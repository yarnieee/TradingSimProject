`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_integration: plays the game on Integration_Top with raw button presses,
// through Matthew's screens, and checks that the orders land in Douglas's and Tricia's parts correctly.
// Only two times are shrunk: a trading day is 4000 clocks (not 2 s) and the
// debounce is 50 clocks (not 20 ms). Every module is the owner's own code.
//
// Yi An's seed files are pointed at by name in Integration_Top (defparam).
module tb_integration;
    reg clk = 0;
    always #5 clk = ~clk;

    reg  rst = 1;
    reg  btnU = 0, btnD = 0, btnL = 0, btnR = 0, btnC = 0;
    reg  [5:0] order_sw = 6'd0;     // sw[7:2]: type, SL/TP, trigger distance
    reg  view_sw = 0;               // sw[15]: bot view
    reg  orders_sw = 0;             // sw[14]: the ORDERS list on the left OLED
    wire [7:0]  JA, JB, seg;
    wire [15:0] led;
    wire [3:0]  an;

    localparam DAY = 4000;
    Integration_Top #(.DAY_MAX_COUNT(DAY), .DEBOUNCE_CTR(32'd50), .SOUND_SAMPLE_SHIFT(4)) dut (
        .clk(clk), .rst(rst), .order_sw(order_sw), .view_sw(view_sw), .orders_sw(orders_sw), .mute_sw(1'b0),
        .btnU(btnU), .btnD(btnD), .btnL(btnL), .btnR(btnR), .btnC(btnC),
        .JA(JA), .JB(JB), .led(led), .an(an), .seg(seg)
    );

    // game_fsm screens
    localparam S_TITLE = `UI_TITLE, S_PORTFOLIO = `UI_PORTFOLIO,
               S_STOCKS = `UI_STOCKS, S_SPECIFIC = `UI_SPECIFIC,
               S_BUY = `UI_BUY_STOCK, S_SELL = `UI_SELL_STOCK,
               S_QUANTITY = `UI_QUANTITY, S_ORDER_REVIEW = `UI_ORDER_REVIEW,
               S_ORDER_RESULT = `UI_ORDER_RESULT, S_TRADE_RESULT = `UI_TRADE_RESULT;

    integer n_pass = 0, n_fail = 0;
    task check;
        input          cond;
        input [8*72:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s (t=%0t)", name, $time); end
        end
    endtask

    integer n_fill = 0, n_rej = 0, n_err = 0, n_tick = 0, n_ord_req = 0;
    reg [2:0]  last_rej = 0;
    reg [15:0] last_px = 0;
    always @(posedge clk) if (!dut.sys_reset) begin
        if (dut.fill)       begin n_fill = n_fill + 1; last_px = dut.fill_price; end
        if (dut.reject)     begin n_rej = n_rej + 1; last_rej = dut.reject_code; end
        if (dut.ledger_err) n_err = n_err + 1;
        if (dut.tick)       n_tick = n_tick + 1;
        if (dut.ord_req)    n_ord_req = n_ord_req + 1;
    end
    // bot_squad's trades; after each open / close: OVERNIGHT holds nothing in the day,
    // MOMENTUM (bot 1) never trades at a close
    integer n_squad = 0, n_close = 0, bad_night = 0, bad_day = 0, q;
    always @(posedge clk) if (!dut.sys_reset) begin
        if (dut.squad_trade) n_squad = n_squad + 1;
        if (dut.close_tick)  n_close = n_close + 1;
    end
    always @(posedge dut.tick) begin
        repeat (400) @(posedge clk);
        for (q = 0; q < 4; q = q + 1) if (dut.bots.pos_m[q] != 0) bad_night = bad_night + 1;
    end
    // (a day here is 4000 clocks with the close at 3600: look before the next open)
    integer w;
    always @(posedge dut.close_tick) begin
        for (w = 0; w < 200 && !dut.tick; w = w + 1) begin
            @(posedge clk); if (dut.squad_trade && dut.squad_bot == 2'd1) bad_day = bad_day + 1; end
    end
    // the progress bar colour follows the days left (one clock later): green, then
    // yellow from 60 days left, red from 10; and each colour is seen in a game
    integer bad_bar = 0, saw_g = 0, saw_y = 0, saw_r = 0;
    reg [31:0] tr_d;
    always @(posedge clk) begin
        if (!dut.sys_reset && tr_d == dut.time_remaining) begin
            if (dut.matthew_display.bar_level !== ((tr_d <= 10) ? 2'd3 : (tr_d <= 60) ? 2'd1 : 2'd0))
                bad_bar = bad_bar + 1;
            if (dut.matthew_display.bar_level == 2'd0) saw_g = 1;
            if (dut.matthew_display.bar_level == 2'd1) saw_y = 1;
            if (dut.matthew_display.bar_level == 2'd3) saw_r = 1;
        end
        tr_d <= dut.time_remaining;
    end

    // sounds heard during the game (B_sound_top's now_playing: 1 click .. 5 game end),
    // and whether a bell ever came straight after a woosh
    integer saw_snd [0:5];
    integer woosh_bell = 0;
    reg [2:0] snd_d = 3'd0;
    initial for (q = 0; q < 6; q = q + 1) saw_snd[q] = 0;
    always @(posedge clk) begin
        if (dut.sound_now != snd_d) begin
            saw_snd[dut.sound_now] = saw_snd[dut.sound_now] + 1;
            if (snd_d == 3'd3 && dut.sound_now == 3'd4) woosh_bell = woosh_bell + 1;
        end
        snd_d <= dut.sound_now;
    end

    // the six places are 1..6, each once
    function places_ok;
        input [17:0] r;
        integer e, f, seen;
        begin
            seen = 0;
            for (e = 0; e < 6; e = e + 1) seen = seen | (1 << r[3*e +: 3]);
            places_ok = (seen == 7'b1111110);
        end
    endfunction

    // order lists the same standing 1st to 6th
    function order_ok;
        input [17:0] r, o;
        integer p;
        begin
            order_ok = 1;
            for (p = 0; p < 6; p = p + 1) if (r[3*o[3*p +: 3] +: 3] != p + 1) order_ok = 0;
        end
    endfunction

    // one press, held long enough for the debouncer (50 clocks)
    task press;
        input integer b;      // 0 U, 1 D, 2 L, 3 R, 4 C
        begin
            case (b) 0: btnU = 1; 1: btnD = 1; 2: btnL = 1; 3: btnR = 1; default: btnC = 1; endcase
            repeat (80) @(posedge clk);
            btnU = 0; btnD = 0; btnL = 0; btnR = 0; btnC = 0;
            repeat (80) @(posedge clk);
        end
    endtask
    localparam U = 0, D = 1, L = 2, R = 3, C = 4;

    // place an order through Matthew's screens, starting from PORTFOLIO
    task trade;
        input integer stock;   // 0=AMD, 1=MCD
        input         sell;
        input integer qty;     // 0..9 (ones digit only, enough here)
        integer k;
        begin
            press(R); press(C);                         // portfolio -> stocks (Stocks selected)
            for (k = 0; k <= stock; k = k + 1) press(D); // Stocks -> selected stock
            press(C);                                   // -> specific
            if (sell) press(R);                         // sell instead of buy
            press(C);                                   // -> buy / sell screen
            press(R); press(C);                         // "quantity" -> quantity screen (qty 0)
            for (k = 0; k < qty; k = k + 1) press(U);   // ones digit
            press(C);                                   // back to buy / sell screen (cursor 0)
            press(R); press(R); press(C);               // -> ORDER_REVIEW
            press(C);                                   // review -> ORDER_RESULT: submit to B
            repeat (300) @(posedge clk);                // Douglas -> Tricia: fill and ledger update
        end
    endtask

    integer cash0, f0, r0, o0;
    reg [15:0] p0;
    reg [31:0] seed1;
    reg [63:0] px1;
    integer    t_new;
    reg [3:0]  m0;

    initial begin
        repeat (10) @(posedge clk);
        rst = 0;
        // ---------------- title: the market waits for the player
        repeat (2 * DAY + 1234) @(posedge clk);
        check(n_tick == 0 && dut.trading_day_count == 0 && !dut.amd_ready,
              "the market does not start on the title screen");
        press(C);
        check(dut.screen_state == S_PORTFOLIO, "Matthew: title -> portfolio");
        check(dut.time_remaining == 120, "the game starts with all its days");
        wait (dut.amd_ready && dut.mcd_ready && dut.stock2_ready && dut.stock3_ready);
        seed1 = dut.yian_market.startup_random_seed;
        repeat (DAY + 100) @(posedge clk);              // one day ticks over
        check(dut.price0 != 0 && dut.price1 != 0 && dut.price2 != 0 && dut.price3 != 0,
              "Yi An: all four stocks have prices (if not: a seed file was not found)");
        check(dut.price0 == dut.amd_close && dut.price1 == dut.mcd_close
              && dut.price2 == dut.stock2_close && dut.price3 == dut.stock3_close,
              "Integration: all four prices are routed into the shared order bus");
        check(n_tick >= 1, "Yi An -> Douglas: a tick reached the order engine after a trading day");
        check(dut.portfolio_value == 32'd1_000_000,
              "Display data path: portfolio starts at the ledger's cash value");
        check(dut.portfolio_samples_30[31:0] == dut.portfolio_value,
              "Display data path: portfolio history is initialized");
        $display("     AMD %0d c, MCD %0d c, NVDA %0d c, GME %0d c",
                 dut.price0, dut.price1, dut.price2, dut.price3);
        // Yi An's own price maths (stock.v, calculate_next_close), reported but not counted
        if (dut.price0 == 16'hFFFF || dut.price1 == 16'hFFFF
            || dut.price2 == 16'hFFFF || dut.price3 == 16'hFFFF
            || dut.price0 < 100 || dut.price1 < 100
            || dut.price2 < 100 || dut.price3 < 100)
            $display("WARN: Yi An's prices look wrong (pinned at $655.35 or near 0): see stock.v, calculate_next_close");

        px1 = {dut.price0, dut.price1, dut.price2, dut.price3};   // after the first day

        // ---------------- buy 3 AMD
        cash0 = dut.cash; f0 = n_fill; o0 = n_ord_req; p0 = dut.price0;
        trade(0, 0, 3);
        check(dut.sel_stock == 0, "Matthew -> Douglas: AMD selected");
        check(n_ord_req == o0 + 1, "valid buy generates one order request");
        check(n_fill == f0 + 1 && dut.pos0 == 3, "Douglas -> Tricia: buy 3 AMD filled, position 3");
        check(dut.cash == cash0 - 3 * last_px - 100, "Tricia: cash down by 3 x ask + fee");
        check(last_px == dut.douglas_orders.u_exec.u_spread.ask || last_px == ((p0 > 16'd65530) ? 16'hFFFF : p0 + 16'd5),
              "Douglas: filled at the ask (price + 5 c, saturating)");
        check(dut.screen_state == S_TRADE_RESULT, "Matthew: on the trade-result screen");
        press(C);                                       // trade result -> portfolio

        // ---------------- sell 2 MCD with none held: rejected by B, never reaches C
        f0 = n_fill; r0 = n_rej; o0 = n_ord_req;
        trade(1, 1, 2);
        check(dut.sel_stock == 1, "Matthew -> Douglas: MCD selected");
        check(n_rej == r0 && n_fill == f0 && n_ord_req == o0
              && dut.screen_state == S_TRADE_RESULT,
              "validation: sell MCD with none held -> NO POS before submission");
        press(C);

        // ---------------- quantity 0 (confirm without setting it)
        r0 = n_rej; o0 = n_ord_req;
        trade(0, 0, 0);
        check(n_rej == r0 && n_ord_req == o0 && dut.screen_state == S_TRADE_RESULT,
              "validation: quantity 0 -> BAD QTY before submission");
        press(C);

        // ---------------- sell 1 AMD back: partial sell through Tricia's divider
        f0 = n_fill; o0 = n_ord_req;
        trade(0, 1, 1);
        check(n_fill == f0 + 1 && n_ord_req == o0 + 1 && dut.pos0 == 2,
              "valid sell generates one order and updates AMD position to 2");
        check(dut.cash + dut.tricia_portfolio.cb0 + dut.tricia_portfolio.cb1
              + dut.tricia_portfolio.cb2 + dut.tricia_portfolio.cb3 == 32'd1_000_000 + dut.realised,
              "Tricia: ledger invariant holds");

        // ---------------- limit buy 2 AMD 5% below the market, SL/TP 5%, set on the switches
        press(C);                                       // trade result -> portfolio
        order_sw = {2'b10, 2'b10, 2'b01};               // sw[7:6] 5%, sw[5:4] SL/TP 5%, sw[3:2] LMT
        o0 = n_ord_req; f0 = n_fill;
        trade(0, 0, 2);
        check(n_ord_req == o0 + 1 && n_fill == f0 && dut.pending_count == 4'd1,
              "switches: the limit buy rests in the book (no fill)");
        check(dut.screen_state == S_TRADE_RESULT && dut.matthew_display.trade_result_placed,
              "Matthew's unchanged FSM reaches the trade result; the screen says PLACED");
        check(dut.douglas_orders.u_book.s_type[0] == `OT_LMT && dut.douglas_orders.u_book.s_brk[0] == `BRK_5,
              "Douglas: book holds a LMT with SL/TP 5%");
        check(dut.douglas_orders.u_book.s_trig[0] < dut.price0 &&
              dut.douglas_orders.u_book.s_trig[0] > dut.price0 - dut.price0 / 16,
              "switches: limit buy trigger is about 5% below the price");
        order_sw = 6'd0;
        press(C);

        // ---------------- sw14 up: the left OLED's ORDERS list; BTNC cancels the chosen order
        check(dut.douglas_orders.e_focus == 3'd7, "the ticket shows no button focus in the full game");
        orders_sw = 1;
        repeat (5) @(posedge clk);
        check(dut.douglas_orders.e_focus == 3'd4, "sw14 up: the left OLED shows the ORDERS list");
        m0 = dut.matthew_display.menu_selection;
        press(D); press(L); press(R); press(U);     // cursor down, left / right ignored, back up to the order
        check(dut.douglas_orders.e_focus == 3'd4 && dut.douglas_orders.e_ord_sel == 3'd0,
              "sw14 up: BTNU / BTND move the cursor, BTNL / BTNR do nothing");
        press(C);
        check(dut.pending_count == 4'd0, "sw14 up: BTNC cancels the chosen pending order");
        check(dut.screen_state == S_PORTFOLIO && dut.matthew_display.menu_selection == m0,
              "sw14 up: the game ignores the buttons");
        orders_sw = 0;
        repeat (5) @(posedge clk);
        check(dut.douglas_orders.e_focus == 3'd7, "sw14 down: the left OLED shows the ticket again");

        // ---------------- Tricia's bot trades on its own; sw[15] shows it, buttons ignored there
        repeat (6 * DAY) @(posedge clk);               // a few more trading days
        check(dut.tricia_portfolio.bot_err == 1'b0, "Tricia: the bot's ledger never rejected a bot fill");
        check(dut.bot_cash + dut.tricia_portfolio.bcb0 + dut.tricia_portfolio.bcb1
              + dut.tricia_portfolio.bcb2 + dut.tricia_portfolio.bcb3 == 32'd1_000_000 + dut.bot_realised,
              "Tricia: the bot's ledger balances (cash + cost basis = start + realised)");
        check(dut.bot_trades == 0 || dut.bot_log_valid[0],
              "the bot's trade log fills as it trades");
        $display("     bot: %0d trades, cash %0d c, equity %0d c", dut.bot_trades, dut.bot_cash, dut.bot_equity);
        view_sw = 1;
        repeat (5) @(posedge clk);
        check(dut.matthew_display.pixel_data_L == dut.matthew_display.bot_log_pixel,
              "sw15 up: left OLED shows the bot's trades");
        press(R); press(C);
        check(dut.screen_state == S_PORTFOLIO, "sw15 up: buttons are ignored");
        check(dut.bot_sel == 3'd1, "sw15 up: BTNR chooses the next bot (OVERNIGHT)");
        press(L); press(L);
        check(dut.bot_sel == 3'd4, "sw15 up: BTNL goes back, round to the last bot (SL / TP)");
        repeat (20) @(posedge clk);
        check(dut.matthew_display.bot_value == dut.squad_value[127:96], "the bot view shows the chosen bot's value");
        press(R);
        check(dut.bot_sel == 3'd0, "and round again to the moving-average bot");
        view_sw = 0;
        repeat (5) @(posedge clk);
        check(dut.matthew_display.pixel_data_L == dut.ticket_pixel,
              "sw15 down: left OLED back to the order ticket");
        press(R); press(C);
        check(dut.screen_state == S_STOCKS, "sw15 down: buttons work again");

        // ---------------- the four bot_squad bots
        check(n_squad > 0 && n_close > 0, "bot_squad's bots trade at the opens and closes");
        check(bad_night == 0, "OVERNIGHT holds nothing during any day");
        check(bad_day == 0, "MOMENTUM never trades at a close");
        check(places_ok(dut.matthew_display.numbers_ranks), "the leaderboard places are 1 to 6, each once");
        check(order_ok(dut.matthew_display.numbers_ranks, dut.matthew_display.numbers_order), "the leaderboard rows go 1st to 6th");
        $display("     bot_squad: %0d trades; values %0d %0d %0d %0d c", n_squad,
                 dut.squad_value[31:0], dut.squad_value[63:32], dut.squad_value[95:64], dut.squad_value[127:96]);

        // ---------------- sound
        check(saw_snd[1] > 0 && saw_snd[2] > 0, "sound: buttons click, the quantity blips");

        // ---------------- game over: everything stops
        while (dut.screen_state != `UI_GAME_END) @(posedge clk);
        repeat (10) @(posedge clk);
        check(dut.sound_now == 3'd5, "sound: the game-end tune plays at game over");
        check(dut.feed_valid == 8'hFF && dut.feed_price[15:0] != 16'd0 && dut.feed_bot[2:0] <= 3'd4,
              "monitor: the news feed holds the bots' last 8 trades");
        // (a woosh lasts 2.6 ms here, in a 5 ms game: by now one has ended and rung its bell)
        check(saw_snd[3] > 0 && woosh_bell > 0, "sound: an order whooshes, then its fill rings the bell");
        repeat (DAY) @(posedge clk);
        begin : frozen
            reg [31:0] d0, v0; reg [15:0] p0; integer s0, b0, t0, pn; reg [63:0] dd;
            d0 = dut.amd_date; p0 = dut.price0; v0 = dut.portfolio_value;
            s0 = n_squad; b0 = dut.bot_trades; t0 = n_tick;
            repeat (3 * DAY) @(posedge clk);
            check(dut.amd_date == d0 && dut.price0 == p0 && n_tick == t0,
                  "game over: the market stops (no new days, prices stay)");
            check(dut.portfolio_value == v0, "game over: your net worth stays at the final value");
            check(n_squad == s0 && dut.bot_trades == b0, "game over: no bot trades any more");
            check(dut.time_remaining == 0, "game over: no days left");
            check(bad_bar == 0 && saw_g && saw_y && saw_r,
                  "progress bar green, yellow from 60 days left, red from 10");
            // return % and max drawdown (basis points) on the portfolio panel
            pn = dut.pnl;
            dd = ({32'd0, dut.tricia_portfolio.peak - dut.equity} * 64'd10000) / dut.tricia_portfolio.peak;
            check(dut.pnl != 0 && dut.ret_bp == pn / 100, "return % = P/L / $100 (start $10,000)");
            check(dut.tricia_portfolio.dd_bp == dd[31:0] && dut.max_dd_bp >= dut.tricia_portfolio.dd_bp
                  && dut.max_dd_bp != 0, "drawdown = (peak - net worth) / peak; max drawdown is the largest");
            $display("     you: P/L %0d c, return %0d bp, drawdown %0d bp, max drawdown %0d bp",
                     pn, $signed(dut.ret_bp), dut.tricia_portfolio.dd_bp, dut.max_dd_bp);
        end

        // ---------------- a new game (sw0 up, down), started at another time: another market
        @(negedge clk); rst = 1; repeat (10) @(posedge clk); rst = 0;
        repeat (DAY / 3 + 777) @(posedge clk);
        press(C);
        wait (dut.amd_ready && dut.mcd_ready && dut.stock2_ready && dut.stock3_ready);
        check(dut.yian_market.startup_random_seed != seed1, "a new game gets a new random seed");
        t_new = n_tick;
        while (n_tick == t_new) @(posedge clk);
        repeat (100) @(posedge clk);
        check({dut.price0, dut.price1, dut.price2, dut.price3} != px1, "and a different market (prices after day 1)");

        check(n_err == 0, "Tricia's ledger never rejected a fill from Douglas");
        $display("     cash %0d c, AMD position %0d, realised %0d c, %0d fills, %0d rejects",
                 dut.cash, dut.pos0, dut.realised, n_fill, n_rej);
        if (n_fail == 0) $display("PASS: tb_integration (%0d checks)", n_pass);
        else             $display("FAIL: tb_integration (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end

    initial begin #20_000_000; $display("FAIL: tb_integration timeout"); $finish; end
endmodule
