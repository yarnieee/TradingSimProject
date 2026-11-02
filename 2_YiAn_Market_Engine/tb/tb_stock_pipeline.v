`timescale 1ns / 1ps

// stock works out the next day over several clocks after day_tick.  For
// thousands of days with random prices, random values and market states,
// check that:
//   - the new close equals calculate_next_close (the one-clock formula)
//   - the date follows the trading calendar (Friday -> Monday, month ends,
//     leap years)
//   - close, date and history change together, exactly LATENCY clocks after
//     day_tick, once per day, and two stocks change on the same clock
module tb_stock_pipeline;
    localparam integer LATENCY = 30;
    localparam integer DAYS    = 3000;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg day_tick = 1'b0;
    reg [1:0] market_state = 2'b01;
    reg [7:0] normalized_random = 8'd50;

    wire        ready_a, ready_b;
    wire [15:0] close_a, close_b;
    wire [31:0] date_a, date_b;
    wire [15:0] hist_a, hist_b;
    wire [31:0] vol_a, vol_b, vh_a, vh_b, dh_a, dh_b;

    stock #(.BUFFER_DEPTH(1), .VOLATILITY(10), .SEED_FILE("AMD_seed.mem")) dut_a (
        .clk(clk), .rst(rst), .day_tick(day_tick), .market_state(market_state),
        .normalized_random(normalized_random), .ready(ready_a),
        .current_close(close_a), .current_volume(vol_a), .current_date(date_a),
        .close_history(hist_a), .volume_history(vh_a), .date_history(dh_a));

    stock #(.BUFFER_DEPTH(1), .VOLATILITY(100), .SEED_FILE("AMD_seed.mem")) dut_b (
        .clk(clk), .rst(rst), .day_tick(day_tick), .market_state(market_state),
        .normalized_random(normalized_random), .ready(ready_b),
        .current_close(close_b), .current_volume(vol_b), .current_date(date_b),
        .close_history(hist_b), .volume_history(vh_b), .date_history(dh_b));

    integer n_pass = 0;
    integer n_fail = 0;
    task check;
        input condition;
        input [8*96:1] name;
        begin
            if (condition === 1'b1) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("FAIL: %0s", name);
            end
        end
    endtask

    // reference calendar (weekday 0 = Saturday ... 6 = Friday, as in stock.v)
    integer y, m, d, wd;
    task next_trading_day;
        integer steps, s, len;
        begin
            steps = (wd == 6) ? 3 : 1;
            for (s = 0; s < steps; s = s + 1) begin
                case (m)
                    2: len = (y % 4 == 0) ? 29 : 28;
                    4, 6, 9, 11: len = 30;
                    default: len = 31;
                endcase
                d = d + 1;
                if (d > len) begin
                    d = 1;
                    if (m == 12) begin m = 1; y = y + 1; end
                    else m = m + 1;
                end
                wd = (wd == 6) ? 0 : wd + 1;
            end
        end
    endtask

    integer day, k, seed;
    integer bad_close_a, bad_close_b, bad_date, bad_hist, bad_early, bad_late, bad_sync;
    integer leap_days;
    reg [15:0] prev_a, prev_b, exp_a, exp_b;
    reg [31:0] date_before;

    initial begin
        seed = 2026;
        y = 2025; m = 12; d = 19; wd = 6;     // the module's starting calendar
        repeat (3) @(posedge clk);
        rst = 1'b0;
        wait (ready_a && ready_b);
        @(posedge clk); #1;

        bad_close_a = 0; bad_close_b = 0; bad_date = 0; bad_hist = 0;
        bad_early = 0; bad_late = 0; bad_sync = 0; leap_days = 0;
        for (day = 1; day <= DAYS; day = day + 1) begin
            // previous close: mostly random, sometimes at the limits
            k = $random(seed) & 15;
            prev_a = (k == 0) ? 16'd1 : (k == 1) ? 16'd65534 : (k == 2) ? 16'd2
                   : ($random(seed) % 65534 + 65534) % 65534 + 1;
            prev_b = (k == 3) ? 16'd65534 : (k == 4) ? 16'd1 : prev_a ^ 16'h0155;
            if (prev_b == 16'd0 || prev_b == 16'hFFFF) prev_b = 16'd500;
            // random value: 0..100 like normalise_lfsr, sometimes out of range
            k = $random(seed) & 31;
            normalized_random = (k == 0) ? 8'd0 : (k == 1) ? 8'd100 : (k == 2) ? 8'd255
                              : (($random(seed) % 101) + 101) % 101;
            market_state = $random(seed);

            force dut_a.current_close = prev_a;
            force dut_b.current_close = prev_b;
            exp_a = dut_a.calculate_next_close(prev_a, normalized_random, market_state);
            exp_b = dut_b.calculate_next_close(prev_b, normalized_random, market_state);
            date_before = date_a;

            day_tick = 1'b1;
            @(posedge clk); #1;
            day_tick = 1'b0;
            release dut_a.current_close;
            release dut_b.current_close;
            normalized_random = $random(seed);     // later changes must not matter
            market_state = $random(seed);

            // nothing changes before LATENCY clocks
            repeat (LATENCY - 1) begin
                @(posedge clk); #1;
                if (date_a != date_before || date_b != date_before) bad_early = bad_early + 1;
            end
            @(posedge clk); #1;
            if (date_a == date_before) bad_late = bad_late + 1;
            if (date_a != date_b) bad_sync = bad_sync + 1;

            next_trading_day;
            if (m == 2 && d == 29) leap_days = leap_days + 1;
            if (close_a != exp_a) begin
                bad_close_a = bad_close_a + 1;
                if (bad_close_a <= 3)
                    $display("  close A: prev %0d rand %0d state %0d -> got %0d, want %0d",
                             prev_a, dut_a.p_rand, dut_a.p_mstate, close_a, exp_a);
            end
            if (close_b != exp_b) bad_close_b = bad_close_b + 1;
            if (date_a != y * 10000 + m * 100 + d) begin
                bad_date = bad_date + 1;
                if (bad_date <= 3)
                    $display("  date: got %0d, want %0d", date_a, y * 10000 + m * 100 + d);
            end
            if (hist_a != close_a || dh_a != date_a || hist_b != close_b) bad_hist = bad_hist + 1;

            // a few idle clocks; the history must not be written again
            repeat (5) @(posedge clk); #1;
            if (hist_a != close_a || dh_a != date_a) bad_hist = bad_hist + 1;
        end

        check(bad_close_a == 0, "VOLATILITY 10: every new close equals calculate_next_close");
        check(bad_close_b == 0, "VOLATILITY 100: every new close equals calculate_next_close");
        check(bad_date == 0,    "the date follows the trading calendar (weekends, month ends)");
        check(leap_days > 0,    "the run crosses at least one 29 February");
        check(bad_early == 0,   "nothing changes before the result is ready");
        check(bad_late == 0,    "close and date change exactly LATENCY clocks after day_tick");
        check(bad_sync == 0,    "two stocks change on the same clock");
        check(bad_hist == 0,    "the history gets the new close and date, once per day");
        $display("     %0d days, last date %0d", DAYS, date_a);

        if (n_fail == 0) $display("PASS: tb_stock_pipeline (%0d checks)", n_pass);
        else             $display("FAIL: tb_stock_pipeline (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
