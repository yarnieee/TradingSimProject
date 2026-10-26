`timescale 1ns / 1ps

// Small resource-friendly chart renderer.
//
// Eight samples of the 30-day history (every fourth day), drawn as a step
// line in a frame at x=4..91, y=22..37 (between the price line and the
// buttons on the specific-stock screen). The samples are scaled against their
// own min/max with a power-of-two shift, so no divider is needed. A rising
// stock is green, a falling one red.
//
// chart_mode:
//   2'b00 = disabled
//   2'b01 = selected-stock chart
//   2'b10 = portfolio-value chart
module chart_renderer (
    input  wire [6:0]  pixel_x,
    input  wire [5:0]  pixel_y,
    input  wire [1:0]  chart_mode,
    input  wire [479:0] stock_samples,
    input  wire [959:0] portfolio_samples,
    input  wire [31:0]  live_value,
    output reg          pixel_active,
    output reg  [15:0]  pixel_color
);

    localparam [1:0] MODE_STOCK     = 2'b01;
    localparam [1:0] MODE_PORTFOLIO = 2'b10;

    reg [2:0] x_bin;
    reg [31:0] sample_value [0:7];
    reg [31:0] selected_value;
    reg [31:0] min_value;
    reg [31:0] max_value;
    reg [31:0] value_range;
    reg [4:0] scale_shift;
    reg [5:0] point_height;
    reg [5:0] point_top;
    reg [31:0] prev_value;
    reg [5:0] prev_height;
    reg [5:0] prev_top;
    reg [6:0] bin_start;
    integer   s;

    always @(*) begin
        pixel_active = 1'b0;
        pixel_color  = 16'h0000;
        x_bin        = 3'd0;
        selected_value = 32'd0;
        min_value    = 32'd0;
        max_value    = 32'd0;
        value_range  = 32'd0;
        scale_shift  = 5'd0;
        point_height = 6'd0;
        point_top    = 6'd36;
        prev_value   = 32'd0;
        prev_height  = 6'd0;
        prev_top     = 6'd36;
        bin_start    = 7'd4;

        // Sample indices 0, 4, 8, ..., 28 keep the displayed bins
        // chronological while reducing the 30-point history to eight bars.
        if (chart_mode == MODE_STOCK) begin
            sample_value[0] = {16'd0, stock_samples[15:0]};
            sample_value[1] = {16'd0, stock_samples[79:64]};
            sample_value[2] = {16'd0, stock_samples[143:128]};
            sample_value[3] = {16'd0, stock_samples[207:192]};
            sample_value[4] = {16'd0, stock_samples[271:256]};
            sample_value[5] = {16'd0, stock_samples[335:320]};
            sample_value[6] = {16'd0, stock_samples[399:384]};
            sample_value[7] = {16'd0, stock_samples[463:448]};
        end else begin
            sample_value[0] = portfolio_samples[31:0];
            sample_value[1] = portfolio_samples[159:128];
            sample_value[2] = portfolio_samples[287:256];
            sample_value[3] = portfolio_samples[415:384];
            sample_value[4] = portfolio_samples[543:512];
            sample_value[5] = portfolio_samples[671:640];
            sample_value[6] = portfolio_samples[799:768];
            // Always include the live valuation as the newest point.  This
            // keeps the graph responsive immediately after a fill, without
            // waiting for another market-day sample to be shifted in.
            sample_value[7] = live_value;
        end

        min_value = sample_value[0];
        max_value = sample_value[0];
        if (sample_value[1] < min_value) min_value = sample_value[1];
        if (sample_value[2] < min_value) min_value = sample_value[2];
        if (sample_value[3] < min_value) min_value = sample_value[3];
        if (sample_value[4] < min_value) min_value = sample_value[4];
        if (sample_value[5] < min_value) min_value = sample_value[5];
        if (sample_value[6] < min_value) min_value = sample_value[6];
        if (sample_value[7] < min_value) min_value = sample_value[7];
        if (sample_value[1] > max_value) max_value = sample_value[1];
        if (sample_value[2] > max_value) max_value = sample_value[2];
        if (sample_value[3] > max_value) max_value = sample_value[3];
        if (sample_value[4] > max_value) max_value = sample_value[4];
        if (sample_value[5] > max_value) max_value = sample_value[5];
        if (sample_value[6] > max_value) max_value = sample_value[6];
        if (sample_value[7] > max_value) max_value = sample_value[7];
        value_range = max_value - min_value;

        // Smallest power-of-two scale that fits the range in the 13-pixel
        // plot height. Constant shifts only: no divider.
        scale_shift = 5'd24;
        for (s = 24; s >= 0; s = s - 1)
            if ((value_range >> s) <= 32'd13) scale_shift = s;

        if ((chart_mode == MODE_STOCK) ||
            (chart_mode == MODE_PORTFOLIO)) begin
            // The chart frame is x=4..91, y=22..37; eight bins of 11 columns.
            if (pixel_x >= 7'd4 && pixel_x <= 7'd91) begin
                if      (pixel_x < 7'd15) x_bin = 3'd0;
                else if (pixel_x < 7'd26) x_bin = 3'd1;
                else if (pixel_x < 7'd37) x_bin = 3'd2;
                else if (pixel_x < 7'd48) x_bin = 3'd3;
                else if (pixel_x < 7'd59) x_bin = 3'd4;
                else if (pixel_x < 7'd70) x_bin = 3'd5;
                else if (pixel_x < 7'd81) x_bin = 3'd6;
                else                       x_bin = 3'd7;
            end
            bin_start = (x_bin == 3'd0) ? 7'd4 : 7'd4 + 7'd11 * x_bin;

            selected_value = sample_value[x_bin];
            prev_value     = sample_value[(x_bin == 3'd0) ? 3'd0 : x_bin - 3'd1];

            // A flat history is drawn as a line across the middle.
            if (value_range == 0) begin
                point_top = 6'd30;
                prev_top  = 6'd30;
            end else begin
                point_height = (selected_value - min_value) >> scale_shift;
                prev_height  = (prev_value - min_value) >> scale_shift;
                if (point_height > 6'd13) point_height = 6'd13;
                if (prev_height > 6'd13)  prev_height = 6'd13;
                point_top = 6'd36 - point_height;
                prev_top  = 6'd36 - prev_height;
            end

            if ((pixel_y >= 6'd22) && (pixel_y <= 6'd37) &&
                (pixel_x >= 7'd4) && (pixel_x <= 7'd91)) begin
                if ((pixel_x == 7'd4) || (pixel_x == 7'd91) ||
                    (pixel_y == 6'd22) || (pixel_y == 6'd37)) begin
                    pixel_active = 1'b1;
                    pixel_color = 16'h4208;             // grey frame
                end else if ((pixel_y == point_top) ||
                             // the step up or down between two bins
                             ((pixel_x == bin_start) && (x_bin != 3'd0) &&
                              (((pixel_y >= prev_top) && (pixel_y <= point_top)) ||
                               ((pixel_y <= prev_top) && (pixel_y >= point_top))))) begin
                    pixel_active = 1'b1;
                    if (chart_mode == MODE_STOCK)
                        pixel_color = (sample_value[7] >= sample_value[0]) ? 16'h07E0 : 16'hF800;
                    else
                        pixel_color = 16'h07FF;
                end
            end
        end
    end

endmodule
