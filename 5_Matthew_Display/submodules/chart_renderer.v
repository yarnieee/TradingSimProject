`timescale 1ns / 1ps

// Small resource-friendly chart renderer.
//
// The original renderer calculated 29 line segments for every pixel.  That
// inferred hundreds of variable multipliers/dividers and exceeded the
// Artix-7 35T resources when used by both OLEDs.  This version keeps the
// live chart behaviour but renders eight sampled vertical bars.  It uses
// fixed slices and comparisons only, so the display remains synthesizable on
// the target board.
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
    output reg          pixel_active,
    output reg  [15:0]  pixel_color
);

    localparam [1:0] MODE_STOCK     = 2'b01;
    localparam [1:0] MODE_PORTFOLIO = 2'b10;

    reg [2:0] x_bin;
    reg [7:0] point_scale;
    reg [5:0] point_top;

    always @(*) begin
        pixel_active = 1'b0;
        pixel_color  = 16'h0000;
        x_bin        = 3'd0;
        point_scale  = 8'd0;
        point_top    = 6'd41;

        if ((chart_mode == MODE_STOCK) ||
            (chart_mode == MODE_PORTFOLIO)) begin
            // The chart occupies x=4..91. Eight fixed bins avoid a
            // run-time divide by the number of samples.
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

            // Use one byte from each source value as a compact, hardware-
            // cheap vertical scale. The selected byte still changes as
            // the market/portfolio data changes.
            if (chart_mode == MODE_STOCK) begin
                case (x_bin)
                    3'd0: point_scale = stock_samples[15:8];
                    3'd1: point_scale = stock_samples[79:72];
                    3'd2: point_scale = stock_samples[143:136];
                    3'd3: point_scale = stock_samples[207:200];
                    3'd4: point_scale = stock_samples[271:264];
                    3'd5: point_scale = stock_samples[335:328];
                    3'd6: point_scale = stock_samples[399:392];
                    default: point_scale = stock_samples[463:456];
                endcase
            end else begin
                case (x_bin)
                    3'd0: point_scale = portfolio_samples[19:12];
                    3'd1: point_scale = portfolio_samples[147:140];
                    3'd2: point_scale = portfolio_samples[275:268];
                    3'd3: point_scale = portfolio_samples[403:396];
                    3'd4: point_scale = portfolio_samples[531:524];
                    3'd5: point_scale = portfolio_samples[659:652];
                    3'd6: point_scale = portfolio_samples[787:780];
                    default: point_scale = portfolio_samples[915:908];
                endcase
            end

            // Map the high nibble into the 18-pixel chart height. Values
            // above the visible range are clamped at the top border.
            if (point_scale[7:4] >= 4'd15)
                point_top = 6'd23;
            else
                point_top = 6'd41 - {2'b00, point_scale[7:4]};

            if ((pixel_y >= 6'd23) && (pixel_y <= 6'd41)) begin
                pixel_active = 1'b1;
                if ((pixel_x == 7'd4) || (pixel_x == 7'd91) ||
                    (pixel_y == 6'd23) || (pixel_y == 6'd41)) begin
                    pixel_color = 16'h07FF;
                end else if (pixel_y >= point_top) begin
                    if (chart_mode == MODE_STOCK)
                        pixel_color = 16'h07E0;
                    else
                        pixel_color = 16'h07FF;
                end else begin
                    pixel_color = 16'h0000;
                end
            end
        end
    end

endmodule
