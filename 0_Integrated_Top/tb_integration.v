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
    reg  bot_sw = 0;
    wire [7:0]  JA, JB, seg;
    wire [15:0] led;
    wire [3:0]  an;

    localparam DAY = 4000;
    Integration_Top #(.DAY_MAX_COUNT(DAY), .DEBOUNCE_CTR(32'd50)) dut (
        .clk(clk), .rst(rst), .bot_sw(bot_sw),
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
            press(R); press(R); press(R); press(C);     // BACK QTY TYPE OK: OK -> ORDER_REVIEW
            press(C);                                   // review -> ORDER_RESULT: submit to B
            repeat (300) @(posedge clk);                // Douglas -> Tricia: fill and ledger update
        end
    endtask

    integer cash0, f0, r0, o0, k0;
    reg [15:0] p0;

    initial begin
        repeat (10) @(posedge clk);
        rst = 0;
        wait (dut.amd_ready && dut.mcd_ready && dut.stock2_ready && dut.stock3_ready);
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

        // ---------------- title -> portfolio
        press(C);
        check(dut.screen_state == S_PORTFOLIO, "Matthew: title -> portfolio");

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
        check(dut.cash + dut.cb0 + dut.cb1 + dut.cb2 + dut.cb3 == 32'd1_000_000 + dut.realised,
              "Tricia: ledger invariant holds");

        // ---------------- limit buy 2 AMD, $5+ below the market, SL/TP 5%: placed in the book
        press(C);                                       // trade result -> portfolio
        o0 = n_ord_req; f0 = n_fill;
        press(R); press(C); press(D); press(C);         // stocks, AMD, specific
        press(C);                                       // buy
        press(R); press(C); press(U); press(U); press(C);   // quantity 2
        press(R); press(R); press(C);                   // TYPE -> order type screen
        check(dut.screen_state == `UI_ORDER_TYPE, "Matthew: buy --TYPE--> order type screen");
        press(R);                                       // MKT -> LMT
        press(D); for (k0 = 0; k0 < 5; k0 = k0 + 1) press(L);   // trigger 5 steps down (~4%)
        press(D); press(R); press(R);                   // SL/TP 5%
        press(C);                                       // back to buy
        check(dut.ord_type == `OT_LMT && dut.ord_brk == `BRK_5 && dut.ord_trig < dut.price0,
              "Matthew: LMT below the price, SL/TP 5% set on the order type screen");
        press(R); press(C);                             // OK -> review
        press(C);                                       // send
        repeat (300) @(posedge clk);
        check(n_ord_req == o0 + 1 && n_fill == f0 && dut.pending_count == 4'd1,
              "Douglas: the limit buy rests in the book");
        check(dut.screen_state == S_TRADE_RESULT && dut.matthew_display.trade_result_placed,
              "Matthew: trade result says PLACED");
        check(dut.douglas_orders.u_book.s_brk[0] == `BRK_5 && dut.douglas_orders.u_book.s_trig[0] == dut.ord_trig,
              "Douglas: book keeps the trigger and the SL/TP setting");

        // ---------------- the bot (Tricia's stub for now); sw[1] shows it
        repeat (6 * DAY) @(posedge clk);               // a few more trading days
        check(!dut.bot_active && dut.bot_trades == 0 && dut.bot_value == 32'd1_000_000,
              "Bot stub: inactive, no trades, value stays at the starting cash");
        bot_sw = 1;
        repeat (5) @(posedge clk);
        check(dut.matthew_display.pixel_data_L == dut.matthew_display.bot_log_pixel,
              "sw1 up: left OLED shows the bot's trades");
        bot_sw = 0;
        repeat (5) @(posedge clk);
        check(dut.matthew_display.pixel_data_L == dut.ticket_pixel,
              "sw1 down: left OLED back to the order ticket");

        check(n_err == 0, "Tricia's ledger never rejected a fill from Douglas");
        $display("     cash %0d c, AMD position %0d, realised %0d c, %0d fills, %0d rejects",
                 dut.cash, dut.pos0, dut.realised, n_fill, n_rej);
        if (n_fail == 0) $display("PASS: tb_integration (%0d checks)", n_pass);
        else             $display("FAIL: tb_integration (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end

    initial begin #20_000_000; $display("FAIL: tb_integration timeout"); $finish; end
endmodule
