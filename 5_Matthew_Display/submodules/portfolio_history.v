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
    input  wire [15:0]                  price0,
    input  wire [15:0]                  price1,
    output wire [31:0]                  portfolio_value,
    output reg  [(SAMPLE_COUNT*32)-1:0] portfolio_samples
);

    wire [31:0] position_value0 = pos0 * price0;
    wire [31:0] position_value1 = pos1 * price1;
    wire [32:0] total_value = {1'b0, cash}
                            + {1'b0, position_value0}
                            + {1'b0, position_value1};

    assign portfolio_value = total_value[31:0];

    reg initialized;
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            initialized <= 1'b0;
            portfolio_samples <= {(SAMPLE_COUNT*32){1'b0}};
        end else if (!initialized) begin
            // Fill the first chart with a flat line instead of leading zeros.
            for (i = 0; i < SAMPLE_COUNT; i = i + 1) begin
                portfolio_samples[i*32 +: 32] <= portfolio_value;
            end
            initialized <= 1'b1;
        end else if (tick) begin
            for (i = 0; i < SAMPLE_COUNT-1; i = i + 1) begin
                portfolio_samples[i*32 +: 32]
                    <= portfolio_samples[(i+1)*32 +: 32];
            end
            portfolio_samples[(SAMPLE_COUNT-1)*32 +: 32]
                <= portfolio_value;
        end
    end

endmodule
