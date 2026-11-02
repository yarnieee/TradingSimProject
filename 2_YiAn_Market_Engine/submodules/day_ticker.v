
`timescale 1ns / 1ps

// Generate a one-clock enable pulse at the requested day interval.
// With a 100 MHz input clock, the default is one pulse every two seconds.
module day_ticker #(
    parameter integer MAX_COUNT = 199_999_999
    )(
    input wire clk,
    input wire rst,
    output reg tick = 1'b0
    );

    reg [31:0] counter = 32'b0;

    always @(posedge clk) begin
        if (rst) begin
            counter <= 32'b0;
            tick <= 1'b0;
        end else if (counter == MAX_COUNT) begin
            counter <= 32'b0;
            tick <= 1'b1;
        end else begin
            counter <= counter + 1'b1;
            tick <= 1'b0;
        end
    end

endmodule
