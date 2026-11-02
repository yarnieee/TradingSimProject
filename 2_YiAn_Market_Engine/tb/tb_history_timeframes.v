`timescale 1ns / 1ps

// Check chronological ordering, exact short-term samples, and remainder
// distribution in the configurable history/timeframe sampler.
module tb_history_timeframes;
    reg [(180*16)-1:0] history;
    wire [(7*16)-1:0] samples_7;
    wire [15:0] mean_7;
    wire [(30*16)-1:0] samples_30;
    wire [15:0] mean_30;
    wire [(30*16)-1:0] samples_180;
    wire [15:0] mean_180;
    wire [(3*16)-1:0] samples_10_by_3;
    wire [15:0] mean_10_by_3;

    integer i;
    integer n_pass = 0;
    integer n_fail = 0;

    task check;
        input         cond;
        input [8*96:1] name;
        begin
            if (cond === 1'b1)
                n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("FAIL: %0s", name);
            end
        end
    endtask

    // Newest history entry is 1000; older entries decrease by one.
    get_30_values #(
        .WINDOW(7), .TOTAL_DEPTH(180), .SAMPLE_COUNT(7)
        ) dut_7 (
        .history_in(history), .samples_out(samples_7), .mean_out(mean_7)
    );

    get_30_values #(
        .WINDOW(30), .TOTAL_DEPTH(180), .SAMPLE_COUNT(30)
        ) dut_30 (
        .history_in(history), .samples_out(samples_30), .mean_out(mean_30)
    );

    get_30_values #(
        .WINDOW(180), .TOTAL_DEPTH(180), .SAMPLE_COUNT(30)
        ) dut_180 (
        .history_in(history), .samples_out(samples_180), .mean_out(mean_180)
    );

    // WINDOW=10 is intentionally not divisible by SAMPLE_COUNT=3.
    get_30_values #(
        .WINDOW(10), .TOTAL_DEPTH(180), .SAMPLE_COUNT(3)
        ) dut_remainder (
        .history_in(history), .samples_out(samples_10_by_3),
        .mean_out(mean_10_by_3)
    );

    initial begin
        history = {(180*16){1'b0}};
        for (i = 0; i < 180; i = i + 1)
            history[i*16 +: 16] = 16'd1000 - i;
        #1;

        check(samples_7[15:0] == 16'd994
            && samples_7[111:96] == 16'd1000
            && mean_7 == 16'd997,
            "7-day output is chronological and preserves each daily close");
        check(samples_30[15:0] == 16'd971
            && samples_30[479:464] == 16'd1000
            && mean_30 == 16'd985,
            "30-day output is chronological with the correct integer mean");
        check(samples_180[15:0] == 16'd823
            && samples_180[479:464] == 16'd997
            && mean_180 == 16'd910,
            "180-day output uses 30 six-day buckets and the correct mean");
        check(samples_10_by_3[15:0] == 16'd992
            && samples_10_by_3[31:16] == 16'd995
            && samples_10_by_3[47:32] == 16'd998
            && mean_10_by_3 == 16'd995,
            "non-divisible windows distribute every history entry");

        if (n_fail == 0)
            $display("PASS: tb_history_timeframes (%0d checks)", n_pass);
        else
            $display("FAIL: tb_history_timeframes (%0d failed, %0d passed)",
                n_fail, n_pass);
        $finish;
    end
endmodule
