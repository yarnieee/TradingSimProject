`timescale 1ns / 1ps
`include "trading_defs.vh"

// text_layer: what every right-OLED screen shows, cell by cell, on the
// text_grid layout (header row 0, body rows 1-6 of 16 cells; or a big row 1).
//
// For the cell (row, col) it gives the character and its colours. Buttons are
// runs of cells with a background: the selected one is black on yellow, the
// others white on dark grey. The three-button bar on row 6 always uses
// cells 0-4, 6-10 and 12-15, matching menu_selection 0, 1, 2.
//
//   header (row 0):  HOME / MARKET tabs, or the screen title; days left at the right
//   PORTFOLIO        NET, CASH, then one row per stock: shares and profit/loss
//   STOCKS           one row per stock: price and an up/down arrow (30-day trend)
//   SPECIFIC         price, 30-day change, shares held; chart on rows 3-5
//   BUY / SELL       quantity, price (limit / stop price for those orders), total,
//                    cash or shares; the order type and SL/TP set on the switches,
//                    or a warning if the order would be rejected; BACK / QTY / NEXT
//   QUANTITY         the quantity in big digits, the digit being changed in yellow
//   ORDER_REVIEW     the order, its type and SL/TP, and its total; SEND
//   TRADE_RESULT     FILLED, PLACED (in the book) or REJECTED in big letters, and why
//   GAME_END         net worth in big digits and the final profit/loss
//   bot view (sw15)  the bot's value against yours, and per stock its signal,
//                    shares and P/L (NO BOT YET until Tricia's bot is in)
// Numbers come from display_numbers (bcd, neg).
module text_layer (
    input  [2:0]  row,
    input  [3:0]  col,
    input  [3:0]  screen_state,
    input  [3:0]  menu_selection,
    input  [2:0]  selected_stock,
    input  [1:0]  quantity_cursor,     // 0 ones .. 3 thousands
    input         trade_side,          // 0 buy, 1 sell
    input         trade_result_success,
    input  [2:0]  trade_result_code,
    input         order_valid,         // the order on screen would pass the checks
    input  [2:0]  validation_code,     // if not, why
    input  [`DN_N*32-1:0] bcd,
    input  [`DN_N-1:0]    neg,
    input  [3:0]  up,                  // stock k is at or above its price 30 days ago
    input         trade_result_placed, // a limit / stop order went into the book
    input  [1:0]  order_type,          // the order's type and SL/TP (from the switches)
    input  [1:0]  order_brk,
    input         bot_view,            // sw15: show the bot instead of the player
    input         bot_active,          // 0: the bot is not written yet (NO BOT YET)
    input  [7:0]  bot_signal,          // per stock [2k+1:2k]: 1 above its 8-day average, 2 below
    output reg        big,             // this screen uses the big row
    output reg        chart_on,        // rows 3-5 are the chart (SPECIFIC)
    output reg [7:0]  ch,
    output reg [15:0] fg,
    output reg [15:0] bg
);
    localparam [15:0] BLACK   = 16'h0000,
                      WHITE   = 16'hFFFF,
                      CYAN    = 16'h07FF,
                      YELLOW  = 16'hFFE0,
                      GREEN   = 16'h07E0,
                      RED     = 16'hF8A2,     // a little lighter than pure red: easier to read
                      GREY    = 16'h8C51,     // labels that matter less
                      HDR     = 16'h0012,     // header bar (navy)
                      BOTHDR  = 16'h4808,     // header bar in the bot view (plum)
                      BTN     = 16'h3186;     // unselected button (dark grey)

    // ------------------------------------------------------------ helpers
    function [7:0] str_ch;                 // character c of a 16-character string
        input [127:0] s;
        input [3:0]   c;
        begin
            str_ch = s[127 - 8*c -: 8];
        end
    endfunction

    function [7:0] ticker_ch;              // AMD, MCD, NVDA, GME (Yi An's stocks 0-3)
        input [1:0] k;
        input [3:0] p;
        reg [31:0] t;
        begin
            case (k)
                2'd0:    t = "AMD ";
                2'd1:    t = "MCD ";
                2'd2:    t = "NVDA";
                default: t = "GME ";
            endcase
            ticker_ch = (p > 4'd3) ? " " : t[31 - 8*p -: 8];
        end
    endfunction

    // A right-aligned number, w characters wide; p is the position in it.
    //   dp2: last two digits are cents;  prefix: e.g. "$" (0 = none);
    //   sgn: show + or -. Leading zeros blank; sign and prefix sit next to the digits.
    function [7:0] num_ch;
        input [31:0] d;
        input        sgn;
        input        is_neg;
        input        dp2;
        input [7:0]  prefix;
        input [3:0]  w;
        input [3:0]  p;
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
        input [3:0] c;
        begin
            case (code)
                `RJ_NO_CASH:   reason_ch = str_ch("NOT ENOUGH CASH ", c);
                `RJ_NO_POS:    reason_ch = str_ch("TOO FEW SHARES  ", c);
                `RJ_BOOK_FULL: reason_ch = str_ch("ORDER BOOK FULL ", c);
                `RJ_BAD_QTY:   reason_ch = str_ch("QTY: 1 TO 255   ", c);
                `RJ_BAD_TRIG:  reason_ch = str_ch("BAD TRIGGER     ", c);
                `RJ_TRIG_FAIL: reason_ch = str_ch("TRIGGER FAILED  ", c);
                `RJ_NOT_LIVE:  reason_ch = str_ch("MARKET CLOSED   ", c);
                default:       reason_ch = str_ch("                ", c);
            endcase
        end
    endfunction

    // the three buttons on row 6: cells 0-4, 6-10, 12-15 (5 and 11 are gaps)
    function [1:0] bar_button;             // 3 = a gap
        input [3:0] c;
        begin
            if (c <= 4'd4)       bar_button = 2'd0;
            else if (c == 4'd5)  bar_button = 2'd3;
            else if (c <= 4'd10) bar_button = 2'd1;
            else if (c == 4'd11) bar_button = 2'd3;
            else                 bar_button = 2'd2;
        end
    endfunction

    function [7:0] brk_ch;                 // OFF, 2%, 5%, 10% in 3 cells
        input [1:0] v;
        input [3:0] c;
        begin
            case (v)
                `BRK_2:  brk_ch = str_ch(" 2%             ", c);
                `BRK_5:  brk_ch = str_ch(" 5%             ", c);
                `BRK_10: brk_ch = str_ch("10%             ", c);
                default: brk_ch = str_ch("OFF             ", c);
            endcase
        end
    endfunction

    // ------------------------------------------------------------ numbers used here
    wire [1:0]  s       = selected_stock[1:0];
    wire [31:0] n_cash  = field(bcd, `DN_CASH);
    wire [31:0] n_net   = field(bcd, `DN_NET);
    wire [31:0] n_chg   = field(bcd, `DN_CHG);
    wire [31:0] n_qty   = field(bcd, `DN_QTY);
    wire [31:0] n_days  = field(bcd, `DN_DAYS);
    wire [31:0] n_ordpx = field(bcd, `DN_ORDPX);
    wire [31:0] n_ordt  = field(bcd, `DN_ORDTOT);
    wire [31:0] n_npnl  = field(bcd, `DN_NETPNL);
    wire [31:0] n_bnet  = field(bcd, `DN_BNET);
    wire [31:0] n_bnpnl = field(bcd, `DN_BNETPNL);
    wire [1:0]  bk      = row[1:0] - 2'd3;            // bot view: rows 3-6 = stocks 0-3
    wire [31:0] n_bpos  = field(bcd, `DN_BPOS0 + bk);
    wire [31:0] n_bpnl  = field(bcd, `DN_BPNL0 + bk);
    wire        g_bpnl  = neg[`DN_BPNL0 + bk];
    wire [1:0]  b_sig   = bot_signal[2*bk +: 2];
    wire        days_low = (n_days[31:4] == 28'd0) && (n_days[3:0] <= 4'd5);   // 5 days or fewer
    wire [31:0] n_spx   = field(bcd, `DN_PX0  + s);
    wire [31:0] n_spos  = field(bcd, `DN_POS0 + s);
    // the stock on this row: PORTFOLIO rows 3-6, STOCKS rows 1-4
    wire [1:0]  rk      = (screen_state == `UI_PORTFOLIO) ? row[1:0] - 2'd3 : row[1:0] - 2'd1;
    wire [31:0] n_rpx   = field(bcd, `DN_PX0  + rk);
    wire [31:0] n_rpos  = field(bcd, `DN_POS0 + rk);
    wire [31:0] n_rpnl  = field(bcd, `DN_PNL0 + rk);
    wire        g_rpnl  = neg[`DN_PNL0 + rk];

    wire        sell     = trade_side;
    wire [15:0] side_col = sell ? RED : GREEN;
    wire        tabs     = (screen_state == `UI_PORTFOLIO) || (screen_state == `UI_STOCKS) ||
                           (screen_state == `UI_SPECIFIC);
    // which tab the cursor is on (3 = none): HOME 0, MARKET 1
    wire [1:0]  tab_sel  = (screen_state == `UI_SPECIFIC) ?
                               ((menu_selection == 4'd3) ? 2'd0 : (menu_selection == 4'd4) ? 2'd1 : 2'd3) :
                               ((menu_selection == 4'd0) ? 2'd0 : (menu_selection == 4'd1) ? 2'd1 : 2'd3);
    wire [3:0]  stock_row_sel = menu_selection - 4'd1;   // STOCKS: menu 2..5 = rows 1..4

    // ------------------------------------------------------------ the cell
    reg [1:0] b;
    always @* begin
        ch       = " ";
        fg       = WHITE;
        bg       = BLACK;
        big      = !bot_view && ((screen_state == `UI_QUANTITY) || (screen_state == `UI_TRADE_RESULT) ||
                                     (screen_state == `UI_GAME_END));
        chart_on = !bot_view && (screen_state == `UI_SPECIFIC);
        b        = 2'd3;

        if (row == 3'd0) begin
            // ---------------------------------------------------- header bar
            bg = bot_view ? BOTHDR : HDR;
            if (col >= 4'd12 && screen_state != `UI_GAME_END) begin   // days left: D120 .. D  1
                ch = (col == 4'd12) ? "D" : num_ch(n_days, 1'b0, 1'b0, 1'b0, 8'd0, 4'd3, col - 4'd13);
                fg = days_low ? RED : YELLOW;
            end else if (bot_view) begin
                ch = str_ch("BOT VS YOU      ", col);
            end else if (tabs) begin
                // HOME (cells 0-3) and MARKET (5-10): the cursor's tab in yellow
                if (col <= 4'd3 || (col >= 4'd5 && col <= 4'd10)) begin
                    ch = (col <= 4'd3) ? str_ch("HOME            ", col) : str_ch("MARKET          ", col - 4'd5);
                    if ((col <= 4'd3) ? (tab_sel == 2'd0) : (tab_sel == 2'd1)) begin
                        bg = YELLOW; fg = BLACK;
                    end else if ((col <= 4'd3) == (screen_state == `UI_PORTFOLIO)) begin
                        fg = WHITE;             // the tab you are on
                    end else begin
                        fg = GREY;
                    end
                end
            end else begin
                case (screen_state)
                    `UI_BUY_STOCK, `UI_SELL_STOCK: begin
                        if (col <= 4'd3) begin ch = str_ch(sell ? "SELL            " : "BUY             ", col); fg = side_col; end
                        else if (col >= 4'd5 && col <= 4'd8) ch = ticker_ch(s, col - 4'd5);
                    end
                    `UI_QUANTITY:     ch = str_ch("QUANTITY        ", col);
                    `UI_ORDER_REVIEW: ch = str_ch("REVIEW          ", col);
                    `UI_ORDER_RESULT: ch = str_ch("SENDING         ", col);
                    `UI_TRADE_RESULT: ch = str_ch("RESULT          ", col);
                    `UI_GAME_END:     begin ch = str_ch("   GAME OVER    ", col); fg = YELLOW; end
                    default: ;
                endcase
            end
        end else if (bot_view && screen_state != `UI_TITLE) begin
            // ---------------------------------------------------- bot view (sw1)
            big = 1'b0;
            chart_on = 1'b0;
            case (row)
                3'd1: begin                                             // BOT  $10123.45
                    if (!bot_active) begin ch = str_ch("NO BOT YET      ", col); fg = GREY; end
                    else if (col <= 4'd2) begin ch = str_ch("BOT             ", col); fg = CYAN; end
                    else begin
                        ch = num_ch(n_bnet, 1'b0, 1'b0, 1'b1, "$", 4'd13, col - 4'd3);
                        fg = neg[`DN_BNETPNL] ? RED : GREEN;
                    end
                end
                3'd2: begin                                             // YOU  $13079.50
                    if (col <= 4'd2) begin ch = str_ch("YOU             ", col); fg = CYAN; end
                    else begin
                        ch = num_ch(n_net, 1'b0, 1'b0, 1'b1, "$", 4'd13, col - 4'd3);
                        fg = neg[`DN_NETPNL] ? RED : GREEN;
                    end
                end
                default: begin                                          // AMD ^  10   +123
                    if (!bot_active) ;
                    else if (col <= 4'd3) begin ch = ticker_ch(bk, col); fg = CYAN; end
                    else if (col == 4'd5) begin
                        ch = (b_sig == 2'd1) ? 8'h80 : (b_sig == 2'd2) ? 8'h81 : " ";
                        fg = (b_sig == 2'd1) ? GREEN : (b_sig == 2'd2) ? RED : GREY;
                    end
                    else if (col >= 4'd6 && col <= 4'd9) begin
                        ch = num_ch(n_bpos, 1'b0, 1'b0, 1'b0, 8'd0, 4'd4, col - 4'd6);
                        fg = (n_bpos == 32'd0) ? GREY : WHITE;
                    end
                    else if (col >= 4'd10) begin
                        ch = num_ch(n_bpnl >> 8, (n_bpnl >> 8) != 32'd0, g_bpnl, 1'b0, 8'd0, 4'd6, col - 4'd10);
                        fg = ((n_bpnl >> 8) == 32'd0) ? GREY : g_bpnl ? RED : GREEN;
                    end
                end
            endcase
        end else begin
            // ---------------------------------------------------- body
            case (screen_state)
                `UI_PORTFOLIO: begin
                    case (row)
                        3'd1: begin                                     // NET   $13079.50
                            if (col <= 4'd2) begin ch = str_ch("NET             ", col); fg = CYAN; end
                            else begin ch = num_ch(n_net, 1'b0, 1'b0, 1'b1, "$", 4'd13, col - 4'd3); fg = YELLOW; end
                        end
                        3'd2: begin                                     // CASH   $8423.50
                            if (col <= 4'd3) begin ch = str_ch("CASH            ", col); fg = CYAN; end
                            else ch = num_ch(n_cash, 1'b0, 1'b0, 1'b1, "$", 4'd12, col - 4'd4);
                        end
                        default: begin                                  // AMD   10  +84.50
                            if (col <= 4'd3) begin
                                ch = ticker_ch(rk, col);
                                fg = (n_rpos == 32'd0) ? GREY : CYAN;
                            end else if (col <= 4'd7) begin
                                ch = num_ch(n_rpos, 1'b0, 1'b0, 1'b0, 8'd0, 4'd4, col - 4'd4);
                                fg = (n_rpos == 32'd0) ? GREY : WHITE;
                            end else begin
                                ch = num_ch(n_rpnl, n_rpnl != 32'd0, g_rpnl, 1'b1, 8'd0, 4'd8, col - 4'd8);
                                fg = (n_rpnl == 32'd0) ? GREY : g_rpnl ? RED : GREEN;
                            end
                        end
                    endcase
                end

                `UI_STOCKS: begin                                       // > MCD   305.10 ^
                    if (row <= 3'd4) begin
                        if (col >= 4'd1 && col <= 4'd4)       begin ch = ticker_ch(rk, col - 4'd1); fg = CYAN; end
                        else if (col >= 4'd6 && col <= 4'd11) ch = num_ch(n_rpx, 1'b0, 1'b0, 1'b1, 8'd0, 4'd6, col - 4'd6);
                        else if (col == 4'd13)                begin ch = up[rk] ? 8'h80 : 8'h81; fg = up[rk] ? GREEN : RED; end
                        if ({1'b0, row} == stock_row_sel) begin              // the cursor's row
                            bg = YELLOW; fg = BLACK;
                        end
                    end else if (row == 3'd6) begin
                        ch = str_ch("U/D PICK  C OPEN", col); fg = GREY;
                    end
                end

                `UI_SPECIFIC: begin
                    case (row)
                        3'd1: begin                                     // MCD      $305.10
                            if (col <= 4'd3) begin ch = ticker_ch(s, col); fg = CYAN; end
                            else ch = num_ch(n_spx, 1'b0, 1'b0, 1'b1, "$", 4'd12, col - 4'd4);
                        end
                        3'd2: begin                                     // 30D -9.90  OWN  5
                            if (col <= 4'd2)      begin ch = str_ch("30D             ", col); fg = GREY; end
                            else if (col <= 4'd8) begin
                                ch = num_ch(n_chg, n_chg != 32'd0, neg[`DN_CHG], 1'b1, 8'd0, 4'd6, col - 4'd3);
                                fg = neg[`DN_CHG] ? RED : GREEN;
                            end
                            else if (col >= 4'd10 && col <= 4'd12) begin ch = str_ch("OWN             ", col - 4'd10); fg = GREY; end
                            else if (col >= 4'd13) ch = num_ch(n_spos, 1'b0, 1'b0, 1'b0, 8'd0, 4'd3, col - 4'd13);
                        end
                        3'd6: begin                                     //  BUY   SELL  BACK
                            ch = str_ch(" BUY  SELL  BACK", col);
                            b  = bar_button(col);
                        end
                        default: ;                                      // rows 3-5: chart
                    endcase
                end

                `UI_BUY_STOCK, `UI_SELL_STOCK, `UI_ORDER_REVIEW: begin
                    case (row)
                        3'd1: begin
                            if (screen_state == `UI_ORDER_REVIEW) begin // BUY    12  MCD
                                if (col <= 4'd3)       begin ch = str_ch(sell ? "SELL            " : "BUY             ", col); fg = side_col; end
                                else if (col <= 4'd8)  ch = num_ch(n_qty, 1'b0, 1'b0, 1'b0, 8'd0, 4'd5, col - 4'd4);
                                else if (col >= 4'd10 && col <= 4'd13) begin ch = ticker_ch(s, col - 4'd10); fg = CYAN; end
                            end else begin                              // QTY        12
                                if (col <= 4'd2) begin ch = str_ch("QTY             ", col); fg = CYAN; end
                                else ch = num_ch(n_qty, 1'b0, 1'b0, 1'b0, 8'd0, 4'd13, col - 4'd3);
                            end
                        end
                        3'd2: begin                                     // PRICE / LIMIT / STOP  $305.15
                            if (col <= 4'd4) begin
                                ch = str_ch((order_type == `OT_LMT) ? "LIMIT           " :
                                            (order_type == `OT_STP) ? "STOP            " : "PRICE           ", col);
                                fg = CYAN;
                            end
                            else ch = num_ch(n_ordpx, 1'b0, 1'b0, 1'b1, "$", 4'd11, col - 4'd5);
                        end
                        3'd3: begin                                     // TOTAL  $3662.80
                            if (col <= 4'd4) begin ch = str_ch("TOTAL           ", col); fg = CYAN; end
                            else begin
                                ch = num_ch(n_ordt, neg[`DN_ORDTOT], 1'b1, 1'b1, "$", 4'd11, col - 4'd5);
                                fg = YELLOW;
                            end
                        end
                        3'd4: begin
                            if (screen_state == `UI_ORDER_REVIEW) begin // MKT    SL/TP  5%
                                if (col <= 4'd2) begin
                                    ch = str_ch((order_type == `OT_LMT) ? "LMT             " :
                                                (order_type == `OT_STP) ? "STP             " : "MKT             ", col);
                                    bg = BTN;
                                end else if (!sell && col >= 4'd7 && col <= 4'd11) begin ch = str_ch("SL/TP           ", col - 4'd7); fg = GREY; end
                                else if (!sell && col >= 4'd13) begin
                                    ch = brk_ch(order_brk, col - 4'd13);
                                    fg = (order_brk == `BRK_OFF) ? GREY : YELLOW;
                                end
                            end else if (!sell) begin                       // CASH   $8423.50
                                if (col <= 4'd3) begin ch = str_ch("CASH            ", col); fg = GREY; end
                                else begin ch = num_ch(n_cash, 1'b0, 1'b0, 1'b1, "$", 4'd12, col - 4'd4); fg = GREY; end
                            end else begin                              // OWN           5
                                if (col <= 4'd2) begin ch = str_ch("OWN             ", col); fg = GREY; end
                                else begin ch = num_ch(n_spos, 1'b0, 1'b0, 1'b0, 8'd0, 4'd13, col - 4'd3); fg = GREY; end
                            end
                        end
                        3'd5: begin
                            if (!order_valid) begin                     // why it would be rejected
                                ch = reason_ch(validation_code, col); fg = RED;
                            end else if (screen_state != `UI_ORDER_REVIEW) begin   // LMT    SL/TP  5%
                                if (col <= 4'd2) begin
                                    ch = str_ch((order_type == `OT_LMT) ? "LMT             " :
                                                (order_type == `OT_STP) ? "STP             " : "MKT             ", col);
                                    bg = BTN;
                                end else if (!sell && col >= 4'd7 && col <= 4'd11) begin ch = str_ch("SL/TP           ", col - 4'd7); fg = GREY; end
                                else if (!sell && col >= 4'd13) begin
                                    ch = brk_ch(order_brk, col - 4'd13);
                                    fg = (order_brk == `BRK_OFF) ? GREY : YELLOW;
                                end
                            end
                        end
                        3'd6: begin
                            if (screen_state == `UI_ORDER_REVIEW) begin //   C: SEND ORDER
                                ch = str_ch(" C: SEND ORDER  ", col);
                                if (col <= 4'd14) begin bg = YELLOW; fg = BLACK; end
                            end else begin                              //  BACK   QTY  NEXT
                                ch = str_ch(" BACK  QTY  NEXT", col);
                                b  = bar_button(col);
                            end
                        end
                        default: ;
                    endcase
                end

                `UI_QUANTITY: begin
                    case (row)
                        3'd1: begin                                     // big: 0012
                            if (col >= 4'd2 && col <= 4'd5) begin
                                ch = "0" + n_qty[4*(5 - col) +: 4];
                                if (col == 4'd5 - {2'b00, quantity_cursor}) begin bg = YELLOW; fg = BLACK; end
                            end
                        end
                        3'd3: begin                                     // BUY  MCD
                            if (col <= 4'd3) begin ch = str_ch(sell ? "SELL            " : "BUY             ", col); fg = side_col; end
                            else if (col >= 4'd5 && col <= 4'd8) begin ch = ticker_ch(s, col - 4'd5); fg = CYAN; end
                        end
                        3'd4: begin ch = str_ch("UP/DOWN: CHANGE ", col); fg = GREY; end
                        3'd5: begin ch = str_ch("LEFT/RIGHT: MOVE", col); fg = GREY; end
                        3'd6: begin
                            ch = str_ch("    C: DONE     ", col);
                            if (col >= 4'd3 && col <= 4'd11) begin bg = YELLOW; fg = BLACK; end
                        end
                        default: ;
                    endcase
                end

                `UI_ORDER_RESULT: begin
                    if (row == 3'd3) begin ch = str_ch(" PLEASE WAIT... ", col); fg = CYAN; end
                end

                `UI_TRADE_RESULT: begin
                    case (row)
                        3'd1: begin                                     // big: FILLED / REJECTED
                            if (trade_result_success && trade_result_placed) begin ch = str_ch(" PLACED         ", col); fg = CYAN; end
                            else if (trade_result_success) begin ch = str_ch(" FILLED         ", col); fg = GREEN; end
                            else                      begin ch = str_ch("REJECTED        ", col); fg = RED; end
                        end
                        3'd3: begin
                            if (!trade_result_success) ch = reason_ch(trade_result_code, col);
                            else if (col <= 4'd3)      begin ch = str_ch(sell ? "SELL            " : "BUY             ", col); fg = side_col; end
                            else if (col <= 4'd8)      ch = num_ch(n_qty, 1'b0, 1'b0, 1'b0, 8'd0, 4'd5, col - 4'd4);
                            else if (col >= 4'd10 && col <= 4'd13) begin ch = ticker_ch(s, col - 4'd10); fg = CYAN; end
                        end
                        3'd6: begin
                            ch = str_ch("  C: CONTINUE   ", col);
                            if (col >= 4'd1 && col <= 4'd13) begin bg = YELLOW; fg = BLACK; end
                        end
                        default: ;
                    endcase
                end

                `UI_GAME_END: begin
                    case (row)
                        3'd1: begin                                     // big: $13079 (whole dollars)
                            ch = num_ch(n_net >> 8, 1'b0, 1'b0, 1'b0, "$", 4'd8, col);
                            fg = neg[`DN_NETPNL] ? RED : GREEN;
                        end
                        3'd3: begin                                     // P/L  +$3079.50
                            if (col <= 4'd2) begin ch = str_ch("P/L             ", col); fg = CYAN; end
                            else begin
                                ch = num_ch(n_npnl, n_npnl != 32'd0, neg[`DN_NETPNL], 1'b1, "$", 4'd13, col - 4'd3);
                                fg = neg[`DN_NETPNL] ? RED : GREEN;
                            end
                        end
                        3'd4: begin ch = str_ch("START  $10000.00", col); fg = GREY; end
                        3'd6: begin ch = str_ch(" SW0: NEW GAME  ", col); fg = GREY; end
                        default: ;
                    endcase
                end

                default: ;
            endcase

            // three-button bar: the cursor's button yellow, the others dark grey
            if (b != 2'd3) begin
                if (b == menu_selection[1:0] && menu_selection[3:2] == 2'b00 && menu_selection != 4'd3) begin
                    bg = YELLOW; fg = BLACK;
                end else begin
                    bg = BTN; fg = WHITE;
                end
            end
        end
    end
endmodule
