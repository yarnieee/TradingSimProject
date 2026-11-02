
`timescale 1ns / 1ps

// Divide a trailing history window into SAMPLE_COUNT chronological subsections.
//
// The input history stores index 0 as the newest value.  samples_out[0] is
// the oldest subsection and samples_out[SAMPLE_COUNT-1] is the newest
// subsection.  Each output is the integer mean of its subsection.  The
// subsection boundaries use proportional integer positions, so a window does
// not silently drop samples when WINDOW is not divisible by SAMPLE_COUNT.
module get_30_values #(
    parameter integer WINDOW = 30,
    parameter integer TOTAL_DEPTH = 180,
    parameter integer WIDTH = 16,
    parameter integer SAMPLE_COUNT = 30
    )(
    input wire [(TOTAL_DEPTH*WIDTH)-1:0] history_in,
    output reg [(SAMPLE_COUNT*WIDTH)-1:0] samples_out,
    output reg [WIDTH-1:0] mean_out
    );

    localparam integer MAX_SEGMENT_SIZE = (WINDOW + SAMPLE_COUNT - 1)
        / SAMPLE_COUNT;
    localparam integer SAMPLE_SUM_WIDTH = WIDTH
        + $clog2(MAX_SEGMENT_SIZE + 1) + 1;
    localparam integer TOTAL_SUM_WIDTH = WIDTH + $clog2(WINDOW + 1) + 1;

    reg [SAMPLE_SUM_WIDTH-1:0] sample_sums [0:SAMPLE_COUNT-1];
    reg [TOTAL_SUM_WIDTH-1:0] total_sum;

    integer sample_index;
    integer value_index;
    integer history_index;
    integer segment_start;
    integer segment_end;
    integer segment_count;

    initial begin
        if ((WINDOW < 1) || (WINDOW > TOTAL_DEPTH)) begin
            $display("ERROR get_30_values: WINDOW must be between 1 and %0d",
                TOTAL_DEPTH);
        end
        if ((SAMPLE_COUNT < 1) || (SAMPLE_COUNT > WINDOW)) begin
            $display("ERROR get_30_values: SAMPLE_COUNT must be between 1 and WINDOW");
        end
    end

    always @(*) begin
        samples_out = {(SAMPLE_COUNT*WIDTH){1'b0}};
        mean_out = {WIDTH{1'b0}};
        total_sum = {TOTAL_SUM_WIDTH{1'b0}};

        for (sample_index = 0; sample_index < SAMPLE_COUNT;
            sample_index = sample_index + 1) begin
            sample_sums[sample_index] = {SAMPLE_SUM_WIDTH{1'b0}};

            // Proportional boundaries distribute any remainder across the
            // later buckets while keeping every history entry in the window.
            segment_start = (sample_index * WINDOW) / SAMPLE_COUNT;
            segment_end = ((sample_index + 1) * WINDOW) / SAMPLE_COUNT;
            segment_count = segment_end - segment_start;

            for (value_index = segment_start; value_index < segment_end;
                value_index = value_index + 1) begin
                // Reverse the newest-first buffer so the displayed samples
                // progress chronologically from oldest to newest.
                history_index = WINDOW - 1 - value_index;
                sample_sums[sample_index] = sample_sums[sample_index]
                    + history_in[history_index*WIDTH +: WIDTH];
            end

            samples_out[sample_index*WIDTH +: WIDTH]
                = sample_sums[sample_index] / segment_count;
            total_sum = total_sum + sample_sums[sample_index];
        end

        mean_out = total_sum / WINDOW;
    end

endmodule
