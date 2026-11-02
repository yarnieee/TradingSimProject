`timescale 1ns / 1ps
// Independent trading model: exact padded 8-day windows, sequential cash
// allocation, spread, fees, buy-only-when-flat and full-position liquidation.
module tb_bot_regression;
    reg clk = 0, rst = 1, run = 1, tick = 0;
    always #5 clk = ~clk;
    reg [15:0] prices [0:3];
    wire fill, side, busy, err, done;
    wire [1:0] stock_id;
    wire [7:0] qty;
    wire [15:0] px, fee;
    wire [7:0] signals;
    wire [31:0] cash;
    wire [9:0] pos0, pos1, pos2, pos3;
    wire signed [31:0] realised;
    bot_trader dut (
        .clk(clk), .rst(rst), .run(run), .tick(tick),
        .price0(prices[0]), .price1(prices[1]), .price2(prices[2]), .price3(prices[3]),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(busy), .fill(fill), .fill_stock(stock_id), .fill_side(side),
        .fill_qty(qty), .fill_price(px), .fill_fee(fee), .tick_done(done), .signals(signals)
    );
    ledger accounts (
        .clk(clk), .rst(rst), .fill(fill), .fill_stock(stock_id), .fill_side(side),
        .fill_qty(qty), .fill_price(px), .fill_fee(fee), .cash(cash),
        .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .realised(realised), .ledger_busy(busy), .err(err)
    );
    integer window [0:31];
    integer shares [0:3];
    integer basis [0:3];
    integer expect_px [0:3];
    reg [3:0] expect_trade, expect_sell, seen;
    reg [7:0] expected_signals;
    reg [31:0] expected_cash;
    integer expected_realised, errors = 0, days = 0;
    integer buys [0:3];
    integer sells [0:3];
    integer i, j, d, total, average, band, ask, bid, n_done;
    reg [31:0] random_bits = 32'h7ac15eed;
    always @(negedge clk) if (!rst) begin
        if (err) begin errors = errors + 1; $display("FAIL: unexpected ledger reject"); end
        if (fill) begin
            if (!expect_trade[stock_id] || seen[stock_id] ||
                side !== expect_sell[stock_id] || qty !== 8'd20 ||
                px !== expect_px[stock_id] || fee !== 16'd100) begin
                errors = errors + 1;
                $display("FAIL: day %0d stock %0d unexpected/duplicate fill side=%0d qty=%0d px=%0d",
                         days, stock_id, side, qty, px);
            end
            seen[stock_id] = 1;
            if (side) sells[stock_id] = sells[stock_id] + 1;
            else buys[stock_id] = buys[stock_id] + 1;
        end
        if (done) n_done = n_done + 1;
    end
    task day;
        begin
            expect_trade = 0; expect_sell = 0; seen = 0; n_done = 0;
            for (i = 0; i < 4; i = i + 1) begin
                if (days == 0)
                    for (j = 0; j < 8; j = j + 1) window[8*i+j] = prices[i];
                else begin
                    for (j = 7; j > 0; j = j - 1) window[8*i+j] = window[8*i+j-1];
                    window[8*i] = prices[i];
                end
                total = 0;
                for (j = 0; j < 8; j = j + 1) total = total + window[8*i+j];
                average = total / 8; band = average / 256;
                expected_signals[2*i +: 2] = prices[i] > average+band ? 2'd1 :
                                              prices[i]+band < average ? 2'd2 : 2'd0;
                ask = prices[i] + 5; if (ask > 65535) ask = 65535;
                bid = prices[i] > 5 ? prices[i] - 5 : 1;
                if (run && shares[i] == 0 && prices[i] > average + band &&
                    expected_cash >= ask*20+100) begin
                    expect_trade[i] = 1; expect_px[i] = ask;
                    shares[i] = 20; basis[i] = ask*20+100;
                    expected_cash = expected_cash - basis[i];
                end else if (run && shares[i] != 0 && prices[i] + band < average) begin
                    expect_trade[i] = 1; expect_sell[i] = 1; expect_px[i] = bid;
                    expected_cash = expected_cash + bid*20-100;
                    expected_realised = expected_realised + bid*20-100-basis[i];
                    shares[i] = 0; basis[i] = 0;
                end
            end
            @(negedge clk); tick = 1;
            @(negedge clk); tick = 0;
            // Includes the initial 32 serial history writes and all fills.
            repeat (300) @(negedge clk);
            if (signals !== expected_signals || seen !== expect_trade || n_done != 1 || cash !== expected_cash ||
                realised !== expected_realised || pos0 !== shares[0] ||
                pos1 !== shares[1] || pos2 !== shares[2] || pos3 !== shares[3]) begin
                errors = errors + 1;
                $display("FAIL: day %0d cash=%0d expected=%0d fills=%b expected=%b done=%0d",
                          days, cash, expected_cash, seen, expect_trade, n_done);
            end
            days = days + 1;
        end
    endtask
    initial begin
        expected_cash = 1000000; expected_realised = 0;
        for (i = 0; i < 4; i = i + 1) begin
            prices[i] = 10000; shares[i] = 0; basis[i] = 0; buys[i] = 0; sells[i] = 0;
        end
        repeat (4) @(negedge clk); rst = 0;
        day;
        // Simultaneous four-stock signals must each execute exactly once.
        for (i = 0; i < 4; i = i + 1) prices[i] = 10100;
        day;
        for (i = 0; i < 4; i = i + 1) prices[i] = 9500;
        day;
        // Ring wrap and quiet dead band, with and without gameplay enabled.
        run = 0;
        for (d = 0; d < 12; d = d + 1) day;
        run = 1;
        // Exhaustively visit all stocks under distinct reproducible changes.
        for (d = 0; d < 160; d = d + 1) begin
            for (i = 0; i < 4; i = i + 1) begin
                random_bits = {random_bits[30:0], random_bits[31]^random_bits[21]^random_bits[1]^random_bits[0]};
                prices[i] = 16'd8000 + (random_bits % 6001);
            end
            run = (d % 11) != 0;
            day;
        end
        // Unaffordable maximum-price entries: no unsigned ask wrapping.
        for (i = 0; i < 4; i = i + 1) prices[i] = 65535;
        day;
        for (i = 0; i < 4; i = i + 1)
            if (buys[i] == 0 || sells[i] == 0) begin
                errors = errors + 1; $display("FAIL: no buy/sell coverage for stock %0d", i);
            end
        if (errors == 0) $display("PASS: ALL BOT REGRESSION TESTS PASSED (%0d trading days)", days);
        else $display("FAIL: %0d BOT REGRESSION TEST(S) FAILED", errors);
        $finish;
    end
    initial begin #2000000; $display("FAIL: bot regression timeout"); $finish; end
endmodule
