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
//   rows 2-7    MARKET: price, 30-day change, trend | YOUR PORTFOLIO
//   rows 9-20   <stock> LAST 30 DAYS: chart with    | HOLDINGS (rows 9-14)
//               high / low prices, SL / TP levels   | PENDING ORDERS (rows 16-25)
//   rows 21-26  YOU VS BOT, recent bot trades       |
//   row 27      the order being made, or the last result
//   row 28      NOW: which buttons to press on this screen (highlighted bar)
//   row 29      the switches and what they are set to
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
                     K_DGREY = 4'd8, K_PLUM = 4'd9, K_ORANGE = 4'd10, K_PANEL = 4'd11,
                     K_ROW = 4'd12;

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

    function [31:0] field;
        input [`DN_N*32-1:0] all;
        input [6:0] f;
        begin
            field = all[32*f +: 32];
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
    wire [31:0] n_bret  = field(bcd, `DN_BRET);
    wire [31:0] n_chi   = field(bcd, `DN_CHI);
    wire [31:0] n_clo   = field(bcd, `DN_CLO);
    wire [31:0] n_sl    = field(bcd, `DN_SL);
    wire [31:0] n_tp    = field(bcd, `DN_TP);
    // market rows 4-7 -> stocks 0-3; holdings rows 11-14 -> stocks 0-3
    wire [1:0]  mk      = row[1:0];
    wire [1:0]  hk      = row[1:0] + 2'd1;
    wire [31:0] n_mpx   = field(bcd, `DN_PX0  + mk);
    wire [31:0] n_mchg  = field(bcd, `DN_CHG0 + mk);
    wire        g_mchg  = neg[`DN_CHG0 + mk];
    wire [31:0] n_hpos  = field(bcd, `DN_POS0 + hk);
    wire [31:0] n_hpnl  = field(bcd, `DN_PNL0 + hk);
    wire        g_hpnl  = neg[`DN_PNL0 + hk];

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
    wire [31:0] n_slq   = field(bcd, `DN_SLQ0 + sl);
    wire [31:0] n_slt   = field(bcd, `DN_SLT0 + sl);
    wire [3:0]  pending = book_valid[0] + book_valid[1] + book_valid[2] + book_valid[3]
                        + book_valid[4] + book_valid[5] + book_valid[6] + book_valid[7];

    // bot trades on rows 25-26 (newest first)
    wire [2:0]  le      = row[2:0] - 3'd1;
    wire [31:0] n_lpx   = field(bcd, `DN_LOGPX0  + le);
    wire [31:0] n_lday  = field(bcd, `DN_LOGDAY0 + le);
    // you (row 22) and the bot (row 23)
    wire        is_bot  = row[0];
    wire [31:0] n_vnet  = is_bot ? n_bnet : n_net;
    wire [31:0] n_vret  = is_bot ? n_bret : n_ret;
    wire        g_vret  = is_bot ? neg[`DN_BRET] : neg[`DN_RET];
    // net worth is never negative; packed BCD compares like the number it holds
    wire        you_lead = (n_net > n_bnet);
    wire        tie      = (n_net == n_bnet);

    wire in_order = (screen_state == `UI_BUY_STOCK) || (screen_state == `UI_SELL_STOCK) ||
                    (screen_state == `UI_QUANTITY)  || (screen_state == `UI_ORDER_REVIEW);
    // a limit buy / stop sell waits below the price, a limit sell / stop buy above it
    wire below = ((order_type == `OT_LMT) && !trade_side) || ((order_type == `OT_STP) && trade_side);
    wire left  = (col >= 7'd1)  && (col <= 7'd34);
    wire right = (col >= 7'd36) && (col <= 7'd69);
    wire [6:0] cl = col - 7'd1;                           // column inside the left panel, 0..33
    wire [6:0] cr = col - 7'd36;                          // column inside the right panel, 0..33

    always @* begin
        ch = " ";
        fg = K_WHITE;
        bg = K_BLACK;

        // ------------------------------------------------------------ title bar
        if (row == 5'd0) begin
            bg = K_NAVY;
            if (col >= 7'd1 && col <= 7'd28)       ch = s64("SCAM STOCK TRADING SIMULATOR                                    ", cl);
            else if (col >= 7'd57 && col <= 7'd65) begin ch = s16("DAYS LEFT       ", col - 7'd57); fg = K_GREY; end
            else if (col >= 7'd67 && col <= 7'd69) begin
                ch = num_ch(n_days, 1'b0, 1'b0, 1'b0, 8'd0, 7'd3, col - 7'd67);
                fg = (n_days[31:4] == 28'd0 && n_days[3:0] <= 4'd5) ? K_RED : K_YELLOW;
            end
        end

        // ------------------------------------------------------------ panel header bars
        else if ((row == 5'd2 || row == 5'd9 || row == 5'd21) && left) begin
            bg = K_PANEL;
            case (row)
                5'd2: ch = s16(" MARKET         ", cl);
                5'd9: begin                                   //  MCD  LAST 30 DAYS
                    if (cl >= 7'd1 && cl <= 7'd4) begin ch = ticker_ch(s, cl - 7'd1); fg = K_YELLOW; end
                    else if (cl >= 7'd6)            ch = s16("LAST 30 DAYS    ", cl - 7'd6);
                end
                default: ch = s16(" YOU VS BOT     ", cl);
            endcase
        end
        else if ((row == 5'd2 || row == 5'd9 || row == 5'd16) && right) begin
            bg = K_PANEL;
            case (row)
                5'd2: ch = s16(" YOUR PORTFOLIO ", cr);
                5'd9: ch = s16(" HOLDINGS       ", cr);
                default: begin                                //  PENDING ORDERS          2 OF 8
                    if (cr <= 7'd15)                     ch = s16(" PENDING ORDERS ", cr);
                    else if (cr == 7'd28)                begin ch = "0" + pending; fg = (pending == 4'd8) ? K_YELLOW : K_WHITE; end
                    else if (cr >= 7'd30 && cr <= 7'd33) ch = s16("OF 8            ", cr - 7'd30);
                end
            endcase
        end

        // ------------------------------------------------------------ MARKET (left, rows 3-7)
        else if (row == 5'd3 && left) begin                  // column names
            fg = K_GREY;
            ch = s64("  STOCK    PRICE    30 DAYS TREND                               ", cl);
        end
        else if (row >= 5'd4 && row <= 5'd7 && left) begin   // > AMD   $207.02   -$12.34  v DOWN
            if (cl == 7'd0)                       begin ch = (mk == s) ? ">" : " "; fg = K_YELLOW; end
            else if (cl >= 7'd2 && cl <= 7'd5)    ch = ticker_ch(mk, cl - 7'd2);
            else if (cl >= 7'd7 && cl <= 7'd15)   ch = num_ch(n_mpx, 1'b0, 1'b0, 1'b1, "$", 7'd9, cl - 7'd7);
            else if (cl >= 7'd17 && cl <= 7'd26) begin
                ch = num_ch(n_mchg, n_mchg != 32'd0, g_mchg, 1'b1, "$", 7'd10, cl - 7'd17);
                fg = (n_mchg == 32'd0) ? K_WHITE : g_mchg ? K_RED : K_GREEN;
            end
            else if (cl == 7'd28)                 begin ch = up[mk] ? 8'h80 : 8'h81; fg = up[mk] ? K_GREEN : K_RED; end
            else if (cl >= 7'd30 && cl <= 7'd33)  begin ch = s16(up[mk] ? "UP              " : "DOWN            ", cl - 7'd30); fg = up[mk] ? K_GREEN : K_RED; end
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
                    else begin ch = num_ch(n_net, 1'b0, 1'b0, 1'b1, "$", 7'd17, cr - 7'd17); fg = K_WHITE; end
                end
                5'd4: begin
                    if (cr <= 7'd16) ch = s16(" CASH           ", cr);
                    else begin ch = num_ch(n_cash, 1'b0, 1'b0, 1'b1, "$", 7'd17, cr - 7'd17); fg = K_WHITE; end
                end
                5'd5: begin
                    if (cr <= 7'd16) ch = s16(" PROFIT/LOSS    ", cr);
                    else begin
                        ch = num_ch(n_npnl, n_npnl != 32'd0, neg[`DN_NETPNL], 1'b1, "$", 7'd17, cr - 7'd17);
                        fg = (n_npnl == 32'd0) ? K_WHITE : neg[`DN_NETPNL] ? K_RED : K_GREEN;
                    end
                end
                5'd6: begin
                    if (cr <= 7'd16) ch = s16(" RETURN         ", cr);
                    else if (cr <= 7'd32) begin
                        ch = num_ch(n_ret, n_ret != 32'd0, neg[`DN_RET], 1'b1, 8'd0, 7'd16, cr - 7'd17);
                        fg = (n_ret == 32'd0) ? K_WHITE : neg[`DN_RET] ? K_RED : K_GREEN;
                    end else begin ch = "%"; fg = K_WHITE; end
                end
                5'd7: begin
                    if (cr <= 7'd16) ch = s16(" MAX DRAWDOWN   ", cr);
                    else if (cr <= 7'd32) begin
                        ch = num_ch(n_maxdd, 1'b0, 1'b0, 1'b1, 8'd0, 7'd16, cr - 7'd17);
                        fg = (n_maxdd == 32'd0) ? K_WHITE : K_ORANGE;
                    end else begin ch = "%"; fg = K_WHITE; end
                end
                default: begin                                // small print
                    fg = K_DGREY;
                    ch = s64(" STARTING CASH WAS $10000.00                                    ", cr);
                end
            endcase
        end

        // ------------------------------------------------------------ chart labels (left, rows 10-20)
        else if (row >= 5'd10 && row <= 5'd20 && left) begin
            case (row)
                5'd10: if (cl >= 7'd27) ch = num_ch(n_chi, 1'b0, 1'b0, 1'b1, "$", 7'd7, cl - 7'd27);
                5'd11: if (cl >= 7'd30) begin ch = s16("HIGH            ", cl - 7'd30); fg = K_DGREY; end
                5'd18: if (cl >= 7'd31) begin ch = s16("LOW             ", cl - 7'd31); fg = K_DGREY; end
                5'd19: if (cl >= 7'd27) ch = num_ch(n_clo, 1'b0, 1'b0, 1'b1, "$", 7'd7, cl - 7'd27);
                5'd20: begin                                  //  -- SL  $196.71     -- TP  $217.43   (only when set)
                    if (n_sl != 32'd0 && cl <= 7'd12) begin
                        if (cl <= 7'd1)       begin ch = "-"; fg = K_RED; end
                        else if (cl <= 7'd4)  begin ch = s16(" SL             ", cl - 7'd2); fg = K_GREY; end
                        else                  ch = num_ch(n_sl, 1'b0, 1'b0, 1'b1, "$", 7'd8, cl - 7'd5);
                    end
                    else if (n_tp != 32'd0 && cl >= 7'd16 && cl <= 7'd28) begin
                        if (cl <= 7'd17)      begin ch = "-"; fg = K_GREEN; end
                        else if (cl <= 7'd20) begin ch = s16(" TP             ", cl - 7'd18); fg = K_GREY; end
                        else                  ch = num_ch(n_tp, 1'b0, 1'b0, 1'b1, "$", 7'd8, cl - 7'd21);
                    end
                end
                default: ;
            endcase
        end

        // ------------------------------------------------------------ HOLDINGS (right, rows 10-14)
        else if (row == 5'd10 && right) begin
            fg = K_GREY;
            ch = s64(" STOCK       SHARES            P/L                              ", cr);
        end
        else if (row >= 5'd11 && row <= 5'd14 && right) begin
            if (n_hpos == 32'd0) begin                        // not held: just a dash
                fg = K_DGREY;
                if (cr >= 7'd1 && cr <= 7'd4) ch = ticker_ch(hk, cr - 7'd1);
                else if (cr == 7'd18)         ch = "-";
            end else begin
                if (cr >= 7'd1 && cr <= 7'd4)        ch = ticker_ch(hk, cr - 7'd1);
                else if (cr >= 7'd13 && cr <= 7'd18) ch = num_ch(n_hpos, 1'b0, 1'b0, 1'b0, 8'd0, 7'd6, cr - 7'd13);
                else if (cr >= 7'd22 && cr <= 7'd33) begin
                    ch = num_ch(n_hpnl, n_hpnl != 32'd0, g_hpnl, 1'b1, "$", 7'd12, cr - 7'd22);
                    fg = (n_hpnl == 32'd0) ? K_WHITE : g_hpnl ? K_RED : K_GREEN;
                end
            end
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
            else if (cr >= 7'd21 && cr <= 7'd24) ch = num_ch(n_slq, 1'b0, 1'b0, 1'b0, 8'd0, 7'd4, cr - 7'd21);
            else if (cr >= 7'd26 && cr <= 7'd33) ch = num_ch(n_slt, 1'b0, 1'b0, 1'b1, "$", 7'd8, cr - 7'd26);
        end

        // ------------------------------------------------------------ YOU VS BOT (left, rows 22-26)
        else if (row >= 5'd22 && row <= 5'd26 && left) begin
            case (row)
                5'd22, 5'd23: begin                           //  YOU   $9967.85   -0.32%    LEAD
                    if (cl >= 7'd1 && cl <= 7'd3)        begin ch = s16(is_bot ? "BOT             " : "YOU             ", cl - 7'd1); fg = K_GREY; end
                    else if (cl >= 7'd5 && cl <= 7'd16)  ch = num_ch(n_vnet, 1'b0, 1'b0, 1'b1, "$", 7'd12, cl - 7'd5);
                    else if (cl >= 7'd18 && cl <= 7'd25) begin
                        ch = num_ch(n_vret, n_vret != 32'd0, g_vret, 1'b1, 8'd0, 7'd8, cl - 7'd18);
                        fg = (n_vret == 32'd0) ? K_WHITE : g_vret ? K_RED : K_GREEN;
                    end
                    else if (cl == 7'd26)                ch = "%";
                    else if (cl >= 7'd29 && cl <= 7'd32 && !tie && (is_bot ? !you_lead : you_lead)) begin
                        ch = s16("LEAD            ", cl - 7'd29); fg = K_YELLOW;
                    end
                end
                5'd24: if (cl >= 7'd1) begin ch = s64("RECENT BOT TRADES                                               ", cl - 7'd1); fg = K_DGREY; end
                default: begin                                // DAY  40   SELL  GME   AT  $33.80
                    if (!log_valid[le]) begin
                        if (row == 5'd25 && cl >= 7'd1) begin ch = s64("THE BOT HAS NOT TRADED YET                                      ", cl - 7'd1); fg = K_GREY; end
                    end
                    else if (cl >= 7'd1 && cl <= 7'd3)   begin ch = s16("DAY             ", cl - 7'd1); fg = K_GREY; end
                    else if (cl >= 7'd5 && cl <= 7'd7)   begin ch = num_ch(n_lday, 1'b0, 1'b0, 1'b0, 8'd0, 7'd3, cl - 7'd5); fg = K_GREY; end
                    else if (cl >= 7'd10 && cl <= 7'd13) begin ch = s16(log_side[le] ? "SELL            " : "BUY             ", cl - 7'd10); fg = log_side[le] ? K_RED : K_GREEN; end
                    else if (cl >= 7'd15 && cl <= 7'd18) ch = ticker_ch(log_stock[2*le +: 2], cl - 7'd15);
                    else if (cl >= 7'd21 && cl <= 7'd22) begin ch = s16("AT              ", cl - 7'd21); fg = K_GREY; end
                    else if (cl >= 7'd24 && cl <= 7'd31) ch = num_ch(n_lpx, 1'b0, 1'b0, 1'b1, "$", 7'd8, cl - 7'd24);
                end
            endcase
        end

        // ------------------------------------------------------------ row 27: the order, or the last result
        else if (row == 5'd27) begin
            if (in_order) begin             //  BUY  3 MCD  LIMIT  AT  $297.04  5% BELOW     TOTAL  $892.12
                bg = K_ROW;
                if (col >= 7'd1 && col <= 7'd4)        begin ch = s16(trade_side ? "SELL            " : "BUY             ", col - 7'd1); fg = trade_side ? K_RED : K_GREEN; end
                else if (col >= 7'd6 && col <= 7'd9)   ch = num_ch(n_qty, 1'b0, 1'b0, 1'b0, 8'd0, 7'd4, col - 7'd6);
                else if (col >= 7'd11 && col <= 7'd14) ch = ticker_ch(s, col - 7'd11);
                else if (col >= 7'd16 && col <= 7'd21) begin ch = type_word(order_type, col - 7'd16); fg = K_GREY; end
                else if (col >= 7'd23 && col <= 7'd24) begin ch = s16("AT              ", col - 7'd23); fg = K_GREY; end
                else if (col >= 7'd26 && col <= 7'd34) ch = num_ch(n_ordpx, 1'b0, 1'b0, 1'b1, "$", 7'd9, col - 7'd26);
                else if (col >= 7'd36 && col <= 7'd38 && order_type != `OT_MKT) begin ch = pct_word(order_dist, 1'b1, col - 7'd36); fg = K_GREY; end
                else if (col >= 7'd40 && col <= 7'd44 && order_type != `OT_MKT) begin ch = s16(below ? "BELOW           " : "ABOVE           ", col - 7'd40); fg = K_GREY; end
                else if (!order_valid) begin
                    if (col >= 7'd48 && col <= 7'd63) begin ch = reason_ch(validation_code, col - 7'd48); fg = K_RED; end
                end
                else if (col >= 7'd48 && col <= 7'd52) begin ch = s16("TOTAL           ", col - 7'd48); fg = K_GREY; end
                else if (col >= 7'd54 && col <= 7'd65) ch = num_ch(n_ordt, 1'b0, 1'b0, 1'b1, "$", 7'd12, col - 7'd54);
            end else if (screen_state == `UI_TRADE_RESULT) begin  //  LAST ORDER  FILLED / PLACED / REJECTED  reason
                bg = K_ROW;
                if (col >= 7'd1 && col <= 7'd10)       begin ch = s16("LAST ORDER      ", col - 7'd1); fg = K_GREY; end
                else if (col >= 7'd12 && col <= 7'd19) begin
                    ch = s16(!trade_result_success ? "REJECTED        " : trade_result_placed ? "PLACED          " : "FILLED          ", col - 7'd12);
                    fg = !trade_result_success ? K_RED : trade_result_placed ? K_CYAN : K_GREEN;
                end
                else if (!trade_result_success && col >= 7'd21 && col <= 7'd36) ch = reason_ch(trade_result_code, col - 7'd21);
                else if (trade_result_success && trade_result_placed && col >= 7'd21 && col <= 7'd69)
                    begin ch = s64("NOW WAITING IN PENDING ORDERS FOR ITS PRICE                     ", col - 7'd21); fg = K_GREY; end
            end
        end

        // ------------------------------------------------------------ row 28: NOW (highlighted bar)
        else if (row == 5'd28) begin
            bg = K_NAVY;
            if (col >= 7'd1 && col <= 7'd3) begin ch = s16("NOW             ", col - 7'd1); fg = K_YELLOW; end
            else if (col >= 7'd5 && col <= 7'd69) begin
                case (screen_state)
                    `UI_TITLE:        ch = s64("PRESS BTNC TO START                                             ", col - 7'd5);
                    `UI_PORTFOLIO:    ch = s64("BTNL / BTNR  CHOOSE HOME OR MARKET          BTNC  OPEN          ", col - 7'd5);
                    `UI_STOCKS:       ch = s64("BTNU / BTND  CHOOSE A STOCK                 BTNC  OPEN IT       ", col - 7'd5);
                    `UI_SPECIFIC:     ch = s64("BTNL / BTNR  CHOOSE BUY, SELL OR BACK       BTNC  SELECT        ", col - 7'd5);
                    `UI_BUY_STOCK,
                    `UI_SELL_STOCK:   ch = s64("BTNL / BTNR  CHOOSE BACK, QTY OR NEXT       BTNC  SELECT        ", col - 7'd5);
                    `UI_QUANTITY:     ch = s64("BTNU / BTND  CHANGE DIGIT    BTNL / BTNR  MOVE    BTNC  DONE    ", col - 7'd5);
                    `UI_ORDER_REVIEW: ch = s64("CHECK THE ORDER ABOVE                       BTNC  SEND IT       ", col - 7'd5);
                    `UI_ORDER_RESULT: ch = s64("SENDING THE ORDER...                                            ", col - 7'd5);
                    `UI_TRADE_RESULT: ch = s64("BTNC  CONTINUE                                                  ", col - 7'd5);
                    `UI_GAME_END:     ch = s64("GAME OVER        SW0 UP THEN DOWN  START A NEW GAME             ", col - 7'd5);
                    default: ;
                endcase
            end
        end

        // ------------------------------------------------------------ row 29: the switches
        else if (row == 5'd29) begin    // SW3:2 TYPE MARKET   SW5:4 SL/TP OFF   SW7:6 DISTANCE 5%   SW15 OLED YOU
            fg = K_GREY;
            if (col >= 7'd1 && col <= 7'd5)        begin ch = s16("SW3:2           ", col - 7'd1); fg = K_DGREY; end
            else if (col >= 7'd7 && col <= 7'd10)  ch = s16("TYPE            ", col - 7'd7);
            else if (col >= 7'd12 && col <= 7'd17) begin ch = type_word(order_type, col - 7'd12); fg = K_WHITE; end
            else if (col >= 7'd20 && col <= 7'd24) begin ch = s16("SW5:4           ", col - 7'd20); fg = K_DGREY; end
            else if (col >= 7'd26 && col <= 7'd30) ch = s16("SL/TP           ", col - 7'd26);
            else if (col >= 7'd32 && col <= 7'd34) begin ch = pct_word(order_brk, 1'b0, col - 7'd32); fg = K_WHITE; end
            else if (col >= 7'd37 && col <= 7'd41) begin ch = s16("SW7:6           ", col - 7'd37); fg = K_DGREY; end
            else if (col >= 7'd43 && col <= 7'd50) ch = s16("DISTANCE        ", col - 7'd43);
            else if (col >= 7'd52 && col <= 7'd54) begin ch = pct_word(order_dist, 1'b1, col - 7'd52); fg = K_WHITE; end
            else if (col >= 7'd57 && col <= 7'd60) begin ch = s16("SW15            ", col - 7'd57); fg = K_DGREY; end
            else if (col >= 7'd62 && col <= 7'd65) ch = s16("OLED            ", col - 7'd62);
            else if (col >= 7'd67 && col <= 7'd69) begin ch = s16(oled_bot_view ? "BOT             " : "YOU             ", col - 7'd67); fg = K_WHITE; end
        end
    end
endmodule
