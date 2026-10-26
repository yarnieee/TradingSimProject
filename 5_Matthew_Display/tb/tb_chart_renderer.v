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

    // Chart frame x 2..93, y 28..54; lowest line y 53; columns of 6 pixels
    // from x 3 (column b shows sample 2b+1; the last one shows live_value).
    initial begin
        pass_count = 0;
        fail_count = 0;
        pixel_x = 7'd8;
        pixel_y = 6'd41;
        chart_mode = 2'b00;
        stock_samples = 480'd0;
        portfolio_samples = 960'd0;
        live_value = 32'd0;
        #1;
        check(!pixel_active, "disabled chart produces no pixels");

        // A flat history is a line across the middle (12 above the bottom: y 41).
        chart_mode = 2'b10;
        for (i = 0; i < 30; i = i + 1)
            set_portfolio_sample(i, 32'd1000000);
        live_value = 32'd1000000;
        pixel_x = 7'd8;
        pixel_y = 6'd41;
        #1;
        check(pixel_active, "flat history draws a centre line");
        pixel_y = 6'd30;
        #1;
        check(!pixel_active, "flat history does not fill the chart");

        // Sample 3 (column 1, x 9..14) is the maximum; everything else the minimum.
        // range 4608 >> 8 = 18 pixels above the bottom line: y 35.
        set_portfolio_sample(3, 32'd1004608);
        pixel_x = 7'd5;  pixel_y = 6'd53; #1;
        check(pixel_active, "minimum sample sits on the bottom line");
        pixel_x = 7'd11; pixel_y = 6'd35; #1;
        check(pixel_active, "maximum sample drawn 18 pixels up");
        pixel_x = 7'd11; pixel_y = 6'd45; #1;
        check(!pixel_active, "the chart is a line, not a filled bar");
        pixel_x = 7'd9;  pixel_y = 6'd45; #1;
        check(pixel_active, "step from column 0 up to column 1 is drawn");
        pixel_x = 7'd2;  pixel_y = 6'd40; #1;
        check(pixel_active && pixel_color == 16'h4208, "grey frame on the left edge");
        pixel_x = 7'd1;  pixel_y = 6'd53; #1;
        check(!pixel_active, "nothing drawn left of the frame");
        pixel_x = 7'd95; pixel_y = 6'd53; #1;
        check(!pixel_active, "nothing drawn right of the frame");

        if (fail_count == 0)
            $display("PASS: tb_chart_renderer (%0d checks)", pass_count);
        else
            $display("FAIL: tb_chart_renderer (%0d failed)", fail_count);
        $finish;
    end

endmodule
