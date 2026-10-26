`timescale 1ns / 1ps

// Small resource-friendly chart renderer.
//
// Frame x=2..93, y=28..54 (rows 3-5 of the text_grid layout). Inside it,
// 15 points of the 30-day history (every second day, newest at the right)
// are drawn as a step line in columns of 6 pixels, scaled against their own
// min/max with a power-of-two shift (no divider) to at most 24 pixels tall.
// A stock that is up over the period is green, down is red.
//
// chart_mode:
//   2'b00 = disabled
//   2'b01 = selected-stock chart
//   2'b10 = portfolio-value chart (newest point = live_value)
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
    localparam [5:0] TOP = 6'd28, BOTTOM = 6'd54;    // frame
    localparam [5:0] BASE = 6'd53;                   // lowest plotted line
    localparam [6:0] LEFT = 7'd2, RIGHT = 7'd93;

    reg [31:0] v [0:14];          // the 15 points, oldest first
    reg [31:0] min_v, max_v, range, cur, prev;
    reg [4:0]  shift;
    reg [3:0]  bin;
    reg [6:0]  bin_x0;
    reg [5:0]  h_cur, h_prev, y_cur, y_prev;
    integer    i, s;

    always @(*) begin
        pixel_active = 1'b0;
        pixel_color  = 16'h0000;

        // samples 1, 3, ..., 29 (29 is the newest)
        for (i = 0; i < 15; i = i + 1)
            v[i] = (chart_mode == MODE_STOCK) ? {16'd0, stock_samples[32*i + 16 +: 16]}
                                              : portfolio_samples[64*i + 32 +: 32];
        if (chart_mode == MODE_PORTFOLIO) v[14] = live_value;

        min_v = v[0];
        max_v = v[0];
        for (i = 1; i < 15; i = i + 1) begin
            if (v[i] < min_v) min_v = v[i];
            if (v[i] > max_v) max_v = v[i];
        end
        range = max_v - min_v;

        // smallest shift that fits the range in 24 pixels
        shift = 5'd24;
        for (s = 24; s >= 0; s = s - 1)
            if ((range >> s) <= 32'd24) shift = s;

        // which column of 6 pixels (x 3..92)
        bin = (pixel_x <= 7'd3) ? 4'd0 : (pixel_x - 7'd3) / 6;
        if (bin > 4'd14) bin = 4'd14;
        bin_x0 = 7'd3 + bin * 6;
        cur  = v[bin];
        prev = v[(bin == 4'd0) ? 4'd0 : bin - 4'd1];

        h_cur  = (range == 0) ? 6'd12 : (cur  - min_v) >> shift;
        h_prev = (range == 0) ? 6'd12 : (prev - min_v) >> shift;
        if (h_cur  > 6'd24) h_cur  = 6'd24;
        if (h_prev > 6'd24) h_prev = 6'd24;
        y_cur  = BASE - h_cur;
        y_prev = BASE - h_prev;

        if ((chart_mode != 2'b00) &&
            (pixel_x >= LEFT) && (pixel_x <= RIGHT) &&
            (pixel_y >= TOP)  && (pixel_y <= BOTTOM)) begin
            if ((pixel_x == LEFT) || (pixel_x == RIGHT) ||
                (pixel_y == TOP)  || (pixel_y == BOTTOM)) begin
                pixel_active = 1'b1;
                pixel_color  = 16'h4208;                 // grey frame
            end else if ((pixel_y == y_cur) ||
                         // the step up or down from the previous point
                         ((pixel_x == bin_x0) && (bin != 4'd0) &&
                          (((pixel_y >= y_prev) && (pixel_y <= y_cur)) ||
                           ((pixel_y <= y_prev) && (pixel_y >= y_cur))))) begin
                pixel_active = 1'b1;
                if (chart_mode == MODE_STOCK)
                    pixel_color = (v[14] >= v[0]) ? 16'h07E0 : 16'hF8A2;
                else
                    pixel_color = 16'h07FF;
            end
        end
    end
endmodule
