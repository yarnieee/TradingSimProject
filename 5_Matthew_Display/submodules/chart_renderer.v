`timescale 1ns / 1ps

// Pixel renderer for a compact 30-point line chart.
//
// chart_mode:
//   2'b00 = disabled
//   2'b01 = selected-stock chart
//   2'b10 = portfolio-value chart
//
// Stock samples and portfolio samples are both ordered oldest-first.
module chart_renderer (
    input  wire [6:0]  pixel_x,
    input  wire [5:0]  pixel_y,
    input  wire [1:0]  chart_mode,
    input  wire [479:0] stock_samples,
    input  wire [959:0] portfolio_samples,
    output reg          pixel_active,
    output reg  [15:0]  pixel_color
);

    localparam [1:0] MODE_STOCK     = 2'b01;
    localparam [1:0] MODE_PORTFOLIO = 2'b10;
    localparam integer SAMPLE_COUNT = 30;

    reg [31:0] values [0:SAMPLE_COUNT-1];
    reg [31:0] min_value;
    reg [31:0] max_value;

    integer i;
    integer x_left;
    integer x_right;
    integer y_top;
    integer y_bottom;
    integer chart_range;
    integer x0;
    integer x1;
    integer y0;
    integer y1;
    integer line_y;
    integer delta_y;
    integer scaled_value;

    always @(*) begin
        pixel_active = 1'b0;
        pixel_color  = 16'h0000;

        for (i = 0; i < SAMPLE_COUNT; i = i + 1) begin
            values[i] = 32'd0;
        end
        min_value = 32'd0;
        max_value = 32'd0;

        if ((chart_mode == MODE_STOCK) ||
            (chart_mode == MODE_PORTFOLIO)) begin
            for (i = 0; i < SAMPLE_COUNT; i = i + 1) begin
                if (chart_mode == MODE_STOCK)
                    values[i] = {16'd0, stock_samples[i*16 +: 16]};
                else
                    values[i] = portfolio_samples[i*32 +: 32];
            end

            min_value = values[0];
            max_value = values[0];
            for (i = 1; i < SAMPLE_COUNT; i = i + 1) begin
                if (values[i] < min_value) min_value = values[i];
                if (values[i] > max_value) max_value = values[i];
            end

            if (chart_mode == MODE_STOCK) begin
                x_left   = 4;
                x_right  = 91;
                y_top    = 23;
                y_bottom = 37;
            end else begin
                // Portfolio information is placed below the graph.
                x_left   = 4;
                x_right  = 91;
                y_top    = 23;
                y_bottom = 41;
            end

            chart_range = max_value - min_value;
            if (chart_range < 1) chart_range = 1;

            if ((pixel_x >= x_left) && (pixel_x <= x_right) &&
                (pixel_y >= y_top) && (pixel_y <= y_bottom)) begin
                // Dark blue grid and a thin cyan border create the neon-panel
                // background without obscuring the graph line.
                pixel_active = 1'b1;
                if ((pixel_x == x_left) || (pixel_x == x_right) ||
                    (pixel_y == y_top) || (pixel_y == y_bottom)) begin
                    pixel_color = 16'h07FF;
                end else if ((((pixel_x - x_left) % 8) == 0) ||
                             (((pixel_y - y_top) % 4) == 0)) begin
                    pixel_color = 16'h0010;
                end else begin
                    pixel_color = 16'h0000;
                end

                // Draw each segment with a two-pixel thickness so it remains
                // visible on the 96x64 OLED.
                for (i = 0; i < SAMPLE_COUNT-1; i = i + 1) begin
                    x0 = x_left + (i * (x_right-x_left)) / (SAMPLE_COUNT-1);
                    x1 = x_left + ((i+1) * (x_right-x_left)) /
                         (SAMPLE_COUNT-1);

                    if (max_value == min_value) begin
                        y0 = (y_top + y_bottom) / 2;
                        y1 = y0;
                    end else begin
                        scaled_value = (values[i] - min_value)
                                     * (y_bottom-y_top);
                        y0 = y_bottom - (scaled_value / chart_range);
                        scaled_value = (values[i+1] - min_value)
                                     * (y_bottom-y_top);
                        y1 = y_bottom - (scaled_value / chart_range);
                    end

                    if ((pixel_x >= x0) && (pixel_x <= x1)) begin
                        delta_y = y1 - y0;
                        if (x1 == x0)
                            line_y = y0;
                        else
                            line_y = y0 + (((pixel_x-x0) * delta_y) /
                                           (x1-x0));

                        if ((pixel_y >= line_y-1) &&
                            (pixel_y <= line_y+1)) begin
                            if (chart_mode == MODE_STOCK)
                                pixel_color = 16'h07E0; // neon green
                            else
                                pixel_color = 16'h07FF; // neon cyan
                        end
                    end
                end
            end
        end
    end

endmodule
