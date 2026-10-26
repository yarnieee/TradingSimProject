`timescale 1ns / 1ps

// Small resource-friendly chart renderer.
//
// The original renderer calculated 29 line segments for every pixel.  That
// inferred hundreds of variable multipliers/dividers and exceeded the
// Artix-7 35T resources when used by both OLEDs.  This version keeps the
// live chart behaviour but renders eight sampled vertical bars.  The eight
// samples are normalized against their own min/max range so both 16-bit stock
// prices and 32-bit portfolio values use the full visible chart height.
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
        point_top    = 6'd41;

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

        // Select a power-of-two scale.  This avoids a hardware divider while
        // keeping the largest bar within the 18-pixel chart height.
        if      (value_range > 32'h12000000) scale_shift = 5'd24;
        else if (value_range > 32'h09000000) scale_shift = 5'd23;
        else if (value_range > 32'h04800000) scale_shift = 5'd22;
        else if (value_range > 32'h02400000) scale_shift = 5'd21;
        else if (value_range > 32'h01200000) scale_shift = 5'd20;
        else if (value_range > 32'h00900000) scale_shift = 5'd19;
        else if (value_range > 32'h00480000) scale_shift = 5'd18;
        else if (value_range > 32'h00240000) scale_shift = 5'd17;
        else if (value_range > 32'h00120000) scale_shift = 5'd16;
        else if (value_range > 32'h00090000) scale_shift = 5'd15;
        else if (value_range > 32'h00048000) scale_shift = 5'd14;
        else if (value_range > 32'h00024000) scale_shift = 5'd13;
        else if (value_range > 32'h00012000) scale_shift = 5'd12;
        else if (value_range > 32'h00009000) scale_shift = 5'd11;
        else if (value_range > 32'h00004800) scale_shift = 5'd10;
        else if (value_range > 32'h00002400) scale_shift = 5'd9;
        else if (value_range > 32'h00001200) scale_shift = 5'd8;
        else if (value_range > 32'h00000900) scale_shift = 5'd7;
        else if (value_range > 32'h00000480) scale_shift = 5'd6;
        else if (value_range > 32'h00000240) scale_shift = 5'd5;
        else if (value_range > 32'h00000120) scale_shift = 5'd4;
        else if (value_range > 32'h00000090) scale_shift = 5'd3;
        else if (value_range > 32'h00000048) scale_shift = 5'd2;
        else if (value_range > 32'h00000024) scale_shift = 5'd1;

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

            case (x_bin)
                3'd0: selected_value = sample_value[0];
                3'd1: selected_value = sample_value[1];
                3'd2: selected_value = sample_value[2];
                3'd3: selected_value = sample_value[3];
                3'd4: selected_value = sample_value[4];
                3'd5: selected_value = sample_value[5];
                3'd6: selected_value = sample_value[6];
                default: selected_value = sample_value[7];
            endcase

            // A flat history is drawn as a centered line. Otherwise the
            // normalized sample height is clamped to the chart's 18 pixels.
            if (value_range == 0) begin
                point_top = 6'd32;
            end else begin
                point_height = (selected_value - min_value) >> scale_shift;
                if (point_height > 6'd18)
                    point_height = 6'd18;
                point_top = 6'd41 - point_height;
            end

            if ((pixel_y >= 6'd23) && (pixel_y <= 6'd41)) begin
                if ((pixel_x == 7'd4) || (pixel_x == 7'd91) ||
                    (pixel_y == 6'd23) || (pixel_y == 6'd41)) begin
                    pixel_active = 1'b1;
                    pixel_color = 16'h07FF;
                end else if ((value_range == 0 && pixel_y == 6'd32) ||
                             (value_range != 0 && pixel_y >= point_top)) begin
                    pixel_active = 1'b1;
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
