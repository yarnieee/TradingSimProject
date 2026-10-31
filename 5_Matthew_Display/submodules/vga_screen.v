`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// vga_screen: the whole game on a VGA monitor, 640 x 480 at 60 Hz (25 MHz
// pixels from the 100 MHz clock: one pixel every 4 clocks). Basys3 VGA is
// 4 bits each of red, green and blue.
//
// Text: 53 x 30 cells of 12 x 16 pixels, Matthew's 5x7 font drawn 2x (10 x 14).
//   A writer walks every cell in the background, asks vga_cells what it shows
//   and stores {fg, bg, char} in a character RAM (one block RAM): one cell
//   every 4 clocks, the whole screen every 8,192 clocks (82 us). The vga_cells
//   logic is given those 4 clocks (multicycle constraint in Integration.xdc).
// Graphics, on top of the text:
//   row 1        progress bar: how much of the game has gone (progress_w of 616 px)
//   rows 10-17   chart of the selected stock, left panel: 30 days, scaled to its
//                own low..high with a sequential divider (worked out once per
//                frame), plus its stop-loss / take-profit levels as dashed lines
// Pixel path (100 MHz, pipelined): counters -> RAM address -> RAM data -> font +
// graphics -> colour, 4 clocks (one pixel) behind the counters; the syncs are
// delayed to match, so each output changes exactly once per pixel.
module vga_screen (
    input  wire        clk,
    input  wire        rst,
    // screen content (see vga_cells)
    input  wire [3:0]  screen_state,
    input  wire [3:0]  menu_selection,
    input  wire [2:0]  selected_stock,
    input  wire        trade_side,
    input  wire        trade_result_success,
    input  wire        trade_result_placed,
    input  wire [2:0]  trade_result_code,
    input  wire        order_valid,
    input  wire [2:0]  validation_code,
    input  wire [1:0]  order_type,
    input  wire [1:0]  order_brk,
    input  wire [1:0]  order_dist,
    input  wire        oled_bot_view,
    input  wire [3:0]  stock_up,
    input  wire [`DN_N*32-1:0] bcd,
    input  wire [`DN_N-1:0]    neg,
    input  wire [7:0]  book_valid,
    input  wire [7:0]  book_side,
    input  wire [15:0] book_stock,
    input  wire [15:0] book_type,
    input  wire [7:0]  book_leg,
    input  wire [4:0]  log_valid,
    input  wire [4:0]  log_side,
    input  wire [9:0]  log_stock,
    // graphics
    input  wire [479:0] stock_samples,   // selected stock, 30 days, oldest first
    input  wire [15:0]  sel_sl,          // its stop-loss / take-profit levels (0 = none)
    input  wire [15:0]  sel_tp,
    input  wire [9:0]   progress_w,      // 0..616: game progress bar width
    // VGA port
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,
    output reg         hsync,
    output reg         vsync
);
    // ------------------------------------------------------------ palette (vga_cells indices)
    function [11:0] rgb;
        input [3:0] k;
        begin
            case (k)
                4'd0:    rgb = 12'h000;   // black
                4'd1:    rgb = 12'hFFF;   // white
                4'd2:    rgb = 12'h0FF;   // cyan
                4'd3:    rgb = 12'hFF0;   // yellow
                4'd4:    rgb = 12'h0F0;   // green
                4'd5:    rgb = 12'hF44;   // red (a little light)
                4'd6:    rgb = 12'h999;   // grey
                4'd7:    rgb = 12'h126;   // navy (title bar)
                4'd8:    rgb = 12'h333;   // dark grey (highlight, order line)
                4'd9:    rgb = 12'h515;   // plum
                4'd10:   rgb = 12'hF90;   // orange
                default: rgb = 12'h000;
            endcase
        end
    endfunction

    // ------------------------------------------------------------ character RAM
    reg  [15:0] cram [0:2047];             // {fg, bg, char}, address {row, col}
    reg  [10:0] wr_addr;
    reg  [15:0] wr_cell;
    reg         wr_we;
    reg  [10:0] rd_addr;
    reg  [15:0] rd_data;
    always @(posedge clk) begin
        if (wr_we) cram[wr_addr] <= wr_cell;
        rd_data <= cram[rd_addr];
    end

    // ------------------------------------------------------------ writer: one cell every 4 clocks
    reg  [4:0] wr_row;
    reg  [5:0] wr_col;
    reg  [1:0] wr_phase;
    wire [7:0] c_ch;
    wire [3:0] c_fg, c_bg;

    vga_cells cells (
        .row(wr_row), .col(wr_col),
        .screen_state(screen_state), .menu_selection(menu_selection), .selected_stock(selected_stock),
        .trade_side(trade_side), .trade_result_success(trade_result_success),
        .trade_result_placed(trade_result_placed), .trade_result_code(trade_result_code),
        .order_valid(order_valid), .validation_code(validation_code),
        .order_type(order_type), .order_brk(order_brk), .order_dist(order_dist),
        .oled_bot_view(oled_bot_view), .up(stock_up), .bcd(bcd), .neg(neg),
        .book_valid(book_valid), .book_side(book_side), .book_stock(book_stock),
        .book_type(book_type), .book_leg(book_leg),
        .log_valid(log_valid), .log_side(log_side), .log_stock(log_stock),
        .ch(c_ch), .fg(c_fg), .bg(c_bg)
    );

    always @(posedge clk) begin
        if (rst) begin
            wr_row   <= 5'd0;
            wr_col   <= 6'd0;
            wr_phase <= 2'd0;
            wr_we    <= 1'b0;
            wr_addr  <= 11'd0;
            wr_cell  <= 16'd0;
        end else begin
            wr_phase <= wr_phase + 2'd1;
            wr_we    <= 1'b0;
            if (wr_phase == 2'd3) begin            // this cell's content has had 4 clocks to settle
                wr_cell <= {c_fg, c_bg, c_ch};
                wr_addr <= {wr_row, wr_col};
                wr_we   <= 1'b1;
                if (wr_col == 6'd52) begin
                    wr_col <= 6'd0;
                    wr_row <= (wr_row == 5'd29) ? 5'd0 : wr_row + 5'd1;
                end else
                    wr_col <= wr_col + 6'd1;
            end
        end
    end

    // ------------------------------------------------------------ 640 x 480 @ 60 Hz timing
    // h: 640 visible, 16 front porch, 96 sync, 48 back porch (800); v: 480, 10, 2, 33 (525).
    reg  [1:0] div4;
    wire       pe = (div4 == 2'd3);            // one pixel every 4 clocks (25 MHz)
    reg  [9:0] h, v;
    reg  [5:0] cx;                             // cell column of h
    reg  [3:0] px;                             // pixel inside the cell, 0..11
    always @(posedge clk) begin
        if (rst) begin
            div4 <= 2'd0; h <= 10'd0; v <= 10'd0; cx <= 6'd0; px <= 4'd0;
        end else begin
            div4 <= div4 + 2'd1;
            if (pe) begin
                if (h == 10'd799) begin
                    h <= 10'd0; cx <= 6'd0; px <= 4'd0;
                    v <= (v == 10'd524) ? 10'd0 : v + 10'd1;
                end else begin
                    h <= h + 10'd1;
                    if (px == 4'd11) begin px <= 4'd0; cx <= cx + 6'd1; end
                    else px <= px + 4'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------ chart: heights, once per frame
    // h_tab[i] = (sample_i - low) * 120 / (high - low), i = 0..29; 30 = stop-loss, 31 = take-profit
    reg  [6:0]  h_tab [0:31];
    reg  [15:0] lo, hi;
    reg  [4:0]  ci;                            // sample being worked on
    reg  [2:0]  cstate;
    reg  [22:0] num;                           // (value - low) * 120
    reg  [15:0] den;
    reg  [22:0] rem;
    reg  [6:0]  quo;
    reg  [4:0]  dstep;
    localparam C_IDLE = 3'd0, C_SCAN = 3'd1, C_LOAD = 3'd2, C_DIV = 3'd3, C_STORE = 3'd4;

    wire [4:0]  si   = (ci > 5'd29) ? 5'd0 : ci;
    wire [15:0] cval = (ci == 5'd30) ? sel_sl : (ci == 5'd31) ? sel_tp : stock_samples[16*si +: 16];
    wire [15:0] cclp = (cval < lo) ? lo : (cval > hi) ? hi : cval;   // levels outside the range sit on the edge
    wire [15:0] coff = cclp - lo;
    wire [22:0] trial = {rem[21:0], num[22 - dstep]};

    always @(posedge clk) begin
        if (rst) begin
            cstate <= C_IDLE; ci <= 5'd0; lo <= 16'd0; hi <= 16'd0;
        end else case (cstate)
            C_IDLE: if (v == 10'd481 && h == 10'd0 && pe) begin   // just after the visible frame
                ci <= 5'd0; lo <= 16'hFFFF; hi <= 16'd0; cstate <= C_SCAN;
            end
            C_SCAN: begin                                     // low and high of the 30 days
                if (cval < lo) lo <= cval;
                if (cval > hi) hi <= cval;
                if (ci == 5'd29) begin ci <= 5'd0; cstate <= C_LOAD; end
                else ci <= ci + 5'd1;
            end
            C_LOAD: begin
                num   <= {coff, 7'd0} - {4'd0, coff, 3'd0};     // x 128 - x 8 = x 120
                den   <= hi - lo;
                rem   <= 23'd0;
                quo   <= 7'd0;
                dstep <= 5'd0;
                cstate <= C_DIV;
            end
            C_DIV: begin                                      // restoring division, one bit a clock
                if (den == 16'd0) begin
                    quo <= 7'd60; cstate <= C_STORE;          // flat history: middle of the chart
                end else begin
                    if (trial >= {7'd0, den}) begin rem <= trial - {7'd0, den}; quo <= {quo[5:0], 1'b1}; end
                    else begin                     rem <= trial;                 quo <= {quo[5:0], 1'b0}; end
                    if (dstep == 5'd22) cstate <= C_STORE;
                    dstep <= dstep + 5'd1;
                end
            end
            default: begin                                    // C_STORE
                h_tab[ci] <= (quo > 7'd120) ? 7'd120 : quo;
                if (ci == 5'd31) cstate <= C_IDLE;
                else begin ci <= ci + 5'd1; cstate <= C_LOAD; end
            end
        endcase
    end

    // ------------------------------------------------------------ pixel pipeline
    // stage 1: RAM address and the pixel's position
    reg  [9:0] s1_h, s1_v;
    reg  [3:0] s1_px;
    reg        s1_vis, s1_hs, s1_vs;
    always @(posedge clk) begin
        rd_addr <= {v[8:4], cx};
        s1_h    <= h;
        s1_v    <= v;
        s1_px   <= px;
        s1_vis  <= (h < 10'd640) && (v < 10'd480);
        s1_hs   <= !((h >= 10'd656) && (h < 10'd752));     // sync pulses are low
        s1_vs   <= !((v >= 10'd490) && (v < 10'd492));
    end

    // stage 1b: wait for the RAM (its data appears one clock after the address)
    reg  [9:0] p_h, p_v;
    reg  [3:0] p_px;
    reg        p_vis, p_hs, p_vs;
    always @(posedge clk) begin
        p_h <= s1_h; p_v <= s1_v; p_px <= s1_px;
        p_vis <= s1_vis; p_hs <= s1_hs; p_vs <= s1_vs;
    end

    // stage 2: the letter's pixel, and the graphics (rd_data and p_* are the same pixel)
    wire [3:0] gyy = p_v[3:0] - 4'd1;                      // text starts 1 px into the cell
    wire [3:0] gxx = p_px - 4'd1;
    wire       in_glyph = (p_px >= 4'd1) && (p_px <= 4'd10) && (p_v[3:0] >= 4'd1) && (p_v[3:0] <= 4'd14);
    wire       glyph;
    font_renderer font (.char_code(rd_data[7:0]),
                        .glyph_x(in_glyph ? gxx[3:1] : 3'd7), .glyph_y(in_glyph ? gyy[3:1] : 3'd7),
                        .pixel_on(glyph));

    // chart area: x 12..251 (30 columns of 8), y 160..287; lines at y = 285 - height
    wire       in_chart = (p_h >= 10'd10) && (p_h <= 10'd253) && (p_v >= 10'd160) && (p_v <= 10'd287);
    wire       chart_edge = (p_h == 10'd10) || (p_h == 10'd253) || (p_v == 10'd160) || (p_v == 10'd287);
    wire [9:0] bx    = p_h - 10'd12;
    wire [4:0] bin   = (p_h < 10'd12) ? 5'd0 : (bx[9:3] > 7'd29) ? 5'd29 : bx[7:3];
    wire [9:0] y_cur = 10'd285 - h_tab[bin];
    wire [9:0] y_prv = 10'd285 - h_tab[(bin == 5'd0) ? 5'd0 : bin - 5'd1];
    wire [9:0] y_sl  = 10'd285 - h_tab[30];
    wire [9:0] y_tp  = 10'd285 - h_tab[31];
    wire       on_line = ((p_v == y_cur) || (p_v + 10'd1 == y_cur)) ||                 // 2 px thick
                         ((bx[2:0] == 3'd0) && (bin != 5'd0) && (p_h >= 10'd12) &&      // step from the previous day
                          (((p_v >= y_prv) && (p_v <= y_cur)) || ((p_v <= y_prv) && (p_v >= y_cur))));
    wire       rising  = (stock_samples[16*29 +: 16] >= stock_samples[15:0]);
    wire       on_sl   = (sel_sl != 16'd0) && (p_v == y_sl) && !p_h[2];                 // dashed
    wire       on_tp   = (sel_tp != 16'd0) && (p_v == y_tp) && !p_h[2];

    // progress bar: x 12..627, y 20..27
    wire       in_bar  = (p_h >= 10'd12) && (p_h <= 10'd627) && (p_v >= 10'd20) && (p_v <= 10'd27);
    wire       bar_on  = (p_h < 10'd12 + progress_w);

    reg [11:0] s2_text;
    reg [11:0] s2_gfx;
    reg        s2_gfx_on, s2_vis, s2_hs, s2_vs;
    always @(posedge clk) begin
        s2_text <= glyph ? rgb(rd_data[15:12]) : rgb(rd_data[11:8]);
        s2_gfx_on <= 1'b1;
        if (in_bar)                                 s2_gfx <= bar_on ? 12'hFC0 : 12'h222;
        else if (in_chart && chart_edge)            s2_gfx <= 12'h444;
        else if (in_chart && on_line)               s2_gfx <= rising ? 12'h0F0 : 12'hF44;
        else if (in_chart && on_sl)                 s2_gfx <= 12'hF00;
        else if (in_chart && on_tp)                 s2_gfx <= 12'h0F0;
        else begin s2_gfx <= 12'h000; s2_gfx_on <= 1'b0; end
        s2_vis <= p_vis;
        s2_hs  <= p_hs;
        s2_vs  <= p_vs;
    end

    // stage 3: the colour out, blank outside the visible area
    always @(posedge clk) begin
        {vga_r, vga_g, vga_b} <= !s2_vis ? 12'h000 : s2_gfx_on ? s2_gfx : s2_text;
        hsync <= s2_hs;
        vsync <= s2_vs;
    end
endmodule

`default_nettype wire
