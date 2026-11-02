
`timescale 1ns / 1ps

// Fibonacci LFSR with an optional runtime seed load.
//
// The default taps implement q[31] ^ q[21] ^ q[1] ^ q[0] for the 32-bit
// instances used by the storage system.  The tap mask remains a parameter so
// that smaller instances can be used for other random sources.
module lfsr #(
    parameter integer N = 32,
    parameter [N-1:0] TAP_MASK = 32'h80200003,
    parameter [N-1:0] SEED = 32'h00000001
    )(
    input wire             clk,
    input wire             rst,
    input wire             en,
    input wire             load,
    input wire [N-1:0]     seed,
    output reg [N-1:0]     q
    );

    wire feedback;
    assign feedback = ^(q & TAP_MASK);

    always @(posedge clk) begin
        if (rst) begin
            q <= SEED;
        end else if (load) begin
            // Avoid entering the all-zero lock-up state.
            q <= (seed == {N{1'b0}}) ? SEED : seed;
        end else if (en) begin
            q <= {q[N-2:0], feedback};
        end
    end

endmodule
