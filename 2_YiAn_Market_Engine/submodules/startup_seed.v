
`timescale 1ns / 1ps

// Produce a startup seed without exposing a manual seed input.
//
// The entropy counter is intentionally not reset.  A reset taken while the
// FPGA is running therefore captures a different counter/LFSR combination.
// This is a lightweight startup variation source, not a cryptographic RNG.
module startup_seed(
    input wire clk,
    input wire rst,
    output reg [31:0] seed = 32'h00000001,
    output reg seed_valid = 1'b0
    );

    reg [31:0] entropy_counter = 32'h13579BDF;
    reg [31:0] entropy_lfsr = 32'hA5A5C3C3;
    reg [4:0] capture_count = 5'b0;
    reg captured = 1'b0;
    wire entropy_feedback;

    assign entropy_feedback = entropy_lfsr[31] ^ entropy_lfsr[21]
        ^ entropy_lfsr[1] ^ entropy_lfsr[0];

    always @(posedge clk) begin
        entropy_counter <= entropy_counter + 1'b1;
        entropy_lfsr <= {entropy_lfsr[30:0], entropy_feedback}
            ^ entropy_counter;

        if (rst) begin
            capture_count <= 5'b0;
            captured <= 1'b0;
            seed_valid <= 1'b0;
        end else if (!captured) begin
            if (capture_count == 5'd15) begin
                seed <= entropy_counter ^ entropy_lfsr ^ 32'h9E3779B9;
                seed_valid <= 1'b1;
                captured <= 1'b1;
            end else begin
                capture_count <= capture_count + 1'b1;
                seed_valid <= 1'b0;
            end
        end else begin
            seed_valid <= 1'b0;
        end
    end

endmodule
