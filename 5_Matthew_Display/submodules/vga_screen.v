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
//   row 1        progress bar: how much of the game has gone (progress_w of 1242 px),
//                green, then yellow from 60 days left and red from 10 (bar_level)
//   rows 10-19   chart of the selected stock, x 18..497 (30 days, 16 px each):
//                scaled to its own low..high with a sequential divider (worked out
//                once per frame, after the picture), stop-loss / take-profit levels
//                as dashed lines, dotted lines at the high and low
// Pixel path (pixel clock, pipelined): counters -> RAM address -> RAM data ->
// font + graphics -> colour; the syncs are delayed to match.
// Title screen: one 320 x 180 picture (Tricia's title_art_vga.mem: Bull vs Bear
// and the five bots, 16 colours, its own palette), each pixel 4 x 4 over the
// whole screen, from block RAM read on the pixel clock; text, bar and chart are
// hidden under it. PRESS BTNC TO START (picture rows 146 down) blinks. The OLEDs
// keep their own title pictures (title_art_renderer).
// GAME OVER: the big GAME OVER flashes for about 3 s (36 steps of 2^GO_STEP
// clocks), then the final results show; the chart is hidden.
module vga_screen #(
    parameter GO_STEP = 23,             // 2^23 clocks = 84 ms
    parameter TITLE_BLINK = 5,          // PRESS START: 2^5 frames on, 2^5 off (about 1 s a blink)
    parameter [7:0] TITLE_BTN_ROW = 8'd146  // the picture's PRESS BTNC TO START: rows 146 down
) (
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
    input  wire [2:0]  bot_sel,            // the bot the OLEDs show
    input  wire        orders_view,        // sw14: the buttons are on the left OLED's ORDERS list
    input  wire [17:0] order,              // leaderboard: who is 1st..6th
    input  wire [3:0]  stock_up,
    output wire [6:0]  num_f,              // display_numbers field the writer needs now
    input  wire [32:0] num_rd,             // that field, from display_numbers' RAM
    input  wire [`DN_N-1:0] zero,
    input  wire [7:0]  book_valid,
    input  wire [7:0]  book_side,
    input  wire [15:0] book_stock,
    input  wire [15:0] book_type,
    input  wire [7:0]  book_leg,
    input  wire [7:0]  feed_valid,      // the bots' last 8 trades (news feed, notifications)
    input  wire [23:0] feed_bot,
    input  wire [7:0]  feed_side,
    input  wire [15:0] feed_stock,
    input  wire [1:0]  quantity_cursor,  // the digit being changed (quantity screen)
    input  wire [2:0]  orders_sel,       // sw14: the order the cancel cursor is on
    // graphics
    input  wire [479:0] stock_samples,   // selected stock, 30 days, oldest first
    input  wire [15:0]  sel_sl,          // its stop-loss / take-profit levels (0 = none)
    input  wire [15:0]  sel_tp,
    input  wire [10:0]  progress_w,      // 0..1242: game progress bar width
    input  wire [1:0]   bar_level,       // its colour: 0 green, 1 yellow, 3 red
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
                4'd12:   rgb = 12'h223;   // dark slate (selected row, older notification)
                4'd13:   rgb = 12'h63A;   // purple (bot view: bars)
                4'd14:   rgb = 12'h314;   // dark purple (bot view: rows)
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

    // ------------------------------------------------------------ game over: flash, then results
    reg  [GO_STEP-1:0] go_div;
    reg  [5:0]         go_t;
    always @(posedge clk) begin
        if (rst || screen_state != `UI_GAME_END) begin
            go_div <= {GO_STEP{1'b0}};
            go_t   <= 6'd0;
        end else begin
            go_div <= go_div + 1'b1;
            if (&go_div && go_t != 6'd36) go_t <= go_t + 6'd1;
        end
    end
    wire go_results = (go_t == 6'd36);
    wire go_blink   = !go_t[2];                    // on 4 steps, off 4 steps
    // to the pixel clock, to hide the chart (and show the title pictures)
    reg        go_c, ti_c;
    reg  [1:0] go_p, ti_p;
    always @(posedge clk)  begin go_c <= (screen_state == `UI_GAME_END); ti_c <= (screen_state == `UI_TITLE); end
    // the bot view shows the news feed where the chart is: no chart then
    reg        bv_c;
    reg  [1:0] bv_p;
    always @(posedge clk)  bv_c <= oled_bot_view;
    always @(posedge pclk) bv_p <= {bv_p[0], bv_c};
    reg  [2:0] bs_c, bs_p0, bs_p;                // the chosen bot (changes rarely)
    always @(posedge clk)  bs_c <= bot_sel;
    always @(posedge pclk) begin bs_p0 <= bs_c; bs_p <= bs_p0; end
    always @(posedge pclk) begin go_p <= {go_p[0], go_c}; ti_p <= {ti_p[0], ti_c}; end
    reg  [1:0] bl_c, bl_p;                 // bar_level changes one bit at a time
    always @(posedge pclk) begin bl_c <= bar_level; bl_p <= bl_c; end
    wire [11:0] bar_rgb = (bl_p == 2'd3) ? 12'hF22 : bl_p[0] ? 12'hFC0 : 12'h0D2;

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
        .oled_bot_view(oled_bot_view), .orders_view(orders_view), .up(stock_up), .num_f(num_f), .num_rd(num_rd), .zero(zero), .bot_sel(bot_sel), .order(order),
        .go_blink(go_blink), .go_results(go_results),
        .book_valid(book_valid), .book_side(book_side), .book_stock(book_stock),
        .book_type(book_type), .book_leg(book_leg),
        .feed_valid(feed_valid), .feed_bot(feed_bot), .feed_side(feed_side), .feed_stock(feed_stock),
        .quantity_cursor(quantity_cursor), .orders_sel(orders_sel),
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

    // ------------------------------------------------------------ title screen
    // One 320 x 180 picture (title_art_vga.mem), each pixel 4 x 4, filling the
    // screen, in its own 16 colours. PRESS BTNC TO START blinks: shown for
    // 2^TITLE_BLINK frames, then rows TITLE_BTN_ROW down show the background.
    // tx / ty: the picture pixel of (h, v), txs / tys count its 4 screen pixels,
    // t_row: ty x 320, so the address needs no multiply.
    (* rom_style = "block" *) reg [3:0] title_pic [0:57599];
    initial $readmemh("title_art_vga.mem", title_pic);
    reg  [5:0] t_frame;                        // frames, for the blink
    wire       t_blink = !t_frame[TITLE_BLINK];
    function [11:0] title_rgb;                 // the title picture's 16 colours, 4 bits each
        input [3:0] c;
        begin
            case (c)
                4'h0: title_rgb = 12'h112; 4'h1: title_rgb = 12'h235; 4'h2: title_rgb = 12'h812; 4'h3: title_rgb = 12'h183;
                4'h4: title_rgb = 12'h862; 4'h5: title_rgb = 12'h358; 4'h6: title_rgb = 12'h1E4; 4'h7: title_rgb = 12'hE32;
                4'h8: title_rgb = 12'hD91; 4'h9: title_rgb = 12'h0CD; 4'hA: title_rgb = 12'h48D; 4'hB: title_rgb = 12'h998;
                4'hC: title_rgb = 12'hEE1; 4'hD: title_rgb = 12'hABD; 4'hE: title_rgb = 12'hED9; default: title_rgb = 12'hDEE;
            endcase
        end
    endfunction
    reg  [8:0]  tx;
    reg  [7:0]  ty;
    reg  [1:0]  txs, tys;
    reg  [15:0] t_row;
    initial begin t_frame = 6'd0; tx = 9'd0; ty = 8'd0; txs = 2'd0; tys = 2'd0; t_row = 16'd0; end
    always @(posedge pclk) begin
        if (h == 11'd1649) begin                // the next line starts at the left
            tx <= 9'd0; txs <= 2'd0;
            if (v == 10'd749) begin             // and the next frame at the top
                ty <= 8'd0; tys <= 2'd0; t_row <= 16'd0;
                t_frame <= t_frame + 6'd1;
            end else if (tys == 2'd3) begin
                tys <= 2'd0; ty <= ty + 8'd1; t_row <= t_row + 16'd320;
            end else
                tys <= tys + 2'd1;
        end else if (txs == 2'd3) begin
            txs <= 2'd0; tx <= tx + 9'd1;
        end else
            txs <= txs + 2'd1;
    end

    // ------------------------------------------------------------ bot view: the chosen bot's picture
    // its 62 x 46 box from the title picture (rows 98-143), drawn 3 x at x 650..835,
    // y 411..548 (the left of the chosen bot's panel, rows 17-22). Only the bot and
    // its props are drawn: the box's background colours (0, 1, 5), its shelf
    // (box rows 37 down) and its edges (3 pixels each side) are left to the panel.
    localparam [10:0] BX0 = 11'd650;
    localparam [9:0]  BY0 = 10'd411;
    reg  [8:0]  b_src;                          // the box's left edge in the title picture
    always @* begin
        case (bs_p)
            3'd0:    b_src = 9'd6;              // MA BOT
            3'd1:    b_src = 9'd70;             // OVERNIGHT
            3'd2:    b_src = 9'd129;            // MOMENTUM
            3'd3:    b_src = 9'd191;            // AVG DOWN
            default: b_src = 9'd255;            // SL / TP
        endcase
    end
    reg  [5:0]  gx, gy;
    reg  [1:0]  gxs, gys;
    reg  [15:0] g_row;                          // (98 + gy) x 320
    initial begin gx = 6'd0; gy = 6'd0; gxs = 2'd0; gys = 2'd0; g_row = 16'd31360; end
    always @(posedge pclk) begin
        if (h == 11'd1649) begin
            gx <= 6'd0; gxs <= 2'd0;
            if (v == BY0 - 10'd1) begin gy <= 6'd0; gys <= 2'd0; g_row <= 16'd31360; end
            else if (gys == 2'd2) begin gys <= 2'd0; gy <= gy + 6'd1; g_row <= g_row + 16'd320; end
            else gys <= gys + 2'd1;
        end else if (h >= BX0) begin
            if (gxs == 2'd2) begin gxs <= 2'd0; gx <= gx + 6'd1; end
            else gxs <= gxs + 2'd1;
        end
    end

    // ------------------------------------------------------------ pixel pipeline
    // stage 1: RAM address, the pixel's position, its chart day
    reg  [10:0] s1_h;
    reg  [9:0]  s1_v;
    reg  [4:0]  s1_px, s1_ly, s1_bn;
    reg  [3:0]  s1_bp;
    reg         s1_vis, s1_hs, s1_vs;
    reg  [15:0] art_addr;
    reg         s1_art, s1_btn, s1_bimg;
    wire [10:0] bx = h - 11'd18;               // chart x: day = bx / 16
    always @(posedge pclk) begin
        rd_addr <= {cy, cx};
        art_addr <= ti_p[1] ? t_row + {7'd0, tx}  // the title: ty * 320 + tx
                            : g_row + {7'd0, b_src} + {10'd0, gx};   // the chosen bot's box
        s1_bimg  <= bv_p[1] && !go_p[1] && !ti_p[1] && (h >= BX0) && (h < BX0 + 11'd186) &&
                    (v >= BY0) && (v < BY0 + 10'd138) &&
                    (gx >= 6'd3) && (gx < 6'd59) && (gy >= 6'd3) && (gy < 6'd37);
        s1_btn   <= (ty >= TITLE_BTN_ROW);
        s1_art  <= (h < 11'd1280) && (v < 10'd720);
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
    reg  [3:0]  p_tpx;
    reg         p_art, p_btn, p_bimg;
    always @(posedge pclk) begin
        p_tpx   <= title_pic[art_addr];
        p_art   <= s1_art && ti_p[1];
        p_btn   <= s1_btn;
        p_bimg  <= s1_bimg;
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
    wire       in_chart = !go_p[1] && !ti_p[1] && !bv_p[1] && (p_h >= 11'd18) && (p_h <= 11'd497) && (p_v >= 10'd240) && (p_v <= 10'd479);
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
        if (p_art)                                  s2_gfx <= title_rgb((p_btn && !t_blink) ? 4'h0 : p_tpx);
        else if (p_bimg && p_tpx != 4'h0 && p_tpx != 4'h1 && p_tpx != 4'h5)
                                                    s2_gfx <= title_rgb(p_tpx);
        else if (in_bar)                            s2_gfx <= bar_on ? bar_rgb : 12'h222;
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
