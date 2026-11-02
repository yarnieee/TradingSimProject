`timescale 1ns / 1ps

// tb_bot_squad: the four bots of bot_squad on scripted prices.
// Numbers worked out by hand: QTY 20, SPREAD 5, FEE 100, start $10,000.00;
// a buy costs (price + 5) x 20 + 100, a sell gets (price - 5) x 20 - 100 (cents).
module tb_bot_squad;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1, run = 1'b1, open_tick = 1'b0, close_tick = 1'b0;
    reg [15:0] p0 = 16'd10000, p1 = 16'd20000, p2 = 16'd5000, p3 = 16'd1000;
    reg [1:0]  sel = 2'd2;
    wire [127:0] value;
    wire [31:0]  sel_cash;
    wire [39:0]  sel_pos;
    wire [127:0] sel_upnl;
    wire         trade, trade_side;
    wire [1:0]   trade_bot, trade_stock;
    wire [15:0]  trade_price;

    bot_squad dut (
        .clk(clk), .rst(rst), .run(run), .open_tick(open_tick), .close_tick(close_tick),
        .price0(p0), .price1(p1), .price2(p2), .price3(p3), .sel(sel),
        .value(value), .sel_cash(sel_cash), .sel_pos(sel_pos), .sel_upnl(sel_upnl),
        .trade(trade), .trade_bot(trade_bot), .trade_stock(trade_stock),
        .trade_side(trade_side), .trade_price(trade_price)
    );

    integer n_pass = 0, n_fail = 0;
    task check;
        input          cond;
        input [8*72:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s", name); end
        end
    endtask

    // trades seen since the last event: [bot][stock] buys / sells, and their prices
    integer nbuy  [0:15];
    integer nsell [0:15];
    reg [15:0] last_px [0:15];
    integer q;
    always @(posedge clk)
        if (trade) begin
            if (trade_side) nsell[{trade_bot, trade_stock}] = nsell[{trade_bot, trade_stock}] + 1;
            else            nbuy [{trade_bot, trade_stock}] = nbuy [{trade_bot, trade_stock}] + 1;
            last_px[{trade_bot, trade_stock}] = trade_price;
        end

    task event_pulse;          // one open or close, then wait for the bots and a re-valuation
        input is_open;
        begin
            for (q = 0; q < 16; q = q + 1) begin nbuy[q] = 0; nsell[q] = 0; end
            @(negedge clk);
            if (is_open) open_tick = 1'b1; else close_tick = 1'b1;
            @(negedge clk);
            open_tick = 1'b0; close_tick = 1'b0;
            repeat (300) @(posedge clk);
            #1;
        end
    endtask

    function integer bought;   // buys of bot b, stock k in the last event
        input integer bk;
        begin bought = nbuy[bk]; end
    endfunction

    function [31:0] cost; input [15:0] p; begin cost = (p + 5) * 20 + 100; end endfunction
    function [31:0] gets; input [15:0] p; begin gets = (p - 5) * 20 - 100; end endfunction

    integer b, k, buys, sells;
    reg [31:0] want;
    initial begin
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (40) @(posedge clk);
        check(value === {4{32'd1_000_000}}, "everyone starts with $10,000.00");

        // ---------------- day 1 open: prices 100, 200, 50, 10
        event_pulse(1);
        buys = 0; sells = 0;
        for (q = 0; q < 16; q = q + 1) begin buys = buys + nbuy[q]; sells = sells + nsell[q]; end
        check(nbuy[0] + nbuy[1] + nbuy[2] + nbuy[3] == 0 && nsell[0] + nsell[1] + nsell[2] + nsell[3] == 0,
              "OVERNIGHT does nothing at the first open");
        check(nbuy[4] + nbuy[5] + nbuy[6] + nbuy[7] == 0 && dut.ref_m[5] == 16'd20000,
              "MOMENTUM: no buy on day 1 (no yesterday yet), remembers today's price");
        check(nbuy[8] == 1 && nbuy[11] == 1 && nbuy[12] == 1 && nbuy[15] == 1, "AVG DOWN and SL/TP buy at the open");
        check(sells == 0 && buys == 8, "8 buys and no sells at the first open");
        check(last_px[9] == 16'd20005, "a buy pays the ask (price + 5)");
        check(dut.cb_m[8] == cost(10000), "cost basis = 20 x ask + the fee, as ledger.v");
        want = 32'd1_000_000 - cost(10000) - cost(20000) - cost(5000) - cost(1000);
        check(dut.cash_m[2] == want, "AVG DOWN cash = start - the four costs");
        // at the price it paid, a bot is worth its cash + shares x mid price
        check(value[95:64] == want + 20 * (10000 + 20000 + 5000 + 1000), "net worth = cash + shares x price");

        // ---------------- day 1 close: same prices
        event_pulse(0);
        check(nbuy[0] == 1 && nbuy[1] == 1 && nbuy[2] == 1 && nbuy[3] == 1, "OVERNIGHT buys all four at the close");
        check(nbuy[4] + nsell[4] + nbuy[5] + nsell[5] + nbuy[6] + nsell[6] + nbuy[7] + nsell[7] == 0,
              "MOMENTUM does nothing at the close");
        check(nbuy[8] + nsell[8] + nbuy[12] + nsell[12] == 0, "AVG DOWN and SL/TP do nothing at the close");

        // ---------------- day 2 open: 94.00 (-6%), 221.00 (+10.5%), 50.00, 10.60 (+6%)
        p0 = 16'd9400; p1 = 16'd22100; p2 = 16'd5000; p3 = 16'd1060;
        event_pulse(1);
        check(nsell[0] == 1 && nsell[1] == 1 && nsell[2] == 1 && nsell[3] == 1, "OVERNIGHT sells everything at the open");
        check(dut.pos_m[0] == 0 && dut.pos_m[1] == 0 && dut.pos_m[2] == 0 && dut.pos_m[3] == 0,
              "OVERNIGHT holds nothing during the day");
        want = 32'd1_000_000 - cost(10000) - cost(20000) - cost(5000) - cost(1000)
             + gets(9400) + gets(22100) + gets(5000) + gets(1060);
        check(dut.cash_m[0] == want, "OVERNIGHT cash: bought at day 1's close, sold at day 2's open");
        check(last_px[0] == 16'd9395, "a sell gets the bid (price - 5)");
        // MOMENTUM: stocks 1 and 3 went up once, stock 0 down, stock 2 flat
        check(nbuy[5] == 0 && nbuy[7] == 0 && dut.adds_m[5] == 2'd1 && dut.adds_m[7] == 2'd1
              && dut.adds_m[4] == 2'd0 && dut.adds_m[6] == 2'd0,
              "MOMENTUM: one up day is not enough (MOM_N = 2), up days counted per stock");
        // AVG DOWN: 94.00 <= 100.00 - 5% -> add; 221.00 x 20 at the bid >= cost + 5% -> sell;
        // 50.00: no change; 10.60: 21,100 < 20,200 + 1,011 -> hold
        check(nbuy[8] == 1 && dut.pos_m[8] == 40, "AVG DOWN adds 20 more after a 5% fall");
        check(dut.cb_m[8] == cost(10000) + cost(9400), "an add adds its cost, fee included");
        check(nsell[9] == 1 && dut.pos_m[9] == 0, "AVG DOWN sells once 5% above what it paid");
        check(nbuy[10] + nsell[10] + nbuy[11] + nsell[11] == 0, "AVG DOWN holds the others");
        // SL / TP: 94.00 <= 100.00 - 3% -> stop loss; 221.00 >= 200.00 + 10% -> take profit
        check(nsell[12] == 1 && nsell[13] == 1, "SL/TP: stop loss below -3%, take profit at +10%");
        check(nbuy[12] == 0 && nbuy[13] == 0, "SL/TP does not buy back at the same open");
        check(nbuy[14] + nsell[14] + nbuy[15] + nsell[15] == 0, "SL/TP holds the stocks still inside its band");

        event_pulse(0);                                                    // day 2 close

        // ---------------- day 3 open: 89.00
        p0 = 16'd8900;
        event_pulse(1);
        check(nbuy[8] == 1 && dut.pos_m[8] == 60 && dut.adds_m[8] == 2, "AVG DOWN adds again 5% below its last buy");
        // after two adds it has $3,546.00 left, less than 20 x 221.05 + 1.00: no new buy
        check(nbuy[9] == 0 && dut.cash_m[2] == 32'd354_600 && dut.cash_m[2] < cost(22100),
              "AVG DOWN cannot afford to buy back stock 1, so it does not");
        check(nbuy[12] == 1 && nbuy[13] == 1, "SL/TP buys again the day after selling");
        check(dut.adds_m[7] == 2'd0 && nbuy[7] == 0, "MOMENTUM: a flat day (10.60 again) resets the up-day count");
        event_pulse(0);

        // ---------------- days 4, 5: 84.00 (third add), 79.00 (no fourth)
        // SL / TP stock 2, entry 50.00: stop at 50.00 - 50.00 x 1968 >> 16 = 50.00 - 1.50 = 48.50
        p0 = 16'd8400; p2 = 16'd4851;
        event_pulse(1);
        check(nbuy[8] == 1 && dut.pos_m[8] == 80, "AVG DOWN third add");
        check(nsell[14] == 0 && dut.pos_m[14] == 20, "SL/TP holds at 48.51 (-2.98%, inside the 3% stop)");
        event_pulse(0);
        p0 = 16'd7900; p2 = 16'd4850;
        event_pulse(1);
        check(nbuy[8] == 0 && dut.pos_m[8] == 80, "AVG DOWN stops after 3 adds");
        check(nsell[14] == 1 && last_px[14] == 16'd4845, "SL/TP stop loss at exactly -3% (48.50), sold at the bid");
        sel = 2'd2; repeat (100) @(posedge clk); #1;
        check(sel_pos[9:0] == 10'd80, "details of the chosen bot: AVG DOWN holds 80 of stock 0");
        want = cost(10000) + cost(9400) + cost(8900) + cost(8400);
        check(dut.cb_m[8] == want, "AVG DOWN paid for four lots, fees included");
        check($signed(sel_upnl[31:0]) == $signed(32'd80 * 7900 - want), "its profit/loss = shares x price - cost");
        check(sel_cash == dut.cash_m[2], "its cash");
        event_pulse(0);

        // ---------------- a price too high to afford: 600.00 x 20 > cash
        // (raised between the open and the close, so OVERNIGHT first sells stock 1 at the
        // old price; raised at the open, that sale would make it rich enough to buy)
        event_pulse(1);
        p1 = 16'd60000;
        event_pulse(0);
        check(nbuy[1] == 0, "OVERNIGHT skips a stock it cannot afford");
        check(nbuy[0] == 1, "... but still buys the ones it can");

        // ---------------- MOMENTUM, stock 3: up, up -> buy; up -> hold; down -> sell
        p3 = 16'd1100;                                                     // day 7: up once
        event_pulse(1);
        check(nbuy[7] == 0 && dut.adds_m[7] == 2'd1, "MOMENTUM: first up day, no buy yet");
        event_pulse(0);
        p3 = 16'd1150;                                                     // day 8: up twice
        event_pulse(1);
        check(nbuy[7] == 1 && last_px[7] == 16'd1155 && dut.pos_m[7] == 20,
              "MOMENTUM buys after 2 up days in a row, at the ask");
        event_pulse(0);
        check(dut.pos_m[7] == 20 && nsell[7] == 0, "MOMENTUM holds overnight");
        p3 = 16'd1200;                                                     // day 9: up again
        event_pulse(1);
        check(nbuy[7] + nsell[7] == 0 && dut.pos_m[7] == 20, "MOMENTUM keeps holding while the price rises");
        event_pulse(0);
        event_pulse(1);                                                    // day 9b: 12.00 again (flat)
        check(nsell[7] == 0 && dut.pos_m[7] == 20, "MOMENTUM: a flat day is not a down day, keeps holding");
        event_pulse(0);
        p3 = 16'd1190;                                                     // day 10: first down day
        event_pulse(1);
        check(nsell[7] == 1 && last_px[7] == 16'd1185 && dut.pos_m[7] == 0,
              "MOMENTUM sells everything on the first down day, at the bid");
        check(dut.cash_m[1] == 32'd1_000_000 - cost(1150) + gets(1190),
              "MOMENTUM cash: start - 20 x 11.55 - $1 + 20 x 11.85 - $1");
        event_pulse(0);

        // ---------------- run = 0 (game over): no trades, values frozen
        run = 1'b0;
        event_pulse(1);
        buys = 0;
        for (q = 0; q < 16; q = q + 1) buys = buys + nbuy[q] + nsell[q];
        check(buys == 0, "no trades while run is 0");

        // ---------------- a new game: everyone back to the start
        rst = 1'b1; repeat (3) @(posedge clk); rst = 1'b0; run = 1'b1;
        repeat (100) @(posedge clk); #1;
        check(value === {4{32'd1_000_000}} && dut.pos_m[8] == 0 && dut.adds_m[8] == 0 && dut.ref_m[7] == 0,
              "reset: a new game starts flat (MOMENTUM forgets yesterday)");

        if (n_fail == 0) $display("PASS: tb_bot_squad (%0d checks)", n_pass);
        else             $display("FAIL: tb_bot_squad (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
