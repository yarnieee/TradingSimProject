
`timescale 1ns / 1ps

// Divide a trailing history window into 30 uniformly sized subsections.
//
// The input history stores index 0 as the newest value.  samples_out[0] is
// the oldest subsection and samples_out[29] is the newest subsection.  Each
// output is the integer mean of its subsection.
module get_30_values #(
    parameter integer WINDOW = 30,
    parameter integer TOTAL_DEPTH = 1800,
    parameter integer WIDTH = 16,
    parameter integer SAMPLE_COUNT = 30
    )(
    input wire [(TOTAL_DEPTH*WIDTH)-1:0] history_in,
    output reg [(SAMPLE_COUNT*WIDTH)-1:0] samples_out,
    output reg [WIDTH-1:0] mean_out
    );

    localparam integer SEGMENT_SIZE = WINDOW / SAMPLE_COUNT;
    localparam integer SAMPLE_SUM_WIDTH = WIDTH + $clog2(SEGMENT_SIZE + 1) + 1;
    localparam integer TOTAL_SUM_WIDTH = WIDTH + $clog2(WINDOW + 1) + 1;

    reg [SAMPLE_SUM_WIDTH-1:0] sample_sums [0:SAMPLE_COUNT-1];
    reg [TOTAL_SUM_WIDTH-1:0] total_sum;

    integer sample_index;
    integer value_index;
    integer history_index;

    always @(*) begin
        samples_out = {(SAMPLE_COUNT*WIDTH){1'b0}};
        mean_out = {WIDTH{1'b0}};
        total_sum = {TOTAL_SUM_WIDTH{1'b0}};

        for (sample_index = 0; sample_index < SAMPLE_COUNT;
            sample_index = sample_index + 1) begin
            sample_sums[sample_index] = {SAMPLE_SUM_WIDTH{1'b0}};

            for (value_index = 0; value_index < SEGMENT_SIZE;
                value_index = value_index + 1) begin
                // Reverse the newest-first buffer so the displayed samples
                // progress chronologically from oldest to newest.
                history_index = WINDOW - 1
                    - (sample_index * SEGMENT_SIZE + value_index);
                sample_sums[sample_index] = sample_sums[sample_index]
                    + history_in[history_index*WIDTH +: WIDTH];
            end

            samples_out[sample_index*WIDTH +: WIDTH]
                = sample_sums[sample_index] / SEGMENT_SIZE;
            total_sum = total_sum + sample_sums[sample_index];
        end

        mean_out = total_sum / WINDOW;
    end

endmodule
