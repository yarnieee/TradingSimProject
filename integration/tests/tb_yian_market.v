`timescale 1ns / 1ps

// tb_yian_market: checks Yi An's market engine (A_top) on its own.
//   - both stocks become ready, starting from the LAST row of their seed file
//     (the most recent trading day, 2025-12-19)
//   - one tick per trading day: the date moves forward every day
//   - prices stay sane for 60 simulated days: never 0, never pinned at
//     $655.35, never below $1.00, and no single day moves more than 25%
// A trading day is shortened to 2000 clocks; nothing else is changed.
//
// EXPECTED TO FAIL until stock.v's calculate_next_close is fixed (unsigned
// arithmetic pins prices at 65535; a 10% daily downward drift). See
// integration/README.md, Known issues. It passes once those are fixed.
module tb_yian_market;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;

    wire [1:0]  market_state;
    wire        amd_ready, mcd_ready;
    wire [15:0] amd_close, mcd_close;
    wire [31:0] amd_date, mcd_date;

    localparam DAY = 2000;
    A_top #(.DAY_MAX_COUNT(DAY)) dut (
        .clk(clk), .rst(rst), .market_state(market_state),
        .amd_ready(amd_ready), .mcd_ready(mcd_ready),
        .amd_current_close(amd_close), .amd_current_volume(), .amd_current_date(amd_date),
        .mcd_current_close(mcd_close), .mcd_current_volume(), .mcd_current_date(mcd_date),
        .amd_samples_30(), .amd_samples_180(), .amd_samples_720(), .amd_samples_1800(),
        .amd_mean_30(), .amd_mean_180(), .amd_mean_720(), .amd_mean_1800(),
        .mcd_samples_30(), .mcd_samples_180(), .mcd_samples_720(), .mcd_samples_1800(),
        .mcd_mean_30(), .mcd_mean_180(), .mcd_mean_720(), .mcd_mean_1800()
    );
    // Simulation only: Vivado's simulator copies .mem files flat into its run folder.
    defparam dut.amd_stock_inst.SEED_FILE = "AMD_seed.mem";
    defparam dut.mcd_stock_inst.SEED_FILE = "MCD_seed.mem";

    integer n_pass = 0, n_fail = 0;
    task check;
        input          cond;
        input [8*80:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s (t=%0t)", name, $time); end
        end
    endtask

    // last rows of the trimmed seed files (2025-12-19)
    localparam [15:0] AMD_LAST_CLOSE = 16'h535F;   // 21343 c
    localparam [15:0] MCD_LAST_CLOSE = 16'h7B60;   // 31584 c
    localparam [31:0] LAST_DATE      = 32'd20251219;

    integer day, bad_range, bad_jump, bad_date;
    reg [15:0] a_prev, m_prev;
    reg [31:0] d_prev;
    integer a_move, m_move;

    initial begin
        repeat (5) @(posedge clk);
        rst = 0;
        wait (amd_ready && mcd_ready);
        @(posedge clk); #1;
        check(amd_close == AMD_LAST_CLOSE && mcd_close == MCD_LAST_CLOSE,
              "starts from the most recent seed row (AMD 21343 c, MCD 31584 c)");
        check(amd_date == LAST_DATE, "starting date is 2025-12-19 (the last seed row)");
        $display("     day 0: %0d  AMD %0d c  MCD %0d c", amd_date, amd_close, mcd_close);

        bad_range = 0; bad_jump = 0; bad_date = 0;
        a_prev = amd_close; m_prev = mcd_close; d_prev = amd_date;
        for (day = 1; day <= 60; day = day + 1) begin
            repeat (DAY + 1) @(posedge clk); #1;
            if (amd_date <= d_prev || mcd_date != amd_date) bad_date = bad_date + 1;
            if (amd_close < 100 || mcd_close < 100 || amd_close == 16'hFFFF || mcd_close == 16'hFFFF)
                bad_range = bad_range + 1;
            a_move = amd_close - a_prev; if (a_move < 0) a_move = -a_move;
            m_move = mcd_close - m_prev; if (m_move < 0) m_move = -m_move;
            if (a_move * 4 > a_prev || m_move * 4 > m_prev) bad_jump = bad_jump + 1;
            if (day % 10 == 0)
                $display("     day %0d: %0d  AMD %0d c  MCD %0d c", day, amd_date, amd_close, mcd_close);
            a_prev = amd_close; m_prev = mcd_close; d_prev = amd_date;
        end
        check(bad_date == 0,  "date moves forward every trading day, same for both stocks");
        check(bad_range == 0, "prices stay between $1.00 and $655.35 (exclusive) for 60 days");
        check(bad_jump == 0,  "no day moves a price by more than 25%");

        if (n_fail == 0) $display("PASS: tb_yian_market (%0d checks)", n_pass);
        else             $display("FAIL: tb_yian_market (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end

    initial begin #10_000_000; $display("FAIL: tb_yian_market timeout"); $finish; end
endmodule
