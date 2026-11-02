
`timescale 1ns / 1ps

// Convert a 32-bit LFSR state into a value from 0 to 100.
// The four bytes are summed first, giving a range of 0 to 1020.
module normalise_lfsr(
    input wire [31:0] lfsr_value,
    output wire [7:0] normalized
    );

    wire [9:0] byte_sum;
    wire [17:0] scaled_sum;
    wire [17:0] normalized_value;

    assign byte_sum = {2'b0, lfsr_value[31:24]}
        + {2'b0, lfsr_value[23:16]}
        + {2'b0, lfsr_value[15:8]}
        + {2'b0, lfsr_value[7:0]};
    // 25/256 is a close, divider-free approximation of 100/1020.
    // The rounding constant makes the upper endpoint map to exactly 100.
    assign scaled_sum = (byte_sum * 18'd25) + 18'd127;
    assign normalized_value = scaled_sum >> 8;
    assign normalized = (normalized_value > 18'd100)
        ? 8'd100
        : normalized_value[7:0];

endmodule
