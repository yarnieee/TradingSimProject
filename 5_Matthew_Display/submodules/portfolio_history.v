`timescale 1ns / 1ps

// Keep the portfolio value for the most recent SAMPLE_COUNT trading ticks.
// Values are stored oldest-first so the display can use index 0 as the left
// side of a chart and index SAMPLE_COUNT-1 as the newest value.
module portfolio_history #(
    parameter integer SAMPLE_COUNT = 30
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         tick,
    input  wire [31:0]                  cash,
    input  wire [9:0]                   pos0,
    input  wire [9:0]                   pos1,
    input  wire [9:0]                   pos2,
    input  wire [9:0]                   pos3,
    input  wire [15:0]                  price0,
    input  wire [15:0]                  price1,
    input  wire [15:0]                  price2,
    input  wire [15:0]                  price3,
    output wire [31:0]                  portfolio_value,
    output reg  [(SAMPLE_COUNT*32)-1:0] portfolio_samples
);

    // Net worth = cash + the four positions at their prices, worked out in
    // registered steps (inputs, products, two partial sums, total) so no
    // multiply-and-add chain has to finish in one 10 ns clock. portfolio_value
    // follows cash / positions / prices LATENCY clocks later.
    // Each tick stores one sample: the new day's value when it arrives (the
    // value-change push), or, if the value has not changed by TICK_WAIT clocks
    // after the tick, the unchanged value then.
    localparam integer LATENCY = 4;
    localparam integer TICK_WAIT = LATENCY + 2;
    reg [31:0] c_a, c_b;
    reg [9:0]  q_a0, q_a1, q_a2, q_a3;
    reg [15:0] p_a0, p_a1, p_a2, p_a3;
    reg [25:0] m0, m1, m2, m3;                 // 1023 x 65535 fits in 26 bits
    reg [31:0] s_a, s_b;
    reg [31:0] value_r;
    reg [TICK_WAIT-1:0] tick_d;
    reg [2:0]  warm;                           // clocks since reset, until the steps are full
    always @(posedge clk) begin
        c_a  <= cash;
        q_a0 <= pos0;   q_a1 <= pos1;   q_a2 <= pos2;   q_a3 <= pos3;
        p_a0 <= price0; p_a1 <= price1; p_a2 <= price2; p_a3 <= price3;
        c_b  <= c_a;
        m0   <= q_a0 * p_a0; m1 <= q_a1 * p_a1; m2 <= q_a2 * p_a2; m3 <= q_a3 * p_a3;
        s_a  <= c_b + m0 + m1;
        s_b  <= m2 + m3;
        value_r <= s_a + s_b;
        if (rst) begin
            tick_d <= {TICK_WAIT{1'b0}};
            warm   <= 3'd0;
        end else begin
            tick_d <= {tick_d[TICK_WAIT-2:0], tick};
            if (warm != LATENCY) warm <= warm + 3'd1;
        end
    end

    assign portfolio_value = value_r;

    reg initialized;
    reg day_pending;                           // a tick whose sample is not stored yet
    wire [31:0] newest_sample = portfolio_samples[(SAMPLE_COUNT*32)-1:((SAMPLE_COUNT-1)*32)];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            initialized <= 1'b0;
            day_pending <= 1'b0;
            portfolio_samples <= {(SAMPLE_COUNT*32){1'b0}};
        end else if (!initialized) begin
            if (warm == LATENCY) begin
                // Fill the first chart with a flat line instead of leading zeros.
                for (i = 0; i < SAMPLE_COUNT; i = i + 1) begin
                    portfolio_samples[i*32 +: 32] <= portfolio_value;
                end
                initialized <= 1'b1;
            end
        end else if ((day_pending && tick_d[TICK_WAIT-1]) || (portfolio_value != newest_sample)) begin
            // Keep the history in one fixed-width shift.  Using a variable
            // part-select inside a procedural loop makes Vivado infer a
            // large run-time mux for every stored bit; explicit slices keep
            // the same oldest-to-newest ordering with simple wiring.  The
            // value-change condition also captures fills immediately, so the
            // portfolio graph reflects the current valuation instead of only
            // changing at the next simulated trading day.
            portfolio_samples <= {portfolio_value,
                                  portfolio_samples[(SAMPLE_COUNT*32)-1:32]};
            day_pending <= tick;
        end else if (tick)
            day_pending <= 1'b1;
    end

endmodule
