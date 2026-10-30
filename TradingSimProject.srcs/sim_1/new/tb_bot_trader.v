`timescale 1ns / 1ps
// tb_bot_trader.v: bot_trader driving a real ledger (Member C)
// All prices start at 100.00. Each step sends one tick, waits ~300 clocks,
// then checks the bot's ledger.
module tb_bot_trader;
    reg clk = 0, rst = 1, run = 1, tick = 0;
    reg  [15:0] price0 = 16'd10000, price1 = 16'd10000, price2 = 16'd10000, price3 = 16'd10000;

    wire        fill, fill_side;
    wire [1:0]  fill_stock;
    wire [7:0]  fill_qty;
    wire [15:0] fill_price, fill_fee;
    wire [31:0] cash, cb0, cb1, cb2, cb3;
    wire [9:0]  pos0, pos1, pos2, pos3;
    wire signed [31:0] realised;
    wire        ledger_busy, err;
    wire        last_valid, last_side, tick_done;
    wire [1:0]  last_stock;
    wire [7:0]  last_qty;
    wire [15:0] last_price;
    integer errors = 0, err_count = 0, done_count = 0;

    bot_trader dut (
        .clk(clk), .rst(rst), .run(run), .tick(tick),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .last_valid(last_valid), .last_stock(last_stock), .last_side(last_side),
        .last_qty(last_qty), .last_price(last_price), .tick_done(tick_done)
    );

    ledger u_ledger (
        .clk(clk), .rst(rst),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .cb0(cb0), .cb1(cb1), .cb2(cb2), .cb3(cb3),
        .realised(realised), .ledger_busy(ledger_busy), .err(err)
    );

    always #5 clk = ~clk;   // 100 MHz

    // count ledger rejects and finished ticks
    always @(posedge clk) begin
        if (err)       err_count  = err_count + 1;
        if (tick_done) done_count = done_count + 1;
    end

    // one trading day: 1-clock tick, then let the bot finish
    task do_tick;
    begin
        @(negedge clk); tick = 1;
        @(negedge clk); tick = 0;
        repeat (300) @(negedge clk);
    end
    endtask

    task check(input [8*28-1:0] name,
               input [31:0] e_cash, input [9:0] e_pos0, input [9:0] e_pos1,
               input integer e_real);
    begin
        if (cash == e_cash && pos0 == e_pos0 && pos1 == e_pos1 &&
            realised == e_real && err_count == 0)
            $display("PASS %0s | cash=%0d pos0=%0d pos1=%0d realised=%0d",
                     name, cash, pos0, pos1, realised);
        else begin
            $display("FAIL %0s | cash=%0d pos0=%0d pos1=%0d realised=%0d errs=%0d",
                     name, cash, pos0, pos1, realised, err_count);
            $display("      expected cash=%0d pos0=%0d pos1=%0d realised=%0d errs=0",
                     e_cash, e_pos0, e_pos1, e_real);
            errors = errors + 1;
        end
    end
    endtask

    initial begin
        #22 rst = 0;
        #50;
        //                                      cash   pos0 pos1 realised
        do_tick;                                // B1: history filled with 100.00, no trade
        check("B1 first tick, all 10000",    1000000,  0,   0,       0);

        price0 = 16'd10100; do_tick;            // up through MA + band -> buy 20 @ 101.05
        check("B2 price0 10100 -> BUY",       797800, 20,   0,       0);

        price0 = 16'd10200; do_tick;            // already holding -> hold
        check("B3 price0 10200 -> hold",      797800, 20,   0,       0);

        price0 = 16'd9600;  do_tick;            // below MA - band -> sell 20 @ 95.95
        check("B4 price0 9600 -> SELL",       989600,  0,   0,  -10400);

        run = 0; price1 = 16'd12000; do_tick;   // signal but not allowed to trade
        check("B5 run=0 price1 12000",        989600,  0,   0,  -10400);

        run = 1; do_tick;                       // signal still there -> buy 20 @ 120.05
        check("B6 run=1 -> BUY stock1",       749400,  0,  20,  -10400);

        if (last_valid && last_stock == 2'd1 && last_side == 1'b0 &&
            last_qty == 8'd20 && last_price == 16'd12005)
            $display("PASS B6 last trade | stock=%0d side=%0d qty=%0d price=%0d",
                     last_stock, last_side, last_qty, last_price);
        else begin
            $display("FAIL B6 last trade | valid=%0d stock=%0d side=%0d qty=%0d price=%0d",
                     last_valid, last_stock, last_side, last_qty, last_price);
            $display("      expected valid=1 stock=1 side=0 qty=20 price=12005");
            errors = errors + 1;
        end

        if (done_count == 6)
            $display("PASS tick_done pulsed once per tick (%0d)", done_count);
        else begin
            $display("FAIL tick_done count = %0d, expected 6", done_count);
            errors = errors + 1;
        end

        if (errors == 0) $display("=== ALL BOT TESTS PASSED ===");
        else             $display("=== %0d BOT TEST(S) FAILED ===", errors);
        $finish;
    end
endmodule
