
`timescale 1ns / 1ps

// Hold a market state for five to twelve day ticks.
//
// State encoding:
//   2'b00 = bear
//   2'b01 = normal
//   2'b10 = bull
//   2'b11 = crash
module market_state(
    input wire       clk,
    input wire       rst,
    input wire       start,
    input wire       day_tick,
    input wire [1:0] random_state,
    input wire [2:0] random_interval,
    output reg [1:0] state = 2'b01
    );

    reg [3:0] days_in_state = 4'b0;
    reg [3:0] state_length = 4'd5;

    always @(posedge clk) begin
        if (rst) begin
            state <= 2'b01;
            days_in_state <= 4'b0;
            state_length <= 4'd5;
        end else if (start) begin
            state <= 2'b01;
            days_in_state <= 4'b0;
            state_length <= 4'd5 + random_interval;
        end else if (day_tick) begin
            if ((days_in_state + 1'b1) >= state_length) begin
                state <= random_state;
                days_in_state <= 4'b0;
                state_length <= 4'd5 + random_interval;
            end else begin
                days_in_state <= days_in_state + 1'b1;
            end
        end
    end

endmodule
