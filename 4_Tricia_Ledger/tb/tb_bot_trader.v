`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_bot_trader: the bot's momentum rule, its cash and shares, its value and
// its trade log, against hand-worked numbers. Every stock's last 30 days are
// flat at $100.00, so its 8-day average is $100.00 (buy above $101.56, sell
// below $98.44).
module tb_bot_trader;
    reg clk = 0;
    always #5 clk = ~clk;

    reg         rst = 1, tick = 0, live = 1;
    reg  [7:0]  day = 8'd3;
    reg  [15:0] p0 = 10000, p1 = 10000, p2 = 10000, p3 = 0;
    reg  [479:0] flat;
    wire [31:0] cash, value, cb0, cb1, cb2, cb3;
    wire [9:0]  pos0, pos1, pos2, pos3;
    wire [7:0]  signal, trades;
    wire [4:0]  log_valid, log_side;
    wire [9:0]  log_stock;
    wire [79:0] log_price;
    wire [39:0] log_day;

    bot_trader dut (
        .clk(clk), .rst(rst), .tick(tick), .game_live(live), .day(day),
        .price0(p0), .price1(p1), .price2(p2), .price3(p3),
        .samples0(flat), .samples1(flat), .samples2(flat), .samples3(flat),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .cb0(cb0), .cb1(cb1), .cb2(cb2), .cb3(cb3), .value(value),
        .signal(signal), .trades(trades),
        .log_valid(log_valid), .log_side(log_side), .log_stock(log_stock),
        .log_price(log_price), .log_day(log_day)
    );

    integer n_pass = 0, n_fail = 0, i;
    task check;
        input          cond;
        input [8*60:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s (t=%0t)", name, $time); end
        end
    endtask
    task do_tick;
        begin
            @(negedge clk); tick = 1; @(negedge clk); tick = 0;
            repeat (30) @(negedge clk);
        end
    endtask

    initial begin
        for (i = 0; i < 30; i = i + 1) flat[16*i +: 16] = 16'd10000;
        repeat (3) @(negedge clk); rst = 0;
        check(cash == 1_000_000 && value == 1_000_000 && trades == 0, "starts with $10,000 and no trades");

        // AMD rises to $105 (above $101.56): buy 10 at the ask $105.05 + $1 fee
        // MCD falls to $95 but the bot holds none: nothing to sell
        p0 = 10500; p1 = 9500;
        do_tick;
        check(pos0 == 10 && cash == 1_000_000 - 105_150, "AMD up: buys 10 at 105.05, pays 1051.50");
        check(cb0 == 105_150, "AMD cost basis includes the fee");
        check(pos1 == 0, "MCD down but none held: no sale");
        check(signal[1:0] == 2'd1 && signal[3:2] == 2'd2 && signal[5:4] == 2'd0, "signals: AMD up, MCD down, NVDA flat");
        check(pos3 == 0, "GME has no price: never traded");
        check(value == 894_850 + 10 * 10500, "value = cash + 10 x 105.00");
        check(trades == 1 && log_valid == 5'b00001 && log_side[0] == 1'b0 && log_stock[1:0] == 2'd0
              && log_price[15:0] == 16'd10505 && log_day[7:0] == 8'd3, "log: day 3, BUY AMD @ 105.05");

        // AMD still up but already held: no second buy
        day = 8'd4;
        do_tick;
        check(pos0 == 10 && trades == 1, "AMD still up, already held: no new trade");

        // AMD falls to $95 (below $98.44): sell all 10 at the bid $94.95 - $1 fee
        day = 8'd5; p0 = 9500;
        do_tick;
        check(pos0 == 0 && cb0 == 0 && cash == 894_850 + 94_850, "AMD down: sells 10 at 94.95, gets 948.50");
        check(value == cash, "no shares left: value = cash");
        check(trades == 2 && log_valid == 5'b00011 && log_side[0] == 1'b1 && log_price[15:0] == 16'd9495
              && log_day[7:0] == 8'd5 && log_price[31:16] == 16'd10505, "log: newest SELL @ 94.95, then the BUY");

        // no trading outside the game
        live = 0; p0 = 11000;
        do_tick;
        check(pos0 == 0 && trades == 2, "game not running: no trades");

        if (n_fail == 0) $display("PASS: tb_bot_trader (%0d checks)", n_pass);
        else             $display("FAIL: tb_bot_trader (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
