`timescale 1ns / 1ps

// Small resource-friendly chart renderer.
//
// Frame x=2..93, y=28..54 (rows 3-5 of the text_grid layout). Inside it,
// 15 points of the 30-day history (every second day, newest at the right)
// are drawn as a step line in columns of 6 pixels, scaled against their own
// min/max with a power-of-two shift (no divider) to at most 24 pixels tall.
// A stock that is up over the period is green, down is red.
// Stop-loss / take-profit levels waiting in the order book (sl_price,
// tp_price; 0 = none) are dashed lines, red and green, behind the price line;
// a level outside the chart's range sits on the bottom or top edge.
//
// The scale does not depend on the pixel, so a small scanner works it out on
// clk, one point per clock (about 40 clocks, over and over), and keeps each
// column's height in a table. The pixel logic only looks heights up. The
// table follows the history within a microsecond; the OLED takes a pixel
// every 160 ns and a whole frame takes milliseconds.
//
// chart_mode:
//   2'b00 = disabled
//   2'b01 = selected-stock chart
//   2'b10 = portfolio-value chart (newest point = live_value)
module chart_renderer (
    input  wire         clk,
    input  wire [6:0]   pixel_x,
    input  wire [5:0]   pixel_y,
    input  wire [1:0]   chart_mode,
    input  wire [479:0] stock_samples,
    input  wire [959:0] portfolio_samples,
    input  wire [31:0]  live_value,
    input  wire [15:0]  sl_price,
    input  wire [15:0]  tp_price,
    output reg          pixel_active,
    output reg  [15:0]  pixel_color
);
    localparam [1:0] MODE_STOCK     = 2'b01;
    localparam [1:0] MODE_PORTFOLIO = 2'b10;
    localparam [5:0] TOP = 6'd28, BOTTOM = 6'd54;    // frame
    localparam [5:0] BASE = 6'd53;                   // lowest plotted line
    localparam [6:0] LEFT = 7'd2, RIGHT = 7'd93;

    // ------------------------------------------------------------ scanner (clk)
    // pass 0: points 0..14 -> min / max; pass 3: the shift; pass 1: points
    // 0..14 -> heights, then 15 / 16 -> the stop-loss / take-profit rows;
    // pass 2: everything is handed to the pixel logic at once.
    reg  [1:0]  sc_pass;
    reg  [4:0]  sc_i;                 // point 0..14; 15 SL, 16 TP
    reg  [31:0] run_min, run_max, lo, rng, first_v;
    reg  [4:0]  sh;
    reg  [4:0]  h_new [0:14];
    reg  [5:0]  y_sl_new, y_tp_new;

    // point sc_i (samples 1, 3, ..., 29; 29 is the newest), or a level
    reg  [31:0] sv;
    always @(*) begin
        if (sc_i == 5'd15)
            sv = {16'd0, sl_price};
        else if (sc_i == 5'd16)
            sv = {16'd0, tp_price};
        else if (chart_mode == MODE_STOCK)
            sv = {16'd0, stock_samples[32*sc_i + 16 +: 16]};
        else if ((chart_mode == MODE_PORTFOLIO) && (sc_i == 5'd14))
            sv = live_value;
        else
            sv = portfolio_samples[64*sc_i + 32 +: 32];
    end

    // smallest shift that fits the range in 24 pixels
    reg  [4:0]  sh_fit;
    integer     s;
    always @(*) begin
        sh_fit = 5'd24;
        for (s = 24; s >= 0; s = s - 1)
            if ((rng >> s) <= 32'd24) sh_fit = s;
    end

    // a height is kept to 6 bits and then capped at 24 (as the per-pixel
    // version did; only matters for a range too big for any shift)
    wire [31:0] above   = sv - lo;
    wire [31:0] h_full  = above >> sh;
    wire [5:0]  h_6     = h_full[5:0];
    wire [4:0]  h_of_sv = (rng == 0) ? 5'd12 : (h_6 > 6'd24) ? 5'd24 : h_6[4:0];

    // y of a price level on this chart (clamped to the plot)
    wire [5:0]  level_of_sv = (sv <= lo)           ? BASE :
                              (above > rng)        ? BASE - 6'd24 :
                              (rng == 0)           ? BASE - 6'd12 :
                              (h_full > 32'd24)    ? BASE - 6'd24 : BASE - h_full[5:0];

    // what the pixel logic uses
    reg  [4:0]  h_tab [0:14];
    reg  [5:0]  y_sl, y_tp;
    reg         up;

    integer k;
    initial begin
        sc_pass = 2'd0;
        sc_i    = 5'd0;
        run_min = 32'd0; run_max = 32'd0; lo = 32'd0; rng = 32'd0; first_v = 32'd0;
        sh      = 5'd0;
        y_sl    = BASE;
        y_tp    = BASE;
        y_sl_new = BASE;
        y_tp_new = BASE;
        up      = 1'b1;
        for (k = 0; k < 15; k = k + 1) begin
            h_new[k] = 5'd12;
            h_tab[k] = 5'd12;
        end
    end

    always @(posedge clk) begin
        case (sc_pass)
            2'd0: begin                                   // min / max
                if (sc_i == 5'd0) begin
                    run_min <= sv;
                    run_max <= sv;
                    first_v <= sv;
                end else begin
                    if (sv < run_min) run_min <= sv;
                    if (sv > run_max) run_max <= sv;
                end
                if (sc_i == 5'd14) begin
                    lo      <= (sv < run_min) ? sv : run_min;
                    rng     <= ((sv > run_max) ? sv : run_max) - ((sv < run_min) ? sv : run_min);
                    up      <= (sv >= first_v);           // newest at or above oldest
                    sc_i    <= 5'd0;
                    sc_pass <= 2'd3;
                end else
                    sc_i <= sc_i + 5'd1;
            end
            2'd3: begin                                   // the shift for this range
                sh      <= sh_fit;
                sc_pass <= 2'd1;
            end
            2'd1: begin                                   // heights, SL / TP rows
                if (sc_i == 5'd15)
                    y_sl_new <= level_of_sv;
                else if (sc_i == 5'd16)
                    y_tp_new <= level_of_sv;
                else
                    h_new[sc_i] <= h_of_sv;
                if (sc_i == 5'd16) begin
                    sc_i    <= 5'd0;
                    sc_pass <= 2'd2;
                end else
                    sc_i <= sc_i + 5'd1;
            end
            default: begin                                // hand over
                y_sl <= y_sl_new;
                y_tp <= y_tp_new;
                for (k = 0; k < 15; k = k + 1)
                    h_tab[k] <= h_new[k];
                sc_pass <= 2'd0;
            end
        endcase
    end

    // ------------------------------------------------------------ pixels
    reg  [3:0]  bin;
    reg  [6:0]  bin_x0;
    reg  [5:0]  y_cur, y_prev;

    always @(*) begin
        pixel_active = 1'b0;
        pixel_color  = 16'h0000;

        // which column of 6 pixels (x 3..92)
        bin = (pixel_x <= 7'd3) ? 4'd0 : (pixel_x - 7'd3) / 6;
        if (bin > 4'd14) bin = 4'd14;
        bin_x0 = 7'd3 + bin * 6;
        y_cur  = BASE - h_tab[bin];
        y_prev = BASE - h_tab[(bin == 4'd0) ? 4'd0 : bin - 4'd1];

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
                    pixel_color = up ? 16'h07E0 : 16'hF8A2;
                else
                    pixel_color = 16'h07FF;
            end else if ((chart_mode == MODE_STOCK) && !pixel_x[1] && (sl_price != 16'd0) && (pixel_y == y_sl)) begin
                pixel_active = 1'b1;
                pixel_color  = 16'hF800;                 // stop-loss: red dashes
            end else if ((chart_mode == MODE_STOCK) && !pixel_x[1] && (tp_price != 16'd0) && (pixel_y == y_tp)) begin
                pixel_active = 1'b1;
                pixel_color  = 16'h07E0;                 // take-profit: green dashes
            end
        end
    end
endmodule
