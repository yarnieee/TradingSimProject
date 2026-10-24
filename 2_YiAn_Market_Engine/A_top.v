
`timescale 1ns / 1ps

// Storage-system top module.
//
// Four independent random sources drive four stock channels. Dedicated LFSRs
// supply market-state choices and the five-to-twelve-day market-state
// duration. Each stock loads its latest 180 CSV records before it starts
// accepting two-second day ticks.
module A_top #(
    parameter integer DAY_MAX_COUNT = 199_999_999,
    parameter integer BUFFER_DEPTH = 180,
    // Per-stock behavior parameters.  The STOCK2/STOCK3 aliases preserve
    // the generic names introduced with the four-channel interface.
    parameter integer AMD_VOLATILITY = 10,
    parameter integer MCD_VOLATILITY = 8,
    parameter integer NVDA_VOLATILITY = 14,
    parameter integer GME_VOLATILITY = 20,
    parameter integer STOCK2_VOLATILITY = NVDA_VOLATILITY,
    parameter integer STOCK3_VOLATILITY = GME_VOLATILITY,
    parameter STOCK0_SEED_FILE = "storage/data/AMD_seed.mem",
    parameter STOCK1_SEED_FILE = "storage/data/MCD_seed.mem",
    parameter STOCK2_SEED_FILE = "storage/data/NVDA_seed.mem",
    parameter STOCK3_SEED_FILE = "storage/data/GME_seed.mem",
    // All four seed files end on Friday, 2025-12-19.
    // Keeping the seed date components as parameters avoids synthesizing
    // binary divide/modulo hardware merely to find the next trading day.
    parameter integer INITIAL_YEAR = 2025,
    parameter integer INITIAL_MONTH = 12,
    parameter integer INITIAL_DAY = 19,
    parameter integer INITIAL_WEEKDAY = 6
    )(
    input wire clk,
    input wire rst,
    output wire [1:0] market_state,
    output wire [2:0] market_event,
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
    output wire [15:0] mcd_mean_180,
    // Generic four-stock interface. stock0/stock1 mirror the legacy AMD/MCD
    // channels; stock2/stock3 use the NVDA/GME seed files below.
    output wire stock0_ready,
    output wire [15:0] stock0_current_close,
    output wire [31:0] stock0_current_volume,
    output wire [31:0] stock0_current_date,
    output wire [(30*16)-1:0] stock0_samples_30,
    output wire [(30*16)-1:0] stock0_samples_180,
    output wire [15:0] stock0_mean_30,
    output wire [15:0] stock0_mean_180,
    output wire stock1_ready,
    output wire [15:0] stock1_current_close,
    output wire [31:0] stock1_current_volume,
    output wire [31:0] stock1_current_date,
    output wire [(30*16)-1:0] stock1_samples_30,
    output wire [(30*16)-1:0] stock1_samples_180,
    output wire [15:0] stock1_mean_30,
    output wire [15:0] stock1_mean_180,
    output wire stock2_ready,
    output wire [15:0] stock2_current_close,
    output wire [31:0] stock2_current_volume,
    output wire [31:0] stock2_current_date,
    output wire [(30*16)-1:0] stock2_samples_30,
    output wire [(30*16)-1:0] stock2_samples_180,
    output wire [15:0] stock2_mean_30,
    output wire [15:0] stock2_mean_180,
    output wire stock3_ready,
    output wire [15:0] stock3_current_close,
    output wire [31:0] stock3_current_volume,
    output wire [31:0] stock3_current_date,
    output wire [(30*16)-1:0] stock3_samples_30,
    output wire [(30*16)-1:0] stock3_samples_180,
    output wire [15:0] stock3_mean_30,
    output wire [15:0] stock3_mean_180
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

    // Distinct derivations keep the seven random streams independent while
    // avoiding a user-configurable seed input.
    wire [31:0] amd_lfsr_seed;
    wire [31:0] mcd_lfsr_seed;
    wire [31:0] stock2_lfsr_seed;
    wire [31:0] stock3_lfsr_seed;
    wire [31:0] market_lfsr_seed;
    wire [31:0] interval_lfsr_seed;
    wire [31:0] event_lfsr_seed;

    assign amd_lfsr_seed = startup_random_seed ^ 32'h13579BDF;
    assign mcd_lfsr_seed = startup_random_seed ^ 32'h2468ACE1;
    assign stock2_lfsr_seed = startup_random_seed ^ 32'h5A5AA5A5;
    assign stock3_lfsr_seed = startup_random_seed ^ 32'hA5A55A5A;
    assign market_lfsr_seed = startup_random_seed ^ 32'h89ABCDEF;
    assign interval_lfsr_seed = startup_random_seed ^ 32'h0F1E2D3C;
    assign event_lfsr_seed = startup_random_seed ^ 32'hC3D2E1F0;

    wire [31:0] amd_lfsr_value;
    wire [31:0] mcd_lfsr_value;
    wire [31:0] stock2_lfsr_value;
    wire [31:0] stock3_lfsr_value;
    wire [31:0] market_lfsr_value;
    wire [31:0] interval_lfsr_value;
    wire [31:0] event_lfsr_value;
    wire [7:0] amd_random_value;
    wire [7:0] mcd_random_value;
    wire [7:0] stock2_random_value;
    wire [7:0] stock3_random_value;

    wire all_stocks_ready;
    assign all_stocks_ready = stock0_ready && stock1_ready
        && stock2_ready && stock3_ready;

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

    lfsr stock2_lfsr_inst (
        .clk(clk),
        .rst(rst),
        .en(day_tick && stock2_ready),
        .load(startup_seed_valid),
        .seed(stock2_lfsr_seed),
        .q(stock2_lfsr_value)
    );

    lfsr stock3_lfsr_inst (
        .clk(clk),
        .rst(rst),
        .en(day_tick && stock3_ready),
        .load(startup_seed_valid),
        .seed(stock3_lfsr_seed),
        .q(stock3_lfsr_value)
    );

    lfsr market_lfsr_inst (
        .clk(clk),
        .rst(rst),
        .en(day_tick && all_stocks_ready),
        .load(startup_seed_valid),
        .seed(market_lfsr_seed),
        .q(market_lfsr_value)
    );

    lfsr interval_lfsr_inst (
        .clk(clk),
        .rst(rst),
        .en(day_tick && all_stocks_ready),
        .load(startup_seed_valid),
        .seed(interval_lfsr_seed),
        .q(interval_lfsr_value)
    );

    lfsr event_lfsr_inst (
        .clk(clk),
        .rst(rst),
        .en(day_tick && all_stocks_ready),
        .load(startup_seed_valid),
        .seed(event_lfsr_seed),
        .q(event_lfsr_value)
    );

    wire [2:0] market_event_request;
    market_events market_events_inst (
        .random_value(event_lfsr_value[7:0]),
        .event_request(market_event_request)
    );

    normalise_lfsr amd_normalise_lfsr_inst (
        .lfsr_value(amd_lfsr_value),
        .normalized(amd_random_value)
    );

    normalise_lfsr mcd_normalise_lfsr_inst (
        .lfsr_value(mcd_lfsr_value),
        .normalized(mcd_random_value)
    );

    normalise_lfsr stock2_normalise_lfsr_inst (
        .lfsr_value(stock2_lfsr_value),
        .normalized(stock2_random_value)
    );

    normalise_lfsr stock3_normalise_lfsr_inst (
        .lfsr_value(stock3_lfsr_value),
        .normalized(stock3_random_value)
    );

    market_state market_state_inst (
        .clk(clk),
        .rst(rst),
        .start(startup_seed_valid),
        .day_tick(day_tick && all_stocks_ready),
        .random_state(market_lfsr_value[1:0]),
        .random_interval(interval_lfsr_value[2:0]),
        .event_request(market_event_request),
        .state(market_state),
        .active_event(market_event)
    );

    wire [(BUFFER_DEPTH*16)-1:0] amd_close_history;
    wire [(BUFFER_DEPTH*32)-1:0] amd_volume_history;
    wire [(BUFFER_DEPTH*32)-1:0] amd_date_history;
    wire [(BUFFER_DEPTH*16)-1:0] mcd_close_history;
    wire [(BUFFER_DEPTH*32)-1:0] mcd_volume_history;
    wire [(BUFFER_DEPTH*32)-1:0] mcd_date_history;
    wire [(BUFFER_DEPTH*16)-1:0] stock2_close_history;
    wire [(BUFFER_DEPTH*32)-1:0] stock2_volume_history;
    wire [(BUFFER_DEPTH*32)-1:0] stock2_date_history;
    wire [(BUFFER_DEPTH*16)-1:0] stock3_close_history;
    wire [(BUFFER_DEPTH*32)-1:0] stock3_volume_history;
    wire [(BUFFER_DEPTH*32)-1:0] stock3_date_history;

    stock #(
        .BUFFER_DEPTH(BUFFER_DEPTH),
        .VOLATILITY(AMD_VOLATILITY),
        .INITIAL_YEAR(INITIAL_YEAR),
        .INITIAL_MONTH(INITIAL_MONTH),
        .INITIAL_DAY(INITIAL_DAY),
        .INITIAL_WEEKDAY(INITIAL_WEEKDAY),
        .SEED_FILE(STOCK0_SEED_FILE)
        ) amd_stock_inst (
        .clk(clk),
        .rst(rst),
        .day_tick(day_tick),
        .market_state(market_state),
        .normalized_random(amd_random_value),
        .ready(stock0_ready),
        .current_close(stock0_current_close),
        .current_volume(stock0_current_volume),
        .current_date(stock0_current_date),
        .close_history(amd_close_history),
        .volume_history(amd_volume_history),
        .date_history(amd_date_history)
    );

    stock #(
        .BUFFER_DEPTH(BUFFER_DEPTH),
        .VOLATILITY(MCD_VOLATILITY),
        .INITIAL_YEAR(INITIAL_YEAR),
        .INITIAL_MONTH(INITIAL_MONTH),
        .INITIAL_DAY(INITIAL_DAY),
        .INITIAL_WEEKDAY(INITIAL_WEEKDAY),
        .SEED_FILE(STOCK1_SEED_FILE)
        ) mcd_stock_inst (
        .clk(clk),
        .rst(rst),
        .day_tick(day_tick),
        .market_state(market_state),
        .normalized_random(mcd_random_value),
        .ready(stock1_ready),
        .current_close(stock1_current_close),
        .current_volume(stock1_current_volume),
        .current_date(stock1_current_date),
        .close_history(mcd_close_history),
        .volume_history(mcd_volume_history),
        .date_history(mcd_date_history)
    );

    stock #(
        .BUFFER_DEPTH(BUFFER_DEPTH),
        .VOLATILITY(STOCK2_VOLATILITY),
        .INITIAL_YEAR(INITIAL_YEAR),
        .INITIAL_MONTH(INITIAL_MONTH),
        .INITIAL_DAY(INITIAL_DAY),
        .INITIAL_WEEKDAY(INITIAL_WEEKDAY),
        .SEED_FILE(STOCK2_SEED_FILE)
        ) stock2_inst (
        .clk(clk),
        .rst(rst),
        .day_tick(day_tick),
        .market_state(market_state),
        .normalized_random(stock2_random_value),
        .ready(stock2_ready),
        .current_close(stock2_current_close),
        .current_volume(stock2_current_volume),
        .current_date(stock2_current_date),
        .close_history(stock2_close_history),
        .volume_history(stock2_volume_history),
        .date_history(stock2_date_history)
    );

    stock #(
        .BUFFER_DEPTH(BUFFER_DEPTH),
        .VOLATILITY(STOCK3_VOLATILITY),
        .INITIAL_YEAR(INITIAL_YEAR),
        .INITIAL_MONTH(INITIAL_MONTH),
        .INITIAL_DAY(INITIAL_DAY),
        .INITIAL_WEEKDAY(INITIAL_WEEKDAY),
        .SEED_FILE(STOCK3_SEED_FILE)
        ) stock3_inst (
        .clk(clk),
        .rst(rst),
        .day_tick(day_tick),
        .market_state(market_state),
        .normalized_random(stock3_random_value),
        .ready(stock3_ready),
        .current_close(stock3_current_close),
        .current_volume(stock3_current_volume),
        .current_date(stock3_current_date),
        .close_history(stock3_close_history),
        .volume_history(stock3_volume_history),
        .date_history(stock3_date_history)
    );

    // Legacy AMD/MCD names remain aliases for stock0/stock1.
    assign amd_ready = stock0_ready;
    assign amd_current_close = stock0_current_close;
    assign amd_current_volume = stock0_current_volume;
    assign amd_current_date = stock0_current_date;
    assign mcd_ready = stock1_ready;
    assign mcd_current_close = stock1_current_close;
    assign mcd_current_volume = stock1_current_volume;
    assign mcd_current_date = stock1_current_date;

    // Each window is represented by 30 chronological subsection means.
    get_30_values #(
        .WINDOW(30),
        .TOTAL_DEPTH(BUFFER_DEPTH)
        ) amd_get_30_values_inst (
        .history_in(amd_close_history),
        .samples_out(stock0_samples_30),
        .mean_out(stock0_mean_30)
    );

    get_30_values #(
        .WINDOW(180),
        .TOTAL_DEPTH(BUFFER_DEPTH)
        ) amd_get_180_values_inst (
        .history_in(amd_close_history),
        .samples_out(stock0_samples_180),
        .mean_out(stock0_mean_180)
    );

    get_30_values #(
        .WINDOW(30),
        .TOTAL_DEPTH(BUFFER_DEPTH)
        ) mcd_get_30_values_inst (
        .history_in(mcd_close_history),
        .samples_out(stock1_samples_30),
        .mean_out(stock1_mean_30)
    );

    get_30_values #(
        .WINDOW(180),
        .TOTAL_DEPTH(BUFFER_DEPTH)
        ) mcd_get_180_values_inst (
        .history_in(mcd_close_history),
        .samples_out(stock1_samples_180),
        .mean_out(stock1_mean_180)
    );

    get_30_values #(
        .WINDOW(30),
        .TOTAL_DEPTH(BUFFER_DEPTH)
        ) stock2_get_30_values_inst (
        .history_in(stock2_close_history),
        .samples_out(stock2_samples_30),
        .mean_out(stock2_mean_30)
    );

    get_30_values #(
        .WINDOW(180),
        .TOTAL_DEPTH(BUFFER_DEPTH)
        ) stock2_get_180_values_inst (
        .history_in(stock2_close_history),
        .samples_out(stock2_samples_180),
        .mean_out(stock2_mean_180)
    );

    get_30_values #(
        .WINDOW(30),
        .TOTAL_DEPTH(BUFFER_DEPTH)
        ) stock3_get_30_values_inst (
        .history_in(stock3_close_history),
        .samples_out(stock3_samples_30),
        .mean_out(stock3_mean_30)
    );

    get_30_values #(
        .WINDOW(180),
        .TOTAL_DEPTH(BUFFER_DEPTH)
        ) stock3_get_180_values_inst (
        .history_in(stock3_close_history),
        .samples_out(stock3_samples_180),
        .mean_out(stock3_mean_180)
    );

    // Legacy sample/mean names remain aliases for stock0/stock1.
    assign amd_samples_30 = stock0_samples_30;
    assign amd_samples_180 = stock0_samples_180;
    assign amd_mean_30 = stock0_mean_30;
    assign amd_mean_180 = stock0_mean_180;
    assign mcd_samples_30 = stock1_samples_30;
    assign mcd_samples_180 = stock1_samples_180;
    assign mcd_mean_30 = stock1_mean_30;
    assign mcd_mean_180 = stock1_mean_180;

endmodule
