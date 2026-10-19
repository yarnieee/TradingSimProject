
`timescale 1ns / 1ps

// Return the newest X values from a stock history buffer.
//
// The history input uses index 0 for the newest value.  The output preserves
// that ordering, so latest_values[WIDTH-1:0] is the newest value.  X is
// intended to be in the range 1 to 30.
module get_latest_values #(
    parameter integer X = 8,
    parameter integer MAX_X = 30,
    parameter integer TOTAL_DEPTH = 180,
    parameter integer WIDTH = 16
    )(
    input wire [(TOTAL_DEPTH*WIDTH)-1:0] history_in,
    output reg [(X*WIDTH)-1:0] latest_values
    );

    integer i;

    initial begin
        if ((X < 1) || (X > MAX_X)) begin
            $display("ERROR get_latest_values: X must be between 1 and %0d", MAX_X);
        end
    end

    always @(*) begin
        latest_values = {(X*WIDTH){1'b0}};
        for (i = 0; i < X; i = i + 1) begin
            latest_values[i*WIDTH +: WIDTH]
                = history_in[i*WIDTH +: WIDTH];
        end
    end

endmodule
