`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// vga_screen: the whole game on a VGA monitor, 1280 x 720 at 60 Hz (widescreen,
// fills a 24" 16:9 monitor). Pixels come at 74.25 MHz (pclk, from vga_clock);
// Basys3 VGA is 4 bits each of red, green and blue.
//
// Text: 71 x 30 cells of 18 x 24 pixels, Matthew's 5x7 font drawn 3x (15 x 21).
//   A writer on the 100 MHz clock walks every cell, asks vga_cells what it shows
//   and stores {fg, bg, char} in a character RAM (block RAM, written at 100 MHz,
//   read at 74.25 MHz): one cell every 4 clocks, the whole screen every 85 us.
//   The vga_cells logic is given those 4 clocks (multicycle constraint in
//   Integration.xdc).
// Graphics, on top of the text (pixel clock):
//   row 1        progress bar: how much of the game has gone (progress_w of 1242 px)
//   rows 10-19   chart of the selected stock, x 18..497 (30 days, 16 px each):
//                scaled to its own low..high with a sequential divider (worked out
//                once per frame, after the picture), stop-loss / take-profit levels
//                as dashed lines, dotted lines at the high and low
// Pixel path (pixel clock, pipelined): counters -> RAM address -> RAM data ->
// font + graphics -> colour; the syncs are delayed to match.
module vga_screen (
    input  wire        clk,             // 100 MHz: character writer
    input  wire        rst,
    input  wire        pclk,            // 74.25 MHz: picture
    input  wire        pix_rst,
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
    input  wire [10:0]  progress_w,      // 0..1242: game progress bar width
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
                4'd7:    rgb = 12'h126;   // navy (title bar, NOW bar)
                4'd8:    rgb = 12'h777;   // dark grey (small print)
                4'd9:    rgb = 12'h515;   // plum
                4'd10:   rgb = 12'hF90;   // orange
                4'd11:   rgb = 12'h235;   // slate (panel header bars)
                4'd12:   rgb = 12'h223;   // dark slate (selected row, order line)
                default: rgb = 12'h000;
            endcase
        end
    endfunction

    // 0..20 / 3 (which font pixel a screen pixel belongs to, font drawn 3x)
    function [2:0] div3;
        input [4:0] n;
        begin
            div3 = (n >= 5'd18) ? 3'd6 : (n >= 5'd15) ? 3'd5 : (n >= 5'd12) ? 3'd4 :
                   (n >= 5'd9)  ? 3'd3 : (n >= 5'd6)  ? 3'd2 : (n >= 5'd3)  ? 3'd1 : 3'd0;
        end
    endfunction

    // ------------------------------------------------------------ character RAM
    reg  [15:0] cram [0:4095];             // {fg, bg, char}, address {row, col}
    reg  [11:0] wr_addr;
    reg  [15:0] wr_cell;
    reg         wr_we;
    reg  [11:0] rd_addr;
    reg  [15:0] rd_data;
    integer ci0;
    initial for (ci0 = 0; ci0 < 4096; ci0 = ci0 + 1) cram[ci0] = 16'd0;
    always @(posedge clk)  if (wr_we) cram[wr_addr] <= wr_cell;
    always @(posedge pclk) rd_data <= cram[rd_addr];

    // ------------------------------------------------------------ writer: one cell every 4 clocks
    reg  [4:0] wr_row;
    reg  [6:0] wr_col;
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
            wr_col   <= 7'd0;
            wr_phase <= 2'd0;
            wr_we    <= 1'b0;
            wr_addr  <= 12'd0;
            wr_cell  <= 16'd0;
        end else begin
            wr_phase <= wr_phase + 2'd1;
            wr_we    <= 1'b0;
            if (wr_phase == 2'd3) begin            // this cell's content has had 4 clocks to settle
                wr_cell <= {c_fg, c_bg, c_ch};
                wr_addr <= {wr_row, wr_col};
                wr_we   <= 1'b1;
                if (wr_col == 7'd70) begin
                    wr_col <= 7'd0;
                    wr_row <= (wr_row == 5'd29) ? 5'd0 : wr_row + 5'd1;
                end else
                    wr_col <= wr_col + 7'd1;
            end
        end
    end

    // ------------------------------------------------------------ 1280 x 720 @ 60 Hz timing (pixel clock)
    // h: 1280 visible, 110 front porch, 40 sync, 220 back porch (1650)
    // v: 720 visible, 5 front porch, 5 sync, 20 back porch (750); syncs are high pulses
    reg  [10:0] h;
    reg  [9:0]  v;
    reg  [6:0]  cx;                            // cell column of h
    reg  [4:0]  px;                            // pixel inside the cell, 0..17
    reg  [4:0]  cy;                            // cell row of v
    reg  [4:0]  ly;                            // line inside the cell, 0..23
    always @(posedge pclk) begin
        if (pix_rst) begin
            h <= 11'd0; v <= 10'd0; cx <= 7'd0; px <= 5'd0; cy <= 5'd0; ly <= 5'd0;
        end else if (h == 11'd1649) begin
            h <= 11'd0; cx <= 7'd0; px <= 5'd0;
            if (v == 10'd749) begin
                v <= 10'd0; cy <= 5'd0; ly <= 5'd0;
            end else begin
                v <= v + 10'd1;
                if (ly == 5'd23) begin ly <= 5'd0; cy <= cy + 5'd1; end
                else ly <= ly + 5'd1;
            end
        end else begin
            h <= h + 11'd1;
            if (px == 5'd17) begin px <= 5'd0; cx <= cx + 7'd1; end
            else px <= px + 5'd1;
        end
    end

    // ------------------------------------------------------------ chart: heights, once per frame
    // h_tab[i] = (sample_i - low) * 216 / (high - low), i = 0..29; 30 = stop-loss, 31 = take-profit
    reg  [7:0]  h_tab [0:31];
    reg  [15:0] lo, hi;
    reg  [4:0]  ci;                            // sample being worked on
    reg  [2:0]  cstate;
    reg  [23:0] num;                           // (value - low) * 216
    reg  [15:0] den;
    reg  [23:0] rem;
    reg  [7:0]  quo;
    reg  [4:0]  dstep;
    localparam C_IDLE = 3'd0, C_SCAN = 3'd1, C_LOAD = 3'd2, C_DIV = 3'd3, C_STORE = 3'd4;

    wire [4:0]  si   = (ci > 5'd29) ? 5'd0 : ci;
    wire [15:0] cval = (ci == 5'd30) ? sel_sl : (ci == 5'd31) ? sel_tp : stock_samples[16*si +: 16];
    wire [15:0] cclp = (cval < lo) ? lo : (cval > hi) ? hi : cval;   // levels outside the range sit on the edge
    wire [15:0] coff = cclp - lo;
    wire [23:0] trial = {rem[22:0], num[23 - dstep]};

    always @(posedge pclk) begin
        if (pix_rst) begin
            cstate <= C_IDLE; ci <= 5'd0; lo <= 16'd0; hi <= 16'd0;
        end else case (cstate)
            C_IDLE: if (v == 10'd721 && h == 11'd0) begin   // just after the visible frame
                ci <= 5'd0; lo <= 16'hFFFF; hi <= 16'd0; cstate <= C_SCAN;
            end
            C_SCAN: begin                                     // low and high of the 30 days
                if (cval < lo) lo <= cval;
                if (cval > hi) hi <= cval;
                if (ci == 5'd29) begin ci <= 5'd0; cstate <= C_LOAD; end
                else ci <= ci + 5'd1;
            end
            C_LOAD: begin                                     // x 256 - x 32 - x 8 = x 216
                num   <= {coff, 8'd0} - {3'd0, coff, 5'd0} - {5'd0, coff, 3'd0};
                den   <= hi - lo;
                rem   <= 24'd0;
                quo   <= 8'd0;
                dstep <= 5'd0;
                cstate <= C_DIV;
            end
            C_DIV: begin                                      // restoring division, one bit a clock
                if (den == 16'd0) begin
                    quo <= 8'd108; cstate <= C_STORE;         // flat history: middle of the chart
                end else begin
                    if (trial >= {8'd0, den}) begin rem <= trial - {8'd0, den}; quo <= {quo[6:0], 1'b1}; end
                    else begin                     rem <= trial;                 quo <= {quo[6:0], 1'b0}; end
                    if (dstep == 5'd23) cstate <= C_STORE;
                    dstep <= dstep + 5'd1;
                end
            end
            default: begin                                    // C_STORE
                h_tab[ci] <= (quo > 8'd216) ? 8'd216 : quo;
                if (ci == 5'd31) cstate <= C_IDLE;
                else begin ci <= ci + 5'd1; cstate <= C_LOAD; end
            end
        endcase
    end

    // ------------------------------------------------------------ pixel pipeline
    // stage 1: RAM address, the pixel's position, its chart day
    reg  [10:0] s1_h;
    reg  [9:0]  s1_v;
    reg  [4:0]  s1_px, s1_ly, s1_bn;
    reg  [3:0]  s1_bp;
    reg         s1_vis, s1_hs, s1_vs;
    wire [10:0] bx = h - 11'd18;               // chart x: day = bx / 16
    always @(posedge pclk) begin
        rd_addr <= {cy, cx};
        s1_h    <= h;
        s1_v    <= v;
        s1_px   <= px;
        s1_ly   <= ly;
        s1_bn   <= (h < 11'd18) ? 5'd0 : (bx[10:4] > 7'd29) ? 5'd29 : bx[8:4];
        s1_bp   <= bx[3:0];
        s1_vis  <= (h < 11'd1280) && (v < 10'd720);
        s1_hs   <= (h >= 11'd1390) && (h < 11'd1430);
        s1_vs   <= (v >= 10'd725) && (v < 10'd730);
    end

    // stage 1b: the RAM data and this day's / the day before's heights
    reg  [10:0] p_h;
    reg  [9:0]  p_v;
    reg  [4:0]  p_px, p_ly, p_bn;
    reg  [3:0]  p_bp;
    reg  [7:0]  p_hc, p_hp;
    reg         p_vis, p_hs, p_vs;
    always @(posedge pclk) begin
        p_h <= s1_h; p_v <= s1_v; p_px <= s1_px; p_ly <= s1_ly; p_bn <= s1_bn; p_bp <= s1_bp;
        p_hc <= h_tab[s1_bn];
        p_hp <= h_tab[(s1_bn == 5'd0) ? 5'd0 : s1_bn - 5'd1];
        p_vis <= s1_vis; p_hs <= s1_hs; p_vs <= s1_vs;
    end

    // stage 2: the letter's pixel, and the graphics (rd_data and p_* are the same pixel)
    wire [4:0] gxx = p_px - 5'd1;                           // text starts 1 px into the cell
    wire [4:0] gyy = p_ly - 5'd1;
    wire       in_glyph = (p_px >= 5'd1) && (p_px <= 5'd15) && (p_ly >= 5'd1) && (p_ly <= 5'd21);
    wire       glyph;
    font_renderer font (.char_code(rd_data[7:0]),
                        .glyph_x(in_glyph ? div3(gxx) : 3'd7), .glyph_y(in_glyph ? div3(gyy) : 3'd7),
                        .pixel_on(glyph));

    // chart area: x 18..497, y 240..479 (rows 10-19); lines at y = 468 - height (252 = high, 468 = low)
    wire       in_chart = (p_h >= 11'd18) && (p_h <= 11'd497) && (p_v >= 10'd240) && (p_v <= 10'd479);
    wire [9:0] y_cur = 10'd468 - {2'd0, p_hc};
    wire [9:0] y_prv = 10'd468 - {2'd0, p_hp};
    wire [9:0] y_sl  = 10'd468 - {2'd0, h_tab[30]};
    wire [9:0] y_tp  = 10'd468 - {2'd0, h_tab[31]};
    wire       on_line = ((p_v + 10'd1 >= y_cur) && (p_v <= y_cur + 10'd1)) ||               // 3 px thick
                         ((p_bp <= 4'd1) && (p_bn != 5'd0) &&                                // step from the day before
                          (((p_v >= y_prv) && (p_v <= y_cur)) || ((p_v <= y_prv) && (p_v >= y_cur))));
    wire       rising  = (stock_samples[16*29 +: 16] >= stock_samples[15:0]);
    wire       on_sl   = (sel_sl != 16'd0) && ((p_v == y_sl) || (p_v == y_sl + 10'd1)) && !p_h[3];   // dashed
    wire       on_tp   = (sel_tp != 16'd0) && ((p_v == y_tp) || (p_v == y_tp + 10'd1)) && !p_h[3];
    wire       on_grid = ((p_v == 10'd252) || (p_v == 10'd468)) && p_h[2];                      // dotted high / low

    // progress bar: x 18..1259, y 32..39
    wire       in_bar  = (p_h >= 11'd18) && (p_h <= 11'd1259) && (p_v >= 10'd32) && (p_v <= 10'd39);
    wire       bar_on  = (p_h < 11'd18 + progress_w);

    reg [11:0] s2_text;
    reg [11:0] s2_gfx;
    reg        s2_gfx_on, s2_vis, s2_hs, s2_vs;
    always @(posedge pclk) begin
        s2_text <= glyph ? rgb(rd_data[15:12]) : rgb(rd_data[11:8]);
        s2_gfx_on <= 1'b1;
        if (in_bar)                                 s2_gfx <= bar_on ? 12'hFC0 : 12'h222;
        else if (in_chart && on_line)               s2_gfx <= rising ? 12'h0F0 : 12'hF44;
        else if (in_chart && on_sl)                 s2_gfx <= 12'hF00;
        else if (in_chart && on_tp)                 s2_gfx <= 12'h0F0;
        else if (in_chart && on_grid)               s2_gfx <= 12'h444;
        else begin s2_gfx <= 12'h000; s2_gfx_on <= 1'b0; end
        s2_vis <= p_vis;
        s2_hs  <= p_hs;
        s2_vs  <= p_vs;
    end

    // stage 3: the colour out, blank outside the visible area
    always @(posedge pclk) begin
        {vga_r, vga_g, vga_b} <= !s2_vis ? 12'h000 : s2_gfx_on ? s2_gfx : s2_text;
        hsync <= s2_hs;
        vsync <= s2_vs;
    end
endmodule

`default_nettype wire
