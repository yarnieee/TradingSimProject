`timescale 1ns / 1ps
`include "trading_defs.vh"

// vga_cells: what the VGA monitor shows, cell by cell (71 columns x 30 rows of
// 18 x 24 pixel cells on a 1280 x 720 screen). For the cell (row, col) it gives
// the character (ASCII, Matthew's 5x7 font drawn 3x) and two 4-bit colours
// (palette in vga_screen). The chart and the progress bar are graphics drawn by
// vga_screen in the areas this module leaves blank.
//
// Two panels side by side (left cells 1-34, right cells 36-69), each section
// with a header bar:
//
//   row 0       title bar                                      days left
//   row 1       game progress bar (graphics)
//   rows 2-7    MARKET: price, 30-day change $ / %  | YOUR PORTFOLIO
//   rows 9-19   <stock> LAST 30 DAYS: chart with    | HOLDINGS (rows 9-14)
//               high / low and SL / TP prices       | PENDING ORDERS (rows 16-25), or
//                                                   | TRADE CONTROLS (rows 16-26) while
//                                                   | an order is being made
//   rows 20-26  LEADERBOARD: you and the 5 bots in  |
//               place order, net worth and return   |
//   rows 28-29  the bots' two latest trades, newest on top (each stays until a
//               newer one pushes it down): day, bot, BUYS / SELLS, stock, price, why
// BOT VIEW (sw15 up), in purple: the left rows 9-19 are LATEST TRADES (the last 8
// trades of all the bots, newest on top) instead of the chart, and the right rows
// 16-26 the bot chosen on the OLEDs (net worth, cash, profit / loss, return,
// holdings) instead of PENDING ORDERS. The rest stays as it is.
// TITLE: vga_screen's title picture covers the whole screen (these cells are hidden under it).
// GAME OVER (rows 2-27 instead): a big flashing GAME OVER for a few seconds,
// then GAME OVER at the top and the final results, 1st to 6th, below it.
//
// Colours: labels grey, values white, gains / buys green, losses / sells red,
// yellow only for what is selected or needs attention.
module vga_cells (
    input  [4:0]  row,
    input  [6:0]  col,
    input  [3:0]  screen_state,
    input  [3:0]  menu_selection,
    input  [2:0]  selected_stock,
    input         trade_side,          // 0 buy, 1 sell
    input         trade_result_success,
    input         trade_result_placed,
    input  [2:0]  trade_result_code,
    input         order_valid,
    input  [2:0]  validation_code,
    input  [1:0]  order_type,          // from the switches
    input  [1:0]  order_brk,
    input  [1:0]  order_dist,          // sw[7:6]: 1, 2, 5, 10%
    input         oled_bot_view,       // sw15
    input         orders_view,         // sw14: the buttons are on the left OLED's ORDERS list
    input  [2:0]  bot_sel,             // the bot the OLEDs show in the bot view
    input  [17:0] order,               // who is in place p+1 at [3*p +: 3]: 0 you, n+1 bot n
    input         go_blink,            // game over: the big GAME OVER is lit now
    input         go_results,          // game over: show the final results
    input  [3:0]  up,                  // stock k at or above its price 30 days ago
    output reg [6:0] num_f,            // the display_numbers field this cell shows
    input  [32:0] num_rd,              // that field from display_numbers' RAM: {negative, 8 digits}
    input  [`DN_N-1:0] zero,           // field f is 0
    input  [7:0]  book_valid,
    input  [7:0]  book_side,
    input  [15:0] book_stock,
    input  [15:0] book_type,
    input  [7:0]  book_leg,
    input  [7:0]  feed_valid,          // the bots' last 8 trades, entry 0 newest
    input  [23:0] feed_bot,            // 0 moving average, 1-4 bot_squad 0-3
    input  [7:0]  feed_side,
    input  [15:0] feed_stock,
    output reg [7:0] ch,
    output reg [3:0] fg,
    output reg [3:0] bg
);
    // palette indices (colours in vga_screen)
    localparam [3:0] K_BLACK = 4'd0, K_WHITE = 4'd1, K_CYAN = 4'd2, K_YELLOW = 4'd3,
                     K_GREEN = 4'd4, K_RED = 4'd5, K_GREY = 4'd6, K_NAVY = 4'd7,
                     K_DGREY = 4'd8, K_PLUM = 4'd9, K_ORANGE = 4'd10, K_PANEL = 4'd11,
                     K_ROW = 4'd12, K_PURPLE = 4'd13, K_PROW = 4'd14;

    // ------------------------------------------------------------ helpers
    function [7:0] s16;                    // character c of a 16-character string
        input [127:0] s;
        input [6:0]   c;
        begin
            s16 = (c > 7'd15) ? " " : s[127 - 8*c -: 8];
        end
    endfunction

    function [7:0] s64;                    // character c of a 64-character string
        input [511:0] s;
        input [6:0]   c;
        begin
            s64 = (c > 7'd63) ? " " : s[511 - 8*c -: 8];
        end
    endfunction

    function [7:0] ticker_ch;              // AMD, MCD, NVDA, GME
        input [1:0] k;
        input [6:0] p;
        reg [31:0] t;
        begin
            case (k)
                2'd0:    t = "AMD ";
                2'd1:    t = "MCD ";
                2'd2:    t = "NVDA";
                default: t = "GME ";
            endcase
            ticker_ch = (p > 7'd3) ? " " : t[31 - 8*p -: 8];
        end
    endfunction

    // right-aligned number, w cells; dp2 = cents; prefix e.g. "$"; sgn = show +/-
    function [7:0] num_ch;
        input [31:0] d;
        input        sgn;
        input        is_neg;
        input        dp2;
        input [7:0]  prefix;
        input [6:0]  w;
        input [6:0]  p;
        integer r, msd, rm, j, i;
        reg [7:0] sign_c;
        begin
            r = w - 1 - p;
            msd = dp2 ? 2 : 0;
            for (j = 0; j < 8; j = j + 1)
                if (d[4*j +: 4] != 4'd0 && j > msd) msd = j;
            rm = (dp2 && msd >= 2) ? msd + 1 : msd;
            sign_c = is_neg ? "-" : "+";
            num_ch = " ";
            if (r <= rm) begin
                if (dp2 && r == 2) num_ch = ".";
                else begin
                    i = (dp2 && r > 2) ? r - 1 : r;
                    num_ch = "0" + d[4*i +: 4];
                end
            end else if (r == rm + 1) begin
                if (prefix != 8'd0) num_ch = prefix;
                else if (sgn)       num_ch = sign_c;
            end else if (r == rm + 2) begin
                if (prefix != 8'd0 && sgn) num_ch = sign_c;
            end
        end
    endfunction

    function [87:0] bot_name;              // leaderboard entry e: 0 you, 1-5 bots 0-4 (11 cells)
        input [2:0] e;
        begin
            case (e)
                3'd0:    bot_name = "YOU        ";
                3'd1:    bot_name = "MA BOT     ";
                3'd2:    bot_name = "OVERNIGHT  ";
                3'd3:    bot_name = "MOMENTUM   ";
                3'd4:    bot_name = "AVG DOWN   ";
                default: bot_name = "SL / TP    ";
            endcase
        end
    endfunction

    function [52:0] big_row;               // row r of a big GAME OVER: 5 x 7 letters, one cell a dot
        input [2:0] r;
        begin
            case (r)
                3'd0: big_row = 53'b01110001110010001011111000000001110010001011111011110;
                3'd1: big_row = 53'b10001010001011011010000000000010001010001010000010001;
                3'd2: big_row = 53'b10000010001010101010000000000010001010001010000010001;
                3'd3: big_row = 53'b10111011111010101011110000000010001010001011110011110;
                3'd4: big_row = 53'b10001010001010001010000000000010001010001010000010100;
                3'd5: big_row = 53'b10001010001010001010000000000010001001010010000010010;
                default: big_row = 53'b01111010001010001011111000000001110000100011111010001;
            endcase
        end
    endfunction

    function [7:0] place_ch;               // 1ST .. 6TH in 3 cells
        input [2:0] p;                     // 0..5
        input [6:0] c;
        reg [143:0] t;
        begin
            t = "1ST2ND3RD4TH5TH6TH";
            place_ch = (c > 7'd2) ? " " : t[143 - 24*p - 8*c -: 8];
        end
    endfunction

    function [7:0] reason_ch;              // why an order is / was rejected
        input [2:0] code;
        input [6:0] c;
        begin
            case (code)
                `RJ_NO_CASH:   reason_ch = s16("NOT ENOUGH CASH ", c);
                `RJ_NO_POS:    reason_ch = s16("TOO FEW SHARES  ", c);
                `RJ_BOOK_FULL: reason_ch = s16("ORDER BOOK FULL ", c);
                `RJ_BAD_QTY:   reason_ch = s16("QTY 1 TO 255    ", c);
                `RJ_BAD_TRIG:  reason_ch = s16("BAD TRIGGER     ", c);
                `RJ_TRIG_FAIL: reason_ch = s16("TRIGGER FAILED  ", c);
                `RJ_NOT_LIVE:  reason_ch = s16("MARKET CLOSED   ", c);
                default:       reason_ch = s16("                ", c);
            endcase
        end
    endfunction

    function [7:0] why_ch;                 // why bot b bought / sold (its rule), 21 cells
        input [2:0] b;
        input       sold;
        input [6:0] c;
        reg [167:0] t;
        begin
            case ({b, sold})
                {3'd0, 1'b0}: t = "ABOVE ITS 8-DAY AVG  ";
                {3'd0, 1'b1}: t = "BELOW ITS 8-DAY AVG  ";
                {3'd1, 1'b0}: t = "HOLDING OVERNIGHT    ";
                {3'd1, 1'b1}: t = "SOLD AT THE OPEN     ";
                {3'd2, 1'b0}: t = "RIDING THE RALLY     ";
                {3'd2, 1'b1}: t = "THE TREND BROKE      ";
                {3'd3, 1'b0}: t = "BUYING THE DIP       ";
                {3'd3, 1'b1}: t = "TOOK ITS 5% PROFIT   ";
                {3'd4, 1'b0}: t = "NEW POSITION         ";
                default:      t = "STOP OR TARGET HIT   ";
            endcase
            why_ch = (c > 7'd20) ? " " : t[167 - 8*c -: 8];
        end
    endfunction

    function [7:0] type_word;              // MARKET / LIMIT / STOP in 6 cells
        input [1:0] t;
        input [6:0] c;
        begin
            case (t)
                `OT_LMT: type_word = s16("LIMIT           ", c);
                `OT_STP: type_word = s16("STOP            ", c);
                default: type_word = s16("MARKET          ", c);
            endcase
        end
    endfunction

    function [7:0] pct_word;               // OFF / 2% / 5% / 10% (sw codes) in 3 cells
        input [1:0] v;
        input       dist;                  // 1: distance codes 1, 2, 5, 10%
        input [6:0] c;
        begin
            case (v)
                2'd0:    pct_word = s16(dist ? "1%              " : "OFF             ", c);
                2'd1:    pct_word = s16("2%              ", c);
                2'd2:    pct_word = s16("5%              ", c);
                default: pct_word = s16("10%             ", c);
            endcase
        end
    endfunction

    // ------------------------------------------------------------ numbers
    wire [1:0]  s       = selected_stock[1:0];
    // market rows 4-7 -> stocks 0-3; holdings rows 11-14 -> stocks 0-3
    wire [1:0]  mk      = row[1:0];
    wire [1:0]  hk      = row[1:0] + 2'd1;

    // pending orders: row 18 + n shows the n-th order in the book (only real ones)
    wire [2:0]  pn = row[2:0] - 3'd2;                     // rows 18-25 -> 0-7
    reg  [2:0]  sl;                                       // its book slot
    reg         sl_ok;
    integer     q, cnt;
    always @* begin
        sl = 3'd0; sl_ok = 1'b0; cnt = 0;
        for (q = 0; q < 8; q = q + 1)
            if (book_valid[q]) begin
                if (cnt == pn && !sl_ok) begin sl = q; sl_ok = 1'b1; end
                cnt = cnt + 1;
            end
    end
    wire [1:0]  sl_stk  = book_stock[2*sl +: 2];
    wire [1:0]  sl_typ  = book_type[2*sl +: 2];
    wire [3:0]  pending = book_valid[0] + book_valid[1] + book_valid[2] + book_valid[3]
                        + book_valid[4] + book_valid[5] + book_valid[6] + book_valid[7];

    // leaderboard rows 21-26 in place order, 1st at the top; entry 0 you, 1-5 bots 0-4
    wire [2:0]  lb_pos  = row[2:0] - 3'd5;                 // rows 21-26 -> 0-5
    wire [2:0]  place   = lb_pos + 3'd1;
    wire [2:0]  ent     = order[3*lb_pos +: 3];
    wire        shown   = oled_bot_view ? (ent == bot_sel + 3'd1) : (ent == 3'd0);  // on the OLEDs now

    // game over: results rows 14-19 in place order; where you finished
    wire        go      = (screen_state == `UI_GAME_END);
    wire [2:0]  go_pos  = row[2:0] - 3'd6;                 // rows 14-19 -> 0-5
    wire [2:0]  go_ent  = order[3*go_pos +: 3];
    wire [2:0]  you_pos = (order[2:0]   == 3'd0) ? 3'd0 : (order[5:3]   == 3'd0) ? 3'd1 :
                          (order[8:6]   == 3'd0) ? 3'd2 : (order[11:9]  == 3'd0) ? 3'd3 :
                          (order[14:12] == 3'd0) ? 3'd4 : 3'd5;
    // the big GAME OVER: cols 9-61, rows 11-17 while it flashes, rows 3-9 above the results
    wire [4:0]  big_r   = row - (go_results ? 5'd3 : 5'd11);
    wire [6:0]  big_c   = col - 7'd9;
    wire [52:0] big_bits = big_row(big_r[2:0]);
    wire        big_on  = (big_r <= 5'd6) && (col >= 7'd9) && (col <= 7'd61) && big_bits[7'd52 - big_c];

    // bot view (sw15 up) on the game screens; the feed entry this row shows:
    // left rows 11-18 in the bot view -> 0..7, notification rows 28 / 29 -> 0 / 1
    wire        bv     = oled_bot_view && !go;
    wire [2:0]  fe     = (row >= 5'd28) ? {2'b00, row[0]} : row[2:0] - 3'd3;
    wire        f_ok   = feed_valid[fe];
    wire [2:0]  f_bot  = feed_bot[3*fe +: 3];
    wire        f_sell = feed_side[fe];
    wire [1:0]  f_stk  = feed_stock[2*fe +: 2];

    wire in_order = (screen_state == `UI_BUY_STOCK) || (screen_state == `UI_SELL_STOCK) ||
                    (screen_state == `UI_QUANTITY)  || (screen_state == `UI_ORDER_REVIEW);
    // the right panel shows TRADE CONTROLS instead of PENDING ORDERS while an order
    // is being made, unless the buttons work the OLEDs (sw14 orders list, sw15 bot)
    wire ctl = in_order && !orders_view && !oled_bot_view;
    wire ctl_menu = (screen_state == `UI_BUY_STOCK) || (screen_state == `UI_SELL_STOCK);
    // a limit buy / stop sell waits below the price, a limit sell / stop buy above it
    wire below = ((order_type == `OT_LMT) && !trade_side) || ((order_type == `OT_STP) && trade_side);
    wire left  = (col >= 7'd1)  && (col <= 7'd34);
    wire right = (col >= 7'd36) && (col <= 7'd69);
    wire [6:0] cl = col - 7'd1;                           // column inside the left panel, 0..33
    wire [6:0] cr = col - 7'd36;                          // column inside the right panel, 0..33

    // A cell shows at most one number. Work out which field and how it is
    // laid out, read that one field, and format it with one num_ch for the
    // whole screen (the cell logic below only says where it goes).
    reg        d_sgn;                                     // show + / - when not zero
    reg        d_sh8;                                     // drop two digits (P/L -> return %)
    reg        d_dp2;
    reg [7:0]  d_prefix;
    reg [6:0]  d_w, d_p;
    always @* begin
        num_f = `DN_CASH; d_sgn = 1'b0; d_sh8 = 1'b0; d_dp2 = 1'b1; d_prefix = "$"; d_w = 7'd1; d_p = 7'd0;
        if (row == 5'd0) begin                                                    // days left
            num_f = `DN_DAYS; d_dp2 = 1'b0; d_prefix = 8'd0; d_w = 7'd3; d_p = col - 7'd67;
        end else if (go && row <= 5'd27) begin                                    // final results
            if (col <= 7'd39)      begin num_f = (go_ent == 3'd0) ? `DN_NET : `DN_LBNET0 + go_ent - 7'd1; d_w = 7'd11; d_p = col - 7'd28; end
            else begin
                num_f = (go_ent == 3'd0) ? `DN_NETPNL : `DN_LBPNL0 + go_ent - 7'd1; d_sgn = 1'b1;
                if (col <= 7'd54)  begin d_w = 7'd12; d_p = col - 7'd42; end
                else               begin d_sh8 = 1'b1; d_prefix = 8'd0; d_w = 7'd7; d_p = col - 7'd57; end
            end
        end else if (row >= 5'd28) begin                                          // notifications
            if (col <= 7'd20) begin num_f = `DN_FDAY0 + fe; d_dp2 = 1'b0; d_prefix = 8'd0; d_w = 7'd3; d_p = col - 7'd9; end
            else              begin num_f = `DN_FPX0 + fe;  d_w = 7'd8; d_p = col - 7'd39; end
        end else if (bv && left && row >= 5'd11 && row <= 5'd18) begin           // the news feed
            if (cl <= 7'd10) begin num_f = `DN_FDAY0 + fe; d_dp2 = 1'b0; d_prefix = 8'd0; d_w = 7'd3; d_p = cl - 7'd1; end
            else             begin num_f = `DN_FPX0 + fe;  d_w = 7'd8; d_p = cl - 7'd26; end
        end else if (bv && right && row >= 5'd17) begin                          // the chosen bot
            case (row)
                5'd17: begin num_f = `DN_BNET;    d_w = 7'd17; d_p = cr - 7'd17; end
                5'd18: begin num_f = `DN_BCASH;   d_w = 7'd17; d_p = cr - 7'd17; end
                5'd19: begin num_f = `DN_BNETPNL; d_sgn = 1'b1; d_w = 7'd17; d_p = cr - 7'd17; end
                5'd20: begin num_f = `DN_BNETPNL; d_sh8 = 1'b1; d_sgn = 1'b1; d_prefix = 8'd0; d_w = 7'd16; d_p = cr - 7'd17; end
                5'd23, 5'd24, 5'd25, 5'd26: begin                                 // its holdings
                    if (cr <= 7'd18) begin num_f = `DN_BPOS0 + hk; d_dp2 = 1'b0; d_prefix = 8'd0; d_w = 7'd6; d_p = cr - 7'd13; end
                    else             begin num_f = `DN_BPNL0 + hk; d_sgn = 1'b1; d_w = 7'd12; d_p = cr - 7'd22; end
                end
                default: ;
            endcase
        end else if (left) begin
            if (row >= 5'd4 && row <= 5'd7) begin                                 // market
                if (cl <= 7'd14)      begin num_f = `DN_PX0 + mk;  d_w = 7'd8; d_p = cl - 7'd7; end
                else if (cl <= 7'd23) begin num_f = `DN_CHG0 + mk; d_sgn = 1'b1; d_w = 7'd8; d_p = cl - 7'd16; end
                else begin num_f = `DN_PCT0 + mk; d_sgn = 1'b1; d_prefix = 8'd0; d_w = 7'd7; d_p = cl - 7'd26; end
            end else if (row >= 5'd10 && row <= 5'd19) begin                      // chart labels
                num_f = (row == 5'd10) ? `DN_CHI : (row == 5'd19) ? `DN_CLO :
                        (row == 5'd14) ? `DN_SL  : `DN_TP;
                d_w = 7'd7; d_p = cl - 7'd27;
            end else if (row >= 5'd21) begin                                      // leaderboard
                // return % = P/L / $100.00 (everyone starts with $10,000.00): drop 2 digits
                if (cl <= 7'd24) begin num_f = (ent == 3'd0) ? `DN_NET : `DN_LBNET0 + ent - 7'd1; d_w = 7'd11; d_p = cl - 7'd14; end
                else begin
                    num_f = (ent == 3'd0) ? `DN_NETPNL : `DN_LBPNL0 + ent - 7'd1;
                    d_sh8 = 1'b1; d_sgn = 1'b1; d_prefix = 8'd0; d_w = 7'd7; d_p = cl - 7'd26;
                end
            end
        end else if (ctl && row >= 5'd17) begin                                   // trade controls
            case (row)
                5'd18: begin num_f = `DN_QTY;    d_dp2 = 1'b0; d_prefix = 8'd0; d_w = 7'd17; d_p = cr - 7'd17; end
                5'd20: begin num_f = `DN_ORDPX;  d_w = 7'd17; d_p = cr - 7'd17; end
                5'd21: begin num_f = `DN_ORDTOT; d_w = 7'd17; d_p = cr - 7'd17; end
                default: ;
            endcase
        end else begin
            case (row)                                                            // portfolio
                5'd3: begin num_f = `DN_NET;    d_w = 7'd17; d_p = cr - 7'd17; end
                5'd4: begin num_f = `DN_CASH;   d_w = 7'd17; d_p = cr - 7'd17; end
                5'd5: begin num_f = `DN_NETPNL; d_sgn = 1'b1; d_w = 7'd17; d_p = cr - 7'd17; end
                5'd6: begin num_f = `DN_RET;    d_sgn = 1'b1; d_prefix = 8'd0; d_w = 7'd16; d_p = cr - 7'd17; end
                5'd7: begin num_f = `DN_MAXDD;  d_prefix = 8'd0; d_w = 7'd16; d_p = cr - 7'd17; end
                5'd11, 5'd12, 5'd13, 5'd14: begin                                 // holdings
                    if (cr <= 7'd18) begin num_f = `DN_POS0 + hk; d_dp2 = 1'b0; d_prefix = 8'd0; d_w = 7'd6; d_p = cr - 7'd13; end
                    else             begin num_f = `DN_PNL0 + hk; d_sgn = 1'b1; d_w = 7'd12; d_p = cr - 7'd22; end
                end
                5'd18, 5'd19, 5'd20, 5'd21, 5'd22, 5'd23, 5'd24, 5'd25: begin     // pending orders
                    if (cr <= 7'd24) begin num_f = `DN_SLQ0 + sl; d_dp2 = 1'b0; d_prefix = 8'd0; d_w = 7'd4; d_p = cr - 7'd21; end
                    else             begin num_f = `DN_SLT0 + sl; d_w = 7'd8; d_p = cr - 7'd26; end
                end
                default: ;
            endcase
        end
    end

    wire [31:0] num_v    = d_sh8 ? num_rd[31:0] >> 8 : num_rd[31:0];
    wire        num_neg  = num_rd[32];
    wire        num_zero = (num_v == 32'd0);
    wire [7:0]  num_char = num_ch(num_v, d_sgn && !num_zero, num_neg, d_dp2, d_prefix, d_w, d_p);


    always @* begin
        ch = " ";
        fg = K_WHITE;
        bg = K_BLACK;

        // ------------------------------------------------------------ title bar
        if (row == 5'd0) begin
            bg = K_NAVY;
            if (col >= 7'd1 && col <= 7'd28)       ch = s64("SCAM STOCK TRADING SIMULATOR                                    ", cl);
            else if (bv && col >= 7'd32 && col <= 7'd39) begin ch = s16("BOT VIEW        ", col - 7'd32); fg = K_YELLOW; end
            else if (col >= 7'd57 && col <= 7'd65) begin ch = s16("DAYS LEFT       ", col - 7'd57); fg = K_GREY; end
            else if (col >= 7'd67 && col <= 7'd69) begin
                ch = num_char;
                fg = (num_v[31:4] == 28'd0 && num_v[3:0] <= 4'd5) ? K_RED : K_YELLOW;
            end
        end

        // ------------------------------------------------------------ GAME OVER (rows 2-27)
        else if (go && row >= 5'd2 && row <= 5'd27) begin
            if (big_on) begin
                if (go_results || go_blink) bg = K_RED;
            end
            else if (!go_results) ;
            else if (row == 5'd11) begin
                if (col >= 7'd29 && col <= 7'd41) begin ch = s16("FINAL RESULTS   ", col - 7'd29); fg = K_YELLOW; end
            end
            else if (row == 5'd13) begin    //   PLACE   NAME             NET WORTH   PROFIT / LOSS     RETURN
                fg = K_GREY; bg = K_NAVY;
                if (col >= 7'd6 && col <= 7'd10)       ch = s16("PLACE           ", col - 7'd6);
                else if (col >= 7'd14 && col <= 7'd17) ch = s16("NAME            ", col - 7'd14);
                else if (col >= 7'd30 && col <= 7'd38) ch = s16("NET WORTH       ", col - 7'd30);
                else if (col >= 7'd41 && col <= 7'd53) ch = s16("PROFIT / LOSS   ", col - 7'd41);
                else if (col >= 7'd59 && col <= 7'd64) ch = s16("RETURN          ", col - 7'd59);
            end
            else if (row >= 5'd14 && row <= 5'd19) begin   //  1ST  OVERNIGHT   $10123.45   +$123.45   +1.23%
                if (go_ent == 3'd0) bg = K_ROW;
                if (col >= 7'd6 && col <= 7'd8)        begin ch = place_ch(go_pos, col - 7'd6); fg = (go_pos == 3'd0) ? K_YELLOW : K_WHITE; end
                else if (col >= 7'd14 && col <= 7'd24) begin ch = bot_name(go_ent) >> (8 * (7'd24 - col)); fg = (go_ent == 3'd0) ? K_CYAN : K_WHITE; end
                else if (col >= 7'd28 && col <= 7'd38) ch = num_char;
                else if (col >= 7'd42 && col <= 7'd53) begin ch = num_char; fg = num_zero ? K_WHITE : num_neg ? K_RED : K_GREEN; end
                else if (col >= 7'd57 && col <= 7'd63) begin ch = num_char; fg = num_zero ? K_WHITE : num_neg ? K_RED : K_GREEN; end
                else if (col == 7'd64)                 ch = "%";
            end
            else if (row == 5'd21) begin    // YOU WIN!  YOU BEAT ALL 5 BOTS  /  YOU FINISHED 3RD OF 6    WINNER: OVERNIGHT
                if (you_pos == 3'd0) begin
                    if (col >= 7'd6 && col <= 7'd34) begin ch = s64("YOU WIN!   YOU BEAT ALL 5 BOTS                                  ", col - 7'd6); fg = K_GREEN; end
                end
                else if (col >= 7'd6 && col <= 7'd18)  ch = s16("YOU FINISHED    ", col - 7'd6);
                else if (col >= 7'd19 && col <= 7'd21) begin ch = place_ch(you_pos, col - 7'd19); fg = K_YELLOW; end
                else if (col >= 7'd22 && col <= 7'd26) ch = s16(" OF 6           ", col - 7'd22);
                else if (col >= 7'd31 && col <= 7'd37) begin ch = s16("WINNER:         ", col - 7'd31); fg = K_GREY; end
                else if (col >= 7'd39 && col <= 7'd49) begin ch = bot_name(order[2:0]) >> (8 * (7'd49 - col)); fg = K_YELLOW; end
            end
            else if (row == 5'd23 && col >= 7'd6 && col <= 7'd39) begin
                ch = s64("NEW GAME: SW0 UP, THEN DOWN                                     ", col - 7'd6); fg = K_GREY;
            end
        end

        // ------------------------------------------------------------ TITLE (rows 2-27): pictures above
        else if (screen_state == `UI_TITLE && row >= 5'd2 && row <= 5'd27) begin
            if (row == 5'd21 && col >= 7'd26 && col <= 7'd44) begin
                ch = s64("PRESS BTNC TO START                                             ", col - 7'd26);
                fg = K_YELLOW;
            end
        end

        // ------------------------------------------------------------ panel header bars
        else if ((row == 5'd2 || row == 5'd9 || row == 5'd20) && left) begin
            bg = K_PANEL;
            case (row)
                5'd2: ch = s16(" MARKET         ", cl);
                5'd9: begin                                   //  MCD  LAST 30 DAYS  /  LATEST TRADES  ALL BOTS
                    if (bv) begin
                        ch = s64(" LATEST TRADES                                                  ", cl);
                        if (cl >= 7'd26) begin ch = s16("ALL BOTS        ", cl - 7'd26); fg = K_GREY; end
                    end
                    else if (cl >= 7'd1 && cl <= 7'd4) begin ch = ticker_ch(s, cl - 7'd1); fg = K_YELLOW; end
                    else if (cl >= 7'd6)            ch = s16("LAST 30 DAYS    ", cl - 7'd6);
                end
                default: begin                                //  # LEADERBOARD  NET WORTH   RETURN
                    ch = s64(" # LEADERBOARD  NET WORTH   RETURN                              ", cl);
                    if (screen_state == `UI_GAME_END && cl >= 7'd3 && cl <= 7'd13) begin
                        ch = s16("FINAL           ", cl - 7'd3); fg = K_YELLOW;
                    end
                end
            endcase
        end
        else if ((row == 5'd2 || row == 5'd9 || row == 5'd16) && right) begin
            bg = K_PANEL;
            case (row)
                5'd2: ch = s16(" YOUR PORTFOLIO ", cr);
                5'd9: ch = s16(" HOLDINGS       ", cr);
                default: begin                                //  PENDING ORDERS          2 OF 8
                    if (bv) begin                             //  MOMENTUM            BTNL / BTNR
                        if (cr >= 7'd1 && cr <= 7'd11) begin ch = bot_name(bot_sel + 3'd1) >> (8 * (7'd11 - cr)); fg = K_YELLOW; end
                        else if (cr >= 7'd23)          begin ch = s16("BTNL / BTNR     ", cr - 7'd23); fg = K_GREY; end
                    end
                    else if (cr <= 7'd15)                ch = s16(ctl ? " TRADE CONTROLS " : " PENDING ORDERS ", cr);
                    else if (ctl && cr >= 7'd17 && cr <= 7'd20) begin   //  TRADE CONTROLS  BUY     2 OF 8
                        ch = s16(trade_side ? "SELL            " : "BUY             ", cr - 7'd17);
                        fg = trade_side ? K_RED : K_GREEN;
                    end
                    else if (cr == 7'd28)                begin ch = "0" + pending; fg = (pending == 4'd8) ? K_YELLOW : K_WHITE; end
                    else if (cr >= 7'd30 && cr <= 7'd33) ch = s16("OF 8            ", cr - 7'd30);
                end
            endcase
        end

        // ------------------------------------------------------------ MARKET (left, rows 3-7)
        else if (row == 5'd3 && left) begin                  // column names
            fg = K_GREY;
            ch = s64("  STOCK   PRICE    30-DAY CHANGE                                ", cl);
        end
        else if (row >= 5'd4 && row <= 5'd7 && left) begin   // > AMD  $207.02  -$12.34 v  -5.63%
            if (cl == 7'd0)                       begin ch = (mk == s) ? ">" : " "; fg = K_YELLOW; end
            else if (cl >= 7'd2 && cl <= 7'd5)    ch = ticker_ch(mk, cl - 7'd2);
            else if (cl >= 7'd7 && cl <= 7'd14)   ch = num_char;
            else if ((cl >= 7'd16 && cl <= 7'd23) || (cl >= 7'd26 && cl <= 7'd32)) begin
                ch = num_char;
                fg = num_zero ? K_WHITE : num_neg ? K_RED : K_GREEN;
            end
            else if (cl == 7'd25)                 begin ch = up[mk] ? 8'h80 : 8'h81; fg = up[mk] ? K_GREEN : K_RED; end
            else if (cl == 7'd33)                 begin ch = "%"; fg = K_WHITE; end
            if (mk == s) bg = K_ROW;                          // the selected stock
            if ((screen_state == `UI_STOCKS) && (menu_selection == {2'b00, mk} + 4'd2)) begin
                bg = K_YELLOW; fg = K_BLACK;                  // the stock the cursor is on
            end
        end

        // ------------------------------------------------------------ YOUR PORTFOLIO (right, rows 3-8)
        else if (row >= 5'd3 && row <= 5'd8 && right) begin
            fg = K_GREY;
            case (row)
                5'd3: begin
                    if (cr <= 7'd16) ch = s16(" NET WORTH      ", cr);
                    else begin ch = num_char; fg = K_WHITE; end
                end
                5'd4: begin
                    if (cr <= 7'd16) ch = s16(" CASH           ", cr);
                    else begin ch = num_char; fg = K_WHITE; end
                end
                5'd5: begin
                    if (cr <= 7'd16) ch = s16(" PROFIT/LOSS    ", cr);
                    else begin
                        ch = num_char;
                        fg = num_zero ? K_WHITE : num_neg ? K_RED : K_GREEN;
                    end
                end
                5'd6: begin
                    if (cr <= 7'd16) ch = s16(" RETURN         ", cr);
                    else if (cr <= 7'd32) begin
                        ch = num_char;
                        fg = num_zero ? K_WHITE : num_neg ? K_RED : K_GREEN;
                    end else begin ch = "%"; fg = K_WHITE; end
                end
                5'd7: begin
                    if (cr <= 7'd16) ch = s16(" MAX DRAWDOWN   ", cr);
                    else if (cr <= 7'd32) begin
                        ch = num_char;
                        fg = num_zero ? K_WHITE : K_ORANGE;
                    end else begin ch = "%"; fg = K_WHITE; end
                end
                default: begin                                // small print
                    fg = K_DGREY;
                    ch = s64(" STARTING CASH WAS $10000.00                                    ", cr);
                end
            endcase
        end

        // ------------------------------------------------------------ LATEST TRADES (bot view, left, rows 10-19)
        else if (bv && row >= 5'd10 && row <= 5'd19 && left) begin
            if (row == 5'd10) begin                           // column names
                fg = K_GREY;
                ch = s64(" DAY BOT         SIDE STOCK  PRICE                              ", cl);
            end
            else if (row == 5'd19) begin
                fg = K_DGREY;
                ch = s64(" NEWEST AT THE TOP                                              ", cl);
            end
            else if (!f_ok) begin
                if (fe == 3'd0 && cl >= 7'd1) begin ch = s64("NO BOT TRADES YET                                               ", cl - 7'd1); fg = K_DGREY; end
            end
            else begin                                        // 045 MOMENTUM    BUY  NVDA  $451.41
                if (fe == 3'd0) bg = K_ROW;                   // the newest
                if (cl >= 7'd1 && cl <= 7'd3)        begin ch = num_char; fg = K_GREY; end
                else if (cl >= 7'd5 && cl <= 7'd15) ch = bot_name(f_bot + 3'd1) >> (8 * (7'd15 - cl));
                else if (cl >= 7'd17 && cl <= 7'd20) begin ch = s16(f_sell ? "SELL            " : "BUY             ", cl - 7'd17); fg = f_sell ? K_RED : K_GREEN; end
                else if (cl >= 7'd22 && cl <= 7'd25) begin ch = ticker_ch(f_stk, cl - 7'd22); fg = K_YELLOW; end
                else if (cl >= 7'd26 && cl <= 7'd33) ch = num_char;
            end
        end

        // ------------------------------------------------------------ chart labels (left, rows 10-19)
        else if (row >= 5'd10 && row <= 5'd19 && left) begin
            case (row)                                        // in the column right of the chart
                5'd10: if (cl >= 7'd27) ch = num_char;
                5'd11: if (cl >= 7'd30) begin ch = s16("HIGH            ", cl - 7'd30); fg = K_DGREY; end
                5'd13: if (cl >= 7'd27 && !zero[`DN_SL]) begin ch = s16("STOP            ", cl - 7'd27); fg = K_RED; end
                5'd14: if (cl >= 7'd27 && !zero[`DN_SL]) begin ch = num_char; fg = K_RED; end
                5'd15: if (cl >= 7'd27 && !zero[`DN_TP]) begin ch = s16("TARGET          ", cl - 7'd27); fg = K_GREEN; end
                5'd16: if (cl >= 7'd27 && !zero[`DN_TP]) begin ch = num_char; fg = K_GREEN; end
                5'd18: if (cl >= 7'd31) begin ch = s16("LOW             ", cl - 7'd31); fg = K_DGREY; end
                5'd19: if (cl >= 7'd27) ch = num_char;
                default: ;
            endcase
        end

        // ------------------------------------------------------------ HOLDINGS (right, rows 10-14)
        else if (row == 5'd10 && right) begin
            fg = K_GREY;
            ch = s64(" STOCK       SHARES            P/L                              ", cr);
        end
        else if (row >= 5'd11 && row <= 5'd14 && right) begin
            if (zero[`DN_POS0 + hk]) begin                        // not held: just a dash
                fg = K_DGREY;
                if (cr >= 7'd1 && cr <= 7'd4) ch = ticker_ch(hk, cr - 7'd1);
                else if (cr == 7'd18)         ch = "-";
            end else begin
                if (cr >= 7'd1 && cr <= 7'd4)        ch = ticker_ch(hk, cr - 7'd1);
                else if (cr >= 7'd13 && cr <= 7'd18) ch = num_char;
                else if (cr >= 7'd22 && cr <= 7'd33) begin
                    ch = num_char;
                    fg = num_zero ? K_WHITE : num_neg ? K_RED : K_GREEN;
                end
            end
        end

        // ------------------------------------------------------------ THE CHOSEN BOT (bot view, right, rows 17-26)
        else if (bv && row >= 5'd17 && row <= 5'd26 && right) begin
            fg = K_GREY;
            case (row)
                5'd17: begin if (cr <= 7'd16) ch = s16(" NET WORTH      ", cr); else begin ch = num_char; fg = K_WHITE; end end
                5'd18: begin if (cr <= 7'd16) ch = s16(" CASH           ", cr); else begin ch = num_char; fg = K_WHITE; end end
                5'd19: begin
                    if (cr <= 7'd16) ch = s16(" PROFIT/LOSS    ", cr);
                    else begin ch = num_char; fg = num_zero ? K_WHITE : num_neg ? K_RED : K_GREEN; end
                end
                5'd20: begin
                    if (cr <= 7'd16) ch = s16(" RETURN         ", cr);
                    else if (cr <= 7'd32) begin ch = num_char; fg = num_zero ? K_WHITE : num_neg ? K_RED : K_GREEN; end
                    else begin ch = "%"; fg = K_WHITE; end
                end
                5'd21: ;
                5'd22: ch = s64(" STOCK       SHARES            P/L                              ", cr);
                default: begin                                // rows 23-26: its holdings
                    if (zero[`DN_BPOS0 + hk]) begin
                        fg = K_DGREY;
                        if (cr >= 7'd1 && cr <= 7'd4) ch = ticker_ch(hk, cr - 7'd1);
                        else if (cr == 7'd18)         ch = "-";
                    end else begin
                        fg = K_WHITE;
                        if (cr >= 7'd1 && cr <= 7'd4)        ch = ticker_ch(hk, cr - 7'd1);
                        else if (cr >= 7'd13 && cr <= 7'd18) ch = num_char;
                        else if (cr >= 7'd22 && cr <= 7'd33) begin ch = num_char; fg = num_zero ? K_WHITE : num_neg ? K_RED : K_GREEN; end
                    end
                end
            endcase
        end

        // ------------------------------------------------------------ TRADE CONTROLS (right, rows 17-26)
        // while an order is being made: the order (values right-aligned as in YOUR PORTFOLIO),
        // the buttons for this screen, the switches, and whether it can be sent
        else if (ctl && row >= 5'd17 && row <= 5'd26 && right) begin
            fg = K_GREY;
            case (row)
                5'd17: begin                                  //  STOCK                         AMD
                    if (cr <= 7'd16) ch = s16(" STOCK          ", cr);
                    else begin ch = ticker_ch(s, cr - ((s == 2'd2) ? 7'd30 : 7'd31)); fg = K_YELLOW; end
                end
                5'd18: begin                                  //  QUANTITY                       10
                    if (cr <= 7'd16) ch = s16(" QUANTITY       ", cr);
                    else begin ch = num_char; fg = K_WHITE; end
                end
                5'd19: begin                                  //  ORDER          LIMIT  5%  BELOW
                    fg = K_WHITE;
                    if (cr <= 7'd16) begin ch = s16(" ORDER          ", cr); fg = K_GREY; end
                    else if (order_type == `OT_MKT) begin
                        if (cr >= 7'd28) ch = type_word(order_type, cr - 7'd28);
                    end
                    else if (cr >= 7'd18 && cr <= 7'd23) ch = type_word(order_type, cr - 7'd18);
                    else if (cr >= 7'd25 && cr <= 7'd27) ch = pct_word(order_dist, 1'b1, cr - 7'd25);
                    else if (cr >= 7'd29)                ch = s16(below ? "BELOW           " : "ABOVE           ", cr - 7'd29);
                end
                5'd20: begin                                  //  PRICE                     $200.68
                    if (cr <= 7'd16) ch = s16(" PRICE          ", cr);
                    else begin ch = num_char; fg = K_WHITE; end
                end
                5'd21: begin                                  //  TOTAL                    $2006.80
                    if (cr <= 7'd16) ch = s16(" TOTAL          ", cr);
                    else begin ch = num_char; fg = K_WHITE; end
                end
                5'd22: if (!trade_side) begin                 //  SL/TP                          5%   (buys only)
                    if (cr <= 7'd16)      ch = s16(" SL/TP          ", cr);
                    else if (cr >= 7'd31) begin                   // right-aligned: 2% / 5% one cell in
                        ch = pct_word(order_brk, 1'b0, cr - ((order_brk == 2'd1 || order_brk == 2'd2) ? 7'd32 : 7'd31));
                        fg = K_WHITE;
                    end
                end
                5'd23: begin                                  // the buttons: key white, what it does grey
                    if (ctl_menu) begin                       //  BTNL/BTNR   BACK   QTY   NEXT
                        if (cr <= 7'd11) begin ch = s16(" BTNL/BTNR      ", cr); fg = K_WHITE; end
                        else if (cr >= 7'd12 && cr <= 7'd17) begin
                            ch = s16(" BACK           ", cr - 7'd12);
                            fg = (menu_selection == 4'd0) ? K_BLACK : K_WHITE; bg = (menu_selection == 4'd0) ? K_YELLOW : K_DGREY;
                        end
                        else if (cr >= 7'd19 && cr <= 7'd23) begin
                            ch = s16(" QTY            ", cr - 7'd19);
                            fg = (menu_selection == 4'd1) ? K_BLACK : K_WHITE; bg = (menu_selection == 4'd1) ? K_YELLOW : K_DGREY;
                        end
                        else if (cr >= 7'd25 && cr <= 7'd30) begin
                            ch = s16(" NEXT           ", cr - 7'd25);
                            fg = (menu_selection == 4'd2) ? K_BLACK : K_WHITE; bg = (menu_selection == 4'd2) ? K_YELLOW : K_DGREY;
                        end
                    end else begin
                        ch = s64((screen_state == `UI_QUANTITY)
                                 ? " BTNU/BTND   CHANGE THE DIGIT                                   "
                                 : " BTNC        SEND THE ORDER                                     ", cr);
                        if (cr <= 7'd11) fg = K_WHITE;
                    end
                end
                5'd24: begin
                    ch = s64(ctl_menu ? " BTNC        SELECT                                             "
                           : (screen_state == `UI_QUANTITY)
                                      ? " BTNL/BTNR   MOVE TO A DIGIT                                    "
                                      : " ANY OTHER   GO BACK                                            ", cr);
                    if (cr <= 7'd11) fg = K_WHITE;
                end
                5'd25: begin                                  // the switches (not while typing the quantity)
                    if (screen_state == `UI_QUANTITY) begin
                        ch = s64(" BTNC        DONE                                               ", cr);
                        if (cr <= 7'd11) fg = K_WHITE;
                    end else begin
                        ch = s64(" SW3:2 TYPE  SW5:4 SL/TP  SW7:6 %                               ", cr);
                        fg = K_DGREY;
                    end
                end
                default: begin                                // row 26: READY TO BUY AMD, or why not
                    if (!order_valid) begin
                        if (cr >= 7'd1 && cr <= 7'd16) begin ch = reason_ch(validation_code, cr - 7'd1); fg = K_RED; end
                    end
                    else if (cr >= 7'd1 && cr <= (trade_side ? 7'd14 : 7'd13)) begin
                        ch = s16(trade_side ? "READY TO SELL   " : "READY TO BUY    ", cr - 7'd1);
                        fg = trade_side ? K_RED : K_GREEN;
                    end
                    else begin
                        ch = ticker_ch(s, cr - (trade_side ? 7'd15 : 7'd14)); fg = K_YELLOW;
                    end
                end
            endcase
        end

        // ------------------------------------------------------------ PENDING ORDERS (right, rows 17-25)
        else if (row == 5'd17 && right) begin
            fg = K_GREY;
            if (pending != 4'd0) ch = s64(" STOCK  ORDER         QTY    PRICE                              ", cr);
        end
        else if (row >= 5'd18 && row <= 5'd25 && right) begin
            if (!sl_ok) begin
                if (row == 5'd18 && cr >= 7'd1) begin ch = s64("NO PENDING ORDERS                                               ", cr - 7'd1); fg = K_DGREY; end
            end
            else if (cr >= 7'd1 && cr <= 7'd4) ch = ticker_ch(sl_stk, cr - 7'd1);
            else if (cr >= 7'd8 && cr <= 7'd18) begin        // green for a buy, red for a sell
                ch = s16(book_leg[sl] ? ((sl_typ == `OT_STP) ? "STOP-LOSS       " : "TAKE-PROFIT     ")
                                      : book_side[sl] ? ((sl_typ == `OT_LMT) ? "SELL LIMIT      " : "SELL STOP       ")
                                                      : ((sl_typ == `OT_LMT) ? "BUY LIMIT       " : "BUY STOP        "), cr - 7'd8);
                fg = book_side[sl] ? K_RED : K_GREEN;
            end
            else if (cr >= 7'd21 && cr <= 7'd24) ch = num_char;
            else if (cr >= 7'd26 && cr <= 7'd33) ch = num_char;
        end

        else if (row == 5'd26 && right && orders_view) begin  // sw14: the buttons work the list on the left OLED
            fg = K_GREY;
            ch = s64(" BTNU / BTND  CHOOSE   BTNC  CANCEL                             ", cr);
        end

        // ------------------------------------------------------------ LEADERBOARD (left, rows 21-26)
        else if (row >= 5'd21 && row <= 5'd26 && left) begin  // > 1 OVERNIGHT   $10123.45   +1.23%
            if (ent == 3'd0) bg = K_ROW;                      // your row
            if (cl == 7'd0)                       begin ch = shown ? ">" : " "; fg = K_YELLOW; end
            else if (cl == 7'd1)                  begin ch = "0" + place; fg = (place == 3'd1) ? K_YELLOW : K_GREY; end
            else if (cl >= 7'd3 && cl <= 7'd13)   begin ch = bot_name(ent) >> (8 * (7'd13 - cl)); fg = (ent == 3'd0) ? K_CYAN : K_WHITE; end
            else if (cl >= 7'd14 && cl <= 7'd24)  ch = num_char;
            else if (cl >= 7'd26 && cl <= 7'd32)  begin ch = num_char; fg = num_zero ? K_WHITE : num_neg ? K_RED : K_GREEN; end
            else if (cl == 7'd33)                 ch = "%";
        end

        // ------------------------------------------------------------ rows 28-29: the bots' latest trades
        //  NEW  DAY 045  MOMENTUM     BUYS  NVDA  AT  $451.41   RIDING THE RALLY
        else if (row >= 5'd28) begin
            bg = (row == 5'd28) ? K_NAVY : K_ROW;
            fg = K_GREY;
            if (!f_ok) begin
                if (row == 5'd28 && col >= 7'd5 && col <= 7'd68)
                    ch = s64("NO BOT TRADES YET  (THEY TRADE AT THE OPEN AND THE CLOSE)       ", col - 7'd5);
            end
            else if (col >= 7'd1 && col <= 7'd3) begin if (row == 5'd28) begin ch = s16("NEW             ", col - 7'd1); fg = K_YELLOW; end end
            else if (col >= 7'd5 && col <= 7'd7)   ch = s16("DAY             ", col - 7'd5);
            else if (col >= 7'd9 && col <= 7'd11)  begin ch = num_char; fg = K_WHITE; end
            else if (col >= 7'd14 && col <= 7'd24) begin ch = bot_name(f_bot + 3'd1) >> (8 * (7'd24 - col)); fg = K_WHITE; end
            else if (col >= 7'd26 && col <= 7'd30) begin ch = s16(f_sell ? "SELLS           " : "BUYS            ", col - 7'd26); fg = f_sell ? K_RED : K_GREEN; end
            else if (col >= 7'd32 && col <= 7'd35) begin ch = ticker_ch(f_stk, col - 7'd32); fg = K_YELLOW; end
            else if (col >= 7'd37 && col <= 7'd38) ch = s16("AT              ", col - 7'd37);
            else if (col >= 7'd39 && col <= 7'd46) begin ch = num_char; fg = K_WHITE; end
            else if (col >= 7'd49 && col <= 7'd69) begin ch = why_ch(f_bot, f_sell, col - 7'd49); fg = K_CYAN; end
        end

        // bot view: purple bars and rows, so it is clear which view this is
        if (bv) begin
            if (bg == K_PANEL || bg == K_NAVY) bg = K_PURPLE;
            else if (bg == K_ROW)              bg = K_PROW;
        end
    end
endmodule
