`timescale 1ns / 1ps

// Focused checks for the live chart compositor.  These tests exercise the
// same packed history format used by OLED_Renderer, rather than checking only
// that the module elaborates.
module tb_chart_renderer;

    reg  [6:0]   pixel_x;
    reg  [5:0]   pixel_y;
    reg  [1:0]   chart_mode;
    reg  [479:0] stock_samples;
    reg  [959:0] portfolio_samples;
    reg  [31:0]  live_value;
    wire         pixel_active;
    wire [15:0]  pixel_color;

    integer pass_count;
    integer fail_count;
    integer i;

    chart_renderer dut (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .chart_mode(chart_mode),
        .stock_samples(stock_samples),
        .portfolio_samples(portfolio_samples),
        .live_value(live_value),
        .pixel_active(pixel_active),
        .pixel_color(pixel_color)
    );

    task check;
        input condition;
        input [1023:0] message;
        begin
            if (condition) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s", message);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task set_portfolio_sample;
        input integer sample_index;
        input [31:0] sample_value;
        begin
            portfolio_samples[sample_index*32 +: 32] = sample_value;
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        pixel_x = 7'd8;
        pixel_y = 6'd32;
        chart_mode = 2'b00;
        stock_samples = 480'd0;
        portfolio_samples = 960'd0;
        live_value = 32'd0;
        #1;
        check(!pixel_active, "disabled chart produces no pixels");

        // A flat initialized portfolio history must be visible as a line in
        // the middle of the chart, not as a full-height saturated bar.
        chart_mode = 2'b10;
        for (i = 0; i < 30; i = i + 1)
            set_portfolio_sample(i, 32'd1000000);
        live_value = 32'd1000000;
        pixel_x = 7'd8;
        pixel_y = 6'd30;
        #1;
        check(pixel_active, "flat portfolio history draws a center line");
        pixel_y = 6'd24;
        #1;
        check(!pixel_active, "flat portfolio history does not fill the chart");

        // A changing history must use the full available range.  Sample 0
        // is the left/minimum bin; sample 4 is the second bin (x 15-25), the maximum.
        for (i = 0; i < 30; i = i + 1)
            set_portfolio_sample(i, 32'd1000000);
        set_portfolio_sample(4, 32'd1004608);
        live_value = 32'd1000000;

        pixel_x = 7'd8;
        pixel_y = 6'd36;
        #1;
        check(pixel_active, "minimum portfolio sample reaches the baseline");

        // Power-of-two scaling puts the highest sample in the top half of the
        // 13-pixel plot: range 4608 >> 9 = 9 pixels above the baseline (y 27).
        pixel_x = 7'd20;
        pixel_y = 6'd27;
        #1;
        check(pixel_active, "maximum portfolio sample drawn in the top half");

        // it is a line, not a filled bar: below the top of bin 1 is empty
        pixel_x = 7'd20;
        pixel_y = 6'd30;
        #1;
        check(!pixel_active, "the chart is a line, not a filled bar");

        // the step between bin 0 (low) and bin 1 (high) is drawn at bin 1's first column
        pixel_x = 7'd15;
        pixel_y = 6'd30;
        #1;
        check(pixel_active, "step from bin 0 up to bin 1 is drawn");

        // nothing outside the frame (x 4..91)
        pixel_x = 7'd2;
        pixel_y = 6'd36;
        #1;
        check(!pixel_active, "nothing drawn left of the frame");
        pixel_x = 7'd94;
        pixel_y = 6'd36;
        #1;
        check(!pixel_active, "nothing drawn right of the frame");

        if (fail_count == 0)
            $display("PASS: tb_chart_renderer (%0d checks)", pass_count);
        else
            $display("FAIL: tb_chart_renderer (%0d failed)", fail_count);
        $finish;
    end

endmodule
