`timescale 1ns / 1ps
`include "trading_defs.vh"

// vga_cells: what the VGA monitor shows, cell by cell (53 columns x 30 rows of
// 12 x 16 pixel cells on a 640 x 480 screen). For the cell (row, col) it gives
// the character (ASCII, Matthew's 5x7 font drawn 2x) and two 4-bit colours
// (palette in vga_screen). The chart and the progress bar are graphics drawn by
// vga_screen in the areas this module leaves blank.
//
//   row 0       title bar, days left
//   row 1       game progress bar (graphics)
//   rows 2-7    MARKET (4 stocks: price, 30-day trend)     | YOUR PORTFOLIO (net, cash, P/L, return, drawdown)
//   rows 9-17   CHART of the selected stock (gfx)   | YOUR HOLDINGS (shares, P/L per stock)
//   rows 16-25                                      | PENDING ORDERS (the 8 book slots)
//   rows 19-25  BOT VS YOU, the bot's last trades   |
//   row 26      the order being made (or the last result)
//   row 27      NOW: what the buttons do on this screen
//   rows 28-29  the switches and what they are set to
module vga_cells (
    input  [4:0]  row,
    input  [5:0]  col,
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
    input  [3:0]  up,                  // stock k at or above its price 30 days ago
    input  [`DN_N*32-1:0] bcd,         // display_numbers
    input  [`DN_N-1:0]    neg,
    input  [7:0]  book_valid,
    input  [7:0]  book_side,
    input  [15:0] book_stock,
    input  [15:0] book_type,
    input  [7:0]  book_leg,
    input  [4:0]  log_valid,           // bot trades, newest first
    input  [4:0]  log_side,
    input  [9:0]  log_stock,
    output reg [7:0] ch,
    output reg [3:0] fg,
    output reg [3:0] bg
);
    // palette indices (colours in vga_screen)
    localparam [3:0] K_BLACK = 4'd0, K_WHITE = 4'd1, K_CYAN = 4'd2, K_YELLOW = 4'd3,
                     K_GREEN = 4'd4, K_RED = 4'd5, K_GREY = 4'd6, K_NAVY = 4'd7,
                     K_DGREY = 4'd8, K_PLUM = 4'd9, K_ORANGE = 4'd10;

    // ------------------------------------------------------------ helpers
    function [7:0] s16;                    // character c of a 16-character string
        input [127:0] s;
        input [5:0]   c;
        begin
            s16 = (c > 6'd15) ? " " : s[127 - 8*c -: 8];
        end
    endfunction

    function [7:0] s48;                    // character c of a 48-character string
        input [383:0] s;
        input [5:0]   c;
        begin
            s48 = (c > 6'd47) ? " " : s[383 - 8*c -: 8];
        end
    endfunction

    function [7:0] ticker_ch;              // AMD, MCD, NVDA, GME
        input [1:0] k;
        input [5:0] p;
        reg [31:0] t;
        begin
            case (k)
                2'd0:    t = "AMD ";
                2'd1:    t = "MCD ";
                2'd2:    t = "NVDA";
                default: t = "GME ";
            endcase
            ticker_ch = (p > 6'd3) ? " " : t[31 - 8*p -: 8];
        end
    endfunction

    // right-aligned number, w cells; dp2 = cents; prefix e.g. "$"; sgn = show +/-
    function [7:0] num_ch;
        input [31:0] d;
        input        sgn;
        input        is_neg;
        input        dp2;
        input [7:0]  prefix;
        input [5:0]  w;
        input [5:0]  p;
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

    function [31:0] field;
        input [`DN_N*32-1:0] all;
        input [5:0] f;
        begin
            field = all[32*f +: 32];
        end
    endfunction

    function [7:0] reason_ch;              // why an order is / was rejected (14 cells)
        input [2:0] code;
        input [5:0] c;
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

    function [7:0] type_word;              // MARKET / LIMIT / STOP in 6 cells
        input [1:0] t;
        input [5:0] c;
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
        input [5:0] c;
        begin
            case (v)
                2'd0:    pct_word = s16(dist ? " 1%             " : "OFF             ", c);
                2'd1:    pct_word = s16(" 2%             ", c);
                2'd2:    pct_word = s16(" 5%             ", c);
                default: pct_word = s16("10%             ", c);
            endcase
        end
    endfunction

    // ------------------------------------------------------------ numbers
    wire [1:0]  s       = selected_stock[1:0];
    wire [31:0] n_cash  = field(bcd, `DN_CASH);
    wire [31:0] n_net   = field(bcd, `DN_NET);
    wire [31:0] n_npnl  = field(bcd, `DN_NETPNL);
    wire [31:0] n_days  = field(bcd, `DN_DAYS);
    wire [31:0] n_qty   = field(bcd, `DN_QTY);
    wire [31:0] n_ordpx = field(bcd, `DN_ORDPX);
    wire [31:0] n_ordt  = field(bcd, `DN_ORDTOT);
    wire [31:0] n_ret   = field(bcd, `DN_RET);
    wire [31:0] n_maxdd = field(bcd, `DN_MAXDD);
    wire [31:0] n_bnet  = field(bcd, `DN_BNET);
    wire [31:0] n_chg   = field(bcd, `DN_CHG);
    // stock on this row: market rows 4-7, holdings rows 11-14
    wire [1:0]  mk      = row[1:0];                       // rows 4-7 -> 0-3
    wire [1:0]  hk      = row[1:0] + 2'd1;                // rows 11-14 -> 0-3
    wire [31:0] n_mpx   = field(bcd, `DN_PX0  + mk);
    wire [31:0] n_hpos  = field(bcd, `DN_POS0 + hk);
    wire [31:0] n_hpnl  = field(bcd, `DN_PNL0 + hk);
    wire        g_hpnl  = neg[`DN_PNL0 + hk];
    // order book slot on this row (rows 18-25 -> slots 0-7)
    wire [2:0]  sl      = row[2:0] - 3'd2;
    wire [1:0]  sl_stk  = book_stock[2*sl +: 2];
    wire [1:0]  sl_typ  = book_type[2*sl +: 2];
    wire [31:0] n_slq   = field(bcd, `DN_SLQ0 + sl);
    wire [31:0] n_slt   = field(bcd, `DN_SLT0 + sl);
    // bot log entry on this row (rows 23-25 -> entries 0-2)
    wire [2:0]  le      = row[2:0] - 3'd7;
    wire [31:0] n_lpx   = field(bcd, `DN_LOGPX0  + le);
    wire [31:0] n_lday  = field(bcd, `DN_LOGDAY0 + le);
    // net worth is never negative; packed BCD compares like the number it holds
    wire        you_lead = (n_net > n_bnet);
    wire        tie      = (n_net == n_bnet);
    wire [3:0]  pending  = book_valid[0] + book_valid[1] + book_valid[2] + book_valid[3]
                         + book_valid[4] + book_valid[5] + book_valid[6] + book_valid[7];

    wire in_order = (screen_state == `UI_BUY_STOCK) || (screen_state == `UI_SELL_STOCK) ||
                    (screen_state == `UI_QUANTITY)  || (screen_state == `UI_ORDER_REVIEW);
    wire [5:0] cr = col - 6'd28;                          // column inside the right panel

    always @* begin
        ch = " ";
        fg = K_WHITE;
        bg = K_BLACK;

        case (row)
            // -------------------------------------------------------- title bar
            5'd0: begin
                bg = K_NAVY;
                if (col >= 6'd1 && col <= 6'd28)
                    ch = s48("SCAM STOCK TRADING SIMULATOR                    ", col - 6'd1);
                else if (col >= 6'd39 && col <= 6'd47) begin
                    ch = s16("DAYS LEFT       ", col - 6'd39); fg = K_YELLOW;
                end else if (col >= 6'd49 && col <= 6'd51) begin
                    ch = num_ch(n_days, 1'b0, 1'b0, 1'b0, 8'd0, 6'd3, col - 6'd49);
                    fg = (n_days[31:4] == 28'd0 && n_days[3:0] <= 4'd5) ? K_RED : K_YELLOW;
                end
            end

            // -------------------------------------------------------- section titles
            5'd2: begin
                if (col >= 6'd1 && col <= 6'd6)        begin ch = s16("MARKET          ", col - 6'd1); fg = K_CYAN; end
                else if (col >= 6'd28 && col <= 6'd41) begin ch = s16("YOUR PORTFOLIO  ", cr); fg = K_CYAN; end
            end
            5'd9: begin
                if (col >= 6'd1 && col <= 6'd6)        begin ch = s16("CHART:          ", col - 6'd1); fg = K_CYAN; end
                else if (col >= 6'd8 && col <= 6'd11)  begin ch = ticker_ch(s, col - 6'd8); fg = K_WHITE; end
                else if (col >= 6'd13 && col <= 6'd24) begin ch = s16("LAST 30 DAYS    ", col - 6'd13); fg = K_GREY; end
                else if (col >= 6'd28 && col <= 6'd40) begin ch = s16("YOUR HOLDINGS   ", cr); fg = K_CYAN; end
            end
            5'd16: begin
                if (col >= 6'd28 && col <= 6'd41)      begin ch = s16("PENDING ORDERS  ", cr); fg = K_CYAN; end
                else if (col == 6'd44)                 ch = "0" + pending;
                else if (col == 6'd45)                 ch = "/";
                else if (col == 6'd46)                 ch = "8";
            end

            // -------------------------------------------------------- column headers
            5'd3: begin
                if (col >= 6'd1 && col <= 6'd5)        begin ch = s16("STOCK           ", col - 6'd1); fg = K_GREY; end
                else if (col >= 6'd10 && col <= 6'd14) begin ch = s16("PRICE           ", col - 6'd10); fg = K_GREY; end
                else if (col >= 6'd17 && col <= 6'd21) begin ch = s16("TREND           ", col - 6'd17); fg = K_GREY; end
                else if (col >= 6'd28 && col <= 6'd38) begin ch = s16("NET WORTH       ", cr); end
                else if (col >= 6'd39 && col <= 6'd51) begin ch = num_ch(n_net, 1'b0, 1'b0, 1'b1, "$", 6'd13, col - 6'd39); fg = K_YELLOW; end
            end
            5'd10: begin
                if (col >= 6'd28 && col <= 6'd32)      begin ch = s16("STOCK           ", cr); fg = K_GREY; end
                else if (col >= 6'd35 && col <= 6'd40) begin ch = s16("SHARES          ", col - 6'd35); fg = K_GREY; end
                else if (col >= 6'd45 && col <= 6'd51) begin ch = s16("    P/L         ", col - 6'd45); fg = K_GREY; end
            end
            5'd17: begin
                if (col >= 6'd28)                      begin ch = s48("#  STOCK TY S QTY  PRICE                        ", cr); fg = K_GREY; end
            end

            default: begin
                // ---------------------------------------------------- MARKET rows 4-7
                if (row >= 5'd4 && row <= 5'd7 && col <= 6'd26) begin
                    if (col == 6'd1)                       begin ch = (mk == s) ? ">" : " "; fg = K_YELLOW; end
                    else if (col >= 6'd2 && col <= 6'd5)   begin ch = ticker_ch(mk, col - 6'd2); fg = K_CYAN; end
                    else if (col >= 6'd8 && col <= 6'd14)  ch = num_ch(n_mpx, 1'b0, 1'b0, 1'b1, "$", 6'd7, col - 6'd8);
                    else if (col == 6'd17)                 begin ch = up[mk] ? 8'h80 : 8'h81; fg = up[mk] ? K_GREEN : K_RED; end
                    else if (col >= 6'd19 && col <= 6'd22) begin ch = s16(up[mk] ? "UP              " : "DOWN            ", col - 6'd19); fg = up[mk] ? K_GREEN : K_RED; end
                    if ((screen_state == `UI_STOCKS) && (menu_selection == {2'b00, mk} + 4'd2) && col >= 6'd1 && col <= 6'd24)
                        bg = K_DGREY;                      // the stock the cursor is on
                end
                // ---------------------------------------------------- YOUR PORTFOLIO rows 4-7
                if (row >= 5'd4 && row <= 5'd7 && col >= 6'd28) begin
                    case (row)
                        5'd4: begin
                            if (col <= 6'd38) ch = s16("CASH            ", cr);
                            else if (col <= 6'd51) ch = num_ch(n_cash, 1'b0, 1'b0, 1'b1, "$", 6'd13, col - 6'd39);
                        end
                        5'd5: begin
                            if (col <= 6'd38) ch = s16("PROFIT/LOSS     ", cr);
                            else if (col <= 6'd51) begin
                                ch = num_ch(n_npnl, n_npnl != 32'd0, neg[`DN_NETPNL], 1'b1, "$", 6'd13, col - 6'd39);
                                fg = (n_npnl == 32'd0) ? K_WHITE : neg[`DN_NETPNL] ? K_RED : K_GREEN;
                            end
                        end
                        5'd6: begin
                            if (col <= 6'd38) ch = s16("RETURN          ", cr);
                            else if (col <= 6'd50) begin
                                ch = num_ch(n_ret, n_ret != 32'd0, neg[`DN_RET], 1'b1, 8'd0, 6'd12, col - 6'd39);
                                fg = (n_ret == 32'd0) ? K_WHITE : neg[`DN_RET] ? K_RED : K_GREEN;
                            end else if (col == 6'd51) ch = "%";
                        end
                        default: begin
                            if (col <= 6'd38) ch = s16("MAX DRAWDOWN    ", cr);
                            else if (col <= 6'd50) begin
                                ch = num_ch(n_maxdd, 1'b0, 1'b0, 1'b1, 8'd0, 6'd12, col - 6'd39);
                                fg = (n_maxdd == 32'd0) ? K_WHITE : K_ORANGE;
                            end else if (col == 6'd51) ch = "%";
                        end
                    endcase
                end
                // ---------------------------------------------------- YOUR HOLDINGS rows 11-14
                if (row >= 5'd11 && row <= 5'd14 && col >= 6'd28) begin
                    if (col <= 6'd31)                      begin ch = ticker_ch(hk, cr); fg = (n_hpos == 32'd0) ? K_GREY : K_CYAN; end
                    else if (col >= 6'd35 && col <= 6'd40) begin ch = num_ch(n_hpos, 1'b0, 1'b0, 1'b0, 8'd0, 6'd6, col - 6'd35); fg = (n_hpos == 32'd0) ? K_GREY : K_WHITE; end
                    else if (col >= 6'd41 && col <= 6'd51) begin
                        ch = num_ch(n_hpnl, n_hpnl != 32'd0, g_hpnl, 1'b1, "$", 6'd11, col - 6'd41);
                        fg = (n_hpnl == 32'd0) ? K_GREY : g_hpnl ? K_RED : K_GREEN;
                    end
                end
                // ---------------------------------------------------- PENDING ORDERS rows 18-25
                if (row >= 5'd18 && row <= 5'd25 && col >= 6'd28) begin
                    if (col == 6'd28) begin ch = "1" + sl; fg = K_GREY; end
                    else if (!book_valid[sl]) begin
                        if (col == 6'd31) begin ch = "-"; fg = K_GREY; end
                    end else if (col >= 6'd31 && col <= 6'd34) begin ch = ticker_ch(sl_stk, col - 6'd31); fg = K_CYAN; end
                    else if (col >= 6'd36 && col <= 6'd37) begin
                        ch = s16(book_leg[sl] ? ((sl_typ == `OT_STP) ? "SL              " : "TP              ")
                                              : ((sl_typ == `OT_LMT) ? "LM              " : "ST              "), col - 6'd36);
                        fg = book_leg[sl] ? ((sl_typ == `OT_STP) ? K_RED : K_GREEN) : K_WHITE;
                    end
                    else if (col == 6'd39) begin ch = book_side[sl] ? "S" : "B"; fg = book_side[sl] ? K_RED : K_GREEN; end
                    else if (col >= 6'd41 && col <= 6'd43) ch = num_ch(n_slq, 1'b0, 1'b0, 1'b0, 8'd0, 6'd3, col - 6'd41);
                    else if (col >= 6'd45 && col <= 6'd52) ch = num_ch(n_slt, 1'b0, 1'b0, 1'b1, "$", 6'd8, col - 6'd45);
                end
                // ---------------------------------------------------- BOT VS YOU rows 19-25
                if (row >= 5'd19 && row <= 5'd25 && col <= 6'd26) begin
                    case (row)
                        5'd19: begin
                            if (col >= 6'd1 && col <= 6'd10)       begin ch = s16("BOT VS YOU      ", col - 6'd1); fg = K_CYAN; end
                        end
                        5'd20: begin
                            if (col >= 6'd1 && col <= 6'd3)        begin ch = s16("YOU             ", col - 6'd1); fg = K_CYAN; end
                            else if (col >= 6'd6 && col <= 6'd18)  begin ch = num_ch(n_net, 1'b0, 1'b0, 1'b1, "$", 6'd13, col - 6'd6); fg = neg[`DN_NETPNL] ? K_RED : K_GREEN; end
                        end
                        5'd21: begin
                            if (col >= 6'd1 && col <= 6'd3)        begin ch = s16("BOT             ", col - 6'd1); fg = K_CYAN; end
                            else if (col >= 6'd6 && col <= 6'd18)  begin ch = num_ch(n_bnet, 1'b0, 1'b0, 1'b1, "$", 6'd13, col - 6'd6); fg = neg[`DN_BNETPNL] ? K_RED : K_GREEN; end
                        end
                        5'd22: begin
                            if (col >= 6'd1 && col <= 6'd8)        begin ch = s16("LEADING:        ", col - 6'd1); fg = K_GREY; end
                            else if (col >= 6'd10 && col <= 6'd12) begin
                                ch = s16(tie ? "TIE             " : you_lead ? "YOU             " : "BOT             ", col - 6'd10);
                                fg = tie ? K_WHITE : you_lead ? K_GREEN : K_ORANGE;
                            end
                        end
                        5'd23, 5'd24, 5'd25: begin                  // bot's last 3 trades
                            if (!log_valid[le]) begin
                                if (row == 5'd23 && col >= 6'd1 && col <= 6'd15) begin ch = s16("BOT: NO TRADES  ", col - 6'd1); fg = K_GREY; end
                            end else if (col >= 6'd1 && col <= 6'd3)   begin ch = s16("DAY             ", col - 6'd1); fg = K_GREY; end
                            else if (col >= 6'd5 && col <= 6'd7)   begin ch = num_ch(n_lday, 1'b0, 1'b0, 1'b0, 8'd0, 6'd3, col - 6'd5); fg = K_GREY; end
                            else if (col >= 6'd9 && col <= 6'd12)  begin ch = s16(log_side[le] ? "SELL            " : "BUY             ", col - 6'd9); fg = log_side[le] ? K_RED : K_GREEN; end
                            else if (col >= 6'd14 && col <= 6'd17) begin ch = ticker_ch(log_stock[2*le +: 2], col - 6'd14); fg = K_CYAN; end
                            else if (col >= 6'd19 && col <= 6'd26) ch = num_ch(n_lpx, 1'b0, 1'b0, 1'b1, "$", 6'd8, col - 6'd19);
                        end
                        default: ;
                    endcase
                end
                // ---------------------------------------------------- row 26: the order / last result
                if (row == 5'd26) begin
                    bg = K_DGREY;
                    if (in_order) begin                     // ORDER: BUY   12 MCD  LIMIT  $297.04  TOTAL $3625.00
                        if (col >= 6'd1 && col <= 6'd6)        begin ch = s16("ORDER:          ", col - 6'd1); fg = K_CYAN; end
                        else if (col >= 6'd8 && col <= 6'd11)  begin ch = s16(trade_side ? "SELL            " : "BUY             ", col - 6'd8); fg = trade_side ? K_RED : K_GREEN; end
                        else if (col >= 6'd13 && col <= 6'd16) ch = num_ch(n_qty, 1'b0, 1'b0, 1'b0, 8'd0, 6'd4, col - 6'd13);
                        else if (col >= 6'd18 && col <= 6'd21) begin ch = ticker_ch(s, col - 6'd18); fg = K_CYAN; end
                        else if (col >= 6'd23 && col <= 6'd28) ch = type_word(order_type, col - 6'd23);
                        else if (col >= 6'd30 && col <= 6'd37) ch = num_ch(n_ordpx, 1'b0, 1'b0, 1'b1, "$", 6'd8, col - 6'd30);
                        else if (!order_valid && col >= 6'd39 && col <= 6'd52) begin ch = reason_ch(validation_code, col - 6'd39); fg = K_RED; end
                        else if (col >= 6'd39 && col <= 6'd43) begin ch = s16("TOTAL           ", col - 6'd39); fg = K_GREY; end
                        else if (col >= 6'd44 && col <= 6'd52) begin ch = num_ch(n_ordt, 1'b0, 1'b0, 1'b1, "$", 6'd9, col - 6'd44); fg = K_YELLOW; end
                    end else if (screen_state == `UI_TRADE_RESULT) begin
                        if (col >= 6'd1 && col <= 6'd11)       begin ch = s16("LAST ORDER:     ", col - 6'd1); fg = K_CYAN; end
                        else if (col >= 6'd13 && col <= 6'd20) begin
                            ch = s16(!trade_result_success ? "REJECTED        " : trade_result_placed ? "PLACED          " : "FILLED          ", col - 6'd13);
                            fg = !trade_result_success ? K_RED : trade_result_placed ? K_CYAN : K_GREEN;
                        end
                        else if (!trade_result_success && col >= 6'd22 && col <= 6'd37) begin ch = reason_ch(trade_result_code, col - 6'd22); fg = K_RED; end
                    end
                end
                // ---------------------------------------------------- row 27: what to press now
                if (row == 5'd27) begin
                    if (col >= 6'd1 && col <= 6'd4) begin ch = s16("NOW:            ", col - 6'd1); fg = K_YELLOW; end
                    else if (col >= 6'd6) begin
                        case (screen_state)
                            `UI_TITLE:        ch = s48("PRESS C TO START THE GAME                       ", col - 6'd6);
                            `UI_PORTFOLIO:    ch = s48("L/R PICK HOME OR MARKET   C OPEN IT             ", col - 6'd6);
                            `UI_STOCKS:       ch = s48("U/D PICK A STOCK   C OPEN IT   L/R TABS         ", col - 6'd6);
                            `UI_SPECIFIC:     ch = s48("L/R PICK BUY, SELL OR BACK   C SELECT   U TABS  ", col - 6'd6);
                            `UI_BUY_STOCK,
                            `UI_SELL_STOCK:   ch = s48("L/R PICK BACK, QTY OR NEXT   C SELECT           ", col - 6'd6);
                            `UI_QUANTITY:     ch = s48("U/D CHANGE THE DIGIT   L/R MOVE   C DONE        ", col - 6'd6);
                            `UI_ORDER_REVIEW: ch = s48("C SEND THE ORDER                                ", col - 6'd6);
                            `UI_ORDER_RESULT: ch = s48("SENDING THE ORDER...                            ", col - 6'd6);
                            `UI_TRADE_RESULT: ch = s48("C CONTINUE                                      ", col - 6'd6);
                            `UI_GAME_END:     ch = s48("GAME OVER   SW0 UP THEN DOWN FOR A NEW GAME     ", col - 6'd6);
                            default: ;
                        endcase
                    end
                end
                // ---------------------------------------------------- rows 28-29: the switches
                if (row == 5'd28) begin                     // SW3:2 TYPE MARKET  SW5:4 SL/TP  5%  SW7:6 DIST  2%
                    if (col >= 6'd1 && col <= 6'd5)        begin ch = s16("SW3:2           ", col - 6'd1); fg = K_GREY; end
                    else if (col >= 6'd7 && col <= 6'd10)  ch = s16("TYPE            ", col - 6'd7);
                    else if (col >= 6'd12 && col <= 6'd17) begin ch = type_word(order_type, col - 6'd12); fg = K_YELLOW; end
                    else if (col >= 6'd20 && col <= 6'd24) begin ch = s16("SW5:4           ", col - 6'd20); fg = K_GREY; end
                    else if (col >= 6'd26 && col <= 6'd30) ch = s16("SL/TP           ", col - 6'd26);
                    else if (col >= 6'd32 && col <= 6'd34) begin ch = pct_word(order_brk, 1'b0, col - 6'd32); fg = K_YELLOW; end
                    else if (col >= 6'd37 && col <= 6'd41) begin ch = s16("SW7:6           ", col - 6'd37); fg = K_GREY; end
                    else if (col >= 6'd43 && col <= 6'd46) ch = s16("DIST            ", col - 6'd43);
                    else if (col >= 6'd48 && col <= 6'd50) begin ch = pct_word(order_dist, 1'b1, col - 6'd48); fg = K_YELLOW; end
                end
                if (row == 5'd29) begin                     // SW0 RESET   SW15 OLED VIEW: YOU   BUTTONS U D L R C
                    if (col >= 6'd1 && col <= 6'd3)        begin ch = s16("SW0             ", col - 6'd1); fg = K_GREY; end
                    else if (col >= 6'd5 && col <= 6'd9)   ch = s16("RESET           ", col - 6'd5);
                    else if (col >= 6'd13 && col <= 6'd16) begin ch = s16("SW15            ", col - 6'd13); fg = K_GREY; end
                    else if (col >= 6'd18 && col <= 6'd27) ch = s16("OLED VIEW:      ", col - 6'd18);
                    else if (col >= 6'd29 && col <= 6'd31) begin ch = s16(oled_bot_view ? "BOT             " : "YOU             ", col - 6'd29); fg = K_YELLOW; end
                    else if (col >= 6'd35 && col <= 6'd41) begin ch = s16("BUTTONS         ", col - 6'd35); fg = K_GREY; end
                    else if (col >= 6'd43 && col <= 6'd51) ch = s16("U D L R C       ", col - 6'd43);
                end
            end
        endcase
    end
endmodule
