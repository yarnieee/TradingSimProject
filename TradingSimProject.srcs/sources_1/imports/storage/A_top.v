
`timescale 1ns / 1ps

// Storage-system top module.
//
// One independent random source drives AMD and MCD.  Dedicated LFSRs supply
// market-state choices and the five-to-twelve-day market-state duration.  Each
// stock loads its latest 180 CSV records before it starts accepting
// two-second day ticks.
module A_top #(
    parameter integer DAY_MAX_COUNT = 199_999_999,
    parameter integer BUFFER_DEPTH = 180,
    parameter integer AMD_VOLATILITY = 10,
    parameter integer MCD_VOLATILITY = 10
    )(
    input wire clk,
    input wire rst,
    output wire [1:0] market_state,
    output wire amd_ready,
    output wire mcd_ready,
    output wire [15:0] amd_current_close,
    output wire [31:0] amd_current_volume,
    output wire [31:0] amd_current_date,
    output wire [15:0] mcd_current_close,
    output wire [31:0] mcd_current_volume,
    output wire [31:0] mcd_current_date,
    output wire [(30*16)-1:0] amd_samples_30,
    output wire [(30*16)-1:0] amd_samples_180,
    output wire [15:0] amd_mean_30,
    output wire [15:0] amd_mean_180,
    output wire [(30*16)-1:0] mcd_samples_30,
    output wire [(30*16)-1:0] mcd_samples_180,
    output wire [15:0] mcd_mean_30,
    output wire [15:0] mcd_mean_180
    );

    wire day_tick;
    wire [31:0] startup_random_seed;
    wire startup_seed_valid;

    startup_seed startup_seed_inst (
        .clk(clk),
        .rst(rst),
        .seed(startup_random_seed),
        .seed_valid(startup_seed_valid)
    );

    day_ticker #(
        .MAX_COUNT(DAY_MAX_COUNT)
        ) day_ticker_inst (
        .clk(clk),
        .rst(rst),
        .tick(day_tick)
    );

    // Distinct derivations keep the six random streams independent while
    // avoiding a user-configurable seed input.
    wire [31:0] amd_lfsr_seed;
    wire [31:0] mcd_lfsr_seed;
    wire [31:0] market_lfsr_seed;
    wire [31:0] interval_lfsr_seed;

    assign amd_lfsr_seed = startup_random_seed ^ 32'h13579BDF;
    assign mcd_lfsr_seed = startup_random_seed ^ 32'h2468ACE1;
    assign market_lfsr_seed = startup_random_seed ^ 32'h89ABCDEF;
    assign interval_lfsr_seed = startup_random_seed ^ 32'h0F1E2D3C;

    wire [31:0] amd_lfsr_value;
    wire [31:0] mcd_lfsr_value;
    wire [31:0] market_lfsr_value;
    wire [31:0] interval_lfsr_value;
    wire [7:0] amd_random_value;
    wire [7:0] mcd_random_value;

    lfsr amd_lfsr_inst (
        .clk(clk),
        .rst(rst),
        .en(day_tick && amd_ready),
        .load(startup_seed_valid),
        .seed(amd_lfsr_seed),
        .q(amd_lfsr_value)
    );

    lfsr mcd_lfsr_inst (
        .clk(clk),
        .rst(rst),
        .en(day_tick && mcd_ready),
        .load(startup_seed_valid),
        .seed(mcd_lfsr_seed),
        .q(mcd_lfsr_value)
    );

    lfsr market_lfsr_inst (
        .clk(clk),
        .rst(rst),
        .en(day_tick && amd_ready && mcd_ready),
        .load(startup_seed_valid),
        .seed(market_lfsr_seed),
        .q(market_lfsr_value)
    );

    lfsr interval_lfsr_inst (
        .clk(clk),
        .rst(rst),
        .en(day_tick && amd_ready && mcd_ready),
        .load(startup_seed_valid),
        .seed(interval_lfsr_seed),
        .q(interval_lfsr_value)
    );

    normalise_lfsr amd_normalise_lfsr_inst (
        .lfsr_value(amd_lfsr_value),
        .normalized(amd_random_value)
    );

    normalise_lfsr mcd_normalise_lfsr_inst (
        .lfsr_value(mcd_lfsr_value),
        .normalized(mcd_random_value)
    );

    market_state market_state_inst (
        .clk(clk),
        .rst(rst),
        .start(startup_seed_valid),
        .day_tick(day_tick && amd_ready && mcd_ready),
        .random_state(market_lfsr_value[1:0]),
        .random_interval(interval_lfsr_value[2:0]),
        .state(market_state)
    );

    wire [(BUFFER_DEPTH*16)-1:0] amd_close_history;
    wire [(BUFFER_DEPTH*32)-1:0] amd_volume_history;
    wire [(BUFFER_DEPTH*32)-1:0] amd_date_history;
    wire [(BUFFER_DEPTH*16)-1:0] mcd_close_history;
    wire [(BUFFER_DEPTH*32)-1:0] mcd_volume_history;
    wire [(BUFFER_DEPTH*32)-1:0] mcd_date_history;

    stock #(
        .BUFFER_DEPTH(BUFFER_DEPTH),
        .VOLATILITY(AMD_VOLATILITY),
        .SEED_FILE("storage/data/AMD_seed.mem")
        ) amd_stock_inst (
        .clk(clk),
        .rst(rst),
        .day_tick(day_tick),
        .market_state(market_state),
        .normalized_random(amd_random_value),
        .ready(amd_ready),
        .current_close(amd_current_close),
        .current_volume(amd_current_volume),
        .current_date(amd_current_date),
        .close_history(amd_close_history),
        .volume_history(amd_volume_history),
        .date_history(amd_date_history)
    );

    stock #(
        .BUFFER_DEPTH(BUFFER_DEPTH),
        .VOLATILITY(MCD_VOLATILITY),
        .SEED_FILE("storage/data/MCD_seed.mem")
        ) mcd_stock_inst (
        .clk(clk),
        .rst(rst),
        .day_tick(day_tick),
        .market_state(market_state),
        .normalized_random(mcd_random_value),
        .ready(mcd_ready),
        .current_close(mcd_current_close),
        .current_volume(mcd_current_volume),
        .current_date(mcd_current_date),
        .close_history(mcd_close_history),
        .volume_history(mcd_volume_history),
        .date_history(mcd_date_history)
    );

    // Each window is represented by 30 chronological subsection means.
    get_30_values #(
        .WINDOW(30),
        .TOTAL_DEPTH(BUFFER_DEPTH)
        ) amd_get_30_values_inst (
        .history_in(amd_close_history),
        .samples_out(amd_samples_30),
        .mean_out(amd_mean_30)
    );

    get_30_values #(
        .WINDOW(180),
        .TOTAL_DEPTH(BUFFER_DEPTH)
        ) amd_get_180_values_inst (
        .history_in(amd_close_history),
        .samples_out(amd_samples_180),
        .mean_out(amd_mean_180)
    );

    get_30_values #(
        .WINDOW(30),
        .TOTAL_DEPTH(BUFFER_DEPTH)
        ) mcd_get_30_values_inst (
        .history_in(mcd_close_history),
        .samples_out(mcd_samples_30),
        .mean_out(mcd_mean_30)
    );

    get_30_values #(
        .WINDOW(180),
        .TOTAL_DEPTH(BUFFER_DEPTH)
        ) mcd_get_180_values_inst (
        .history_in(mcd_close_history),
        .samples_out(mcd_samples_180),
        .mean_out(mcd_mean_180)
    );

endmodule
