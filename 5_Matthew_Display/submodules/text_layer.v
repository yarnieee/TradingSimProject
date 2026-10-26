`timescale 1ns / 1ps
`include "trading_defs.vh"

// Text for every screen of the right OLED, on one grid: 16 columns of 6-pixel
// cells, and these lines (5x7 font, each line 7 pixels tall):
//
//   line 0..4   y = 13, 21, 29, 37, 45    (STOCKS: y = 13, 22, 31, 40, to sit in the list buttons)
//   line 5      y = 55                    bottom line; columns 13-15 hold the days left ("D30")
//
// Each screen says what goes in each cell, so no two pieces of text can land on
// the same pixels. The tab bar (y 1-10), buttons, OK box and chart are drawn by
// menu_buttons / menu_button_text / chart_renderer in the areas this layer leaves empty.
// Numbers come from display_numbers as decimal digits (bcd, neg).
module text_layer (
    input  [12:0] pixel_index,
    input  [3:0]  screen_state,
    input  [2:0]  selected_stock,
    input  [1:0]  quantity_cursor,     // 0 ones .. 3 thousands
    input         trade_side,          // 0 buy, 1 sell
    input         trade_result_success,
    input  [2:0]  trade_result_code,
    input  [`DN_N*32-1:0] bcd,
    input  [`DN_N-1:0]    neg,
    input  [3:0]  up,                  // stock k is above its price 30 days ago
    output reg        pixel_active,
    output reg [15:0] pixel_color
);
    localparam [15:0] WHITE  = 16'hFFFF,
                      CYAN   = 16'h07FF,
                      YELLOW = 16'hFFE0,
                      GREEN  = 16'h07E0,
                      RED    = 16'hF800;

    wire [6:0] pixel_x = pixel_index % 96;
    wire [5:0] pixel_y = pixel_index / 96;
    wire [3:0] col     = pixel_x / 6;
    wire [2:0] gx      = pixel_x % 6;

    // ------------------------------------------------------------ which line
    reg       on_line;
    reg [2:0] line;
    reg [2:0] gy;
    integer   ln;
    always @* begin
        on_line = 1'b0;
        line    = 3'd0;
        gy      = 3'd0;
        if (pixel_y >= 6'd55 && pixel_y < 6'd62) begin
            on_line = 1'b1; line = 3'd5; gy = pixel_y - 6'd55;
        end else if (screen_state == `UI_STOCKS) begin
            for (ln = 0; ln < 4; ln = ln + 1)
                if (pixel_y >= 13 + 9*ln && pixel_y < 20 + 9*ln) begin
                    on_line = 1'b1; line = ln; gy = pixel_y - (13 + 9*ln);
                end
        end else begin
            for (ln = 0; ln < 5; ln = ln + 1)
                if (pixel_y >= 13 + 8*ln && pixel_y < 20 + 8*ln) begin
                    on_line = 1'b1; line = ln; gy = pixel_y - (13 + 8*ln);
                end
        end
    end

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
        input [3:0] p;                     // 0..3
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

    // A right-aligned number field w characters wide; p is the position in it.
    //   dp2:    show the last two digits as cents (".05")
    //   prefix: a character just before the number ("$"), or 0 for none
    //   sgn:    show + or - before the number (and before the prefix)
    // Leading zeros are blank; the sign and prefix sit next to the first digit.
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
            r = w - 1 - p;                                 // 0 = rightmost
            msd = dp2 ? 2 : 0;                             // always show "0.05" / "0"
            for (j = 0; j < 8; j = j + 1)
                if (d[4*j +: 4] != 4'd0 && j > msd) msd = j;
            rm = (dp2 && msd >= 2) ? msd + 1 : msd;        // position of the first digit
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

    function [31:0] field;                 // the digits of one display_numbers field
        input [`DN_N*32-1:0] all;
        input [4:0] f;
        begin
            field = all[32*f +: 32];
        end
    endfunction

    function [7:0] reason_ch;              // why an order was rejected
        input [2:0] code;
        input [3:0] c;
        begin
            case (code)
                `RJ_NO_CASH:   reason_ch = str_ch("NOT ENOUGH CASH ", c);
                `RJ_NO_POS:    reason_ch = str_ch("TOO FEW SHARES  ", c);
                `RJ_BOOK_FULL: reason_ch = str_ch("ORDER BOOK FULL ", c);
                `RJ_BAD_QTY:   reason_ch = str_ch("QTY NOT 1 TO 255", c);
                `RJ_BAD_TRIG:  reason_ch = str_ch("BAD TRIGGER     ", c);
                `RJ_TRIG_FAIL: reason_ch = str_ch("TRIGGER FAILED  ", c);
                `RJ_NOT_LIVE:  reason_ch = str_ch("MARKET CLOSED   ", c);
                default:       reason_ch = str_ch("                ", c);
            endcase
        end
    endfunction

    // ------------------------------------------------------------ the numbers used here
    wire [1:0]  s       = selected_stock[1:0];
    wire [31:0] n_cash  = field(bcd, `DN_CASH);
    wire [31:0] n_net   = field(bcd, `DN_NET);
    wire [31:0] n_chg   = field(bcd, `DN_CHG);
    wire [31:0] n_qty   = field(bcd, `DN_QTY);
    wire [31:0] n_days  = field(bcd, `DN_DAYS);
    wire [31:0] n_ordpx = field(bcd, `DN_ORDPX);
    wire [31:0] n_ordt  = field(bcd, `DN_ORDTOT);
    wire [31:0] n_npnl  = field(bcd, `DN_NETPNL);
    wire [31:0] n_spx   = field(bcd, `DN_PX0  + s);
    wire [31:0] n_spos  = field(bcd, `DN_POS0 + s);
    wire [31:0] n_spnl  = field(bcd, `DN_PNL0 + s);
    wire        g_spnl  = neg[`DN_PNL0 + s];
    // stock row k on the portfolio and stock-list screens
    wire [1:0]  rk      = (screen_state == `UI_STOCKS) ? line[1:0] : line[1:0] - 2'd1;
    wire [31:0] n_rpx   = field(bcd, `DN_PX0  + rk);
    wire [31:0] n_rpos  = field(bcd, `DN_POS0 + rk);
    wire [31:0] n_rpnl  = field(bcd, `DN_PNL0 + rk);
    wire        g_rpnl  = neg[`DN_PNL0 + rk];

    wire        sell    = trade_side;
    wire [15:0] side_col = sell ? RED : GREEN;
    // cursor digit on the quantity screen: column 9 is ones, 6 is thousands
    wire [3:0]  qcur_col = 4'd9 - {2'b00, quantity_cursor};
    wire        days_on  = (screen_state != `UI_TITLE) && (screen_state != `UI_GAME_END);

    // ------------------------------------------------------------ character and colour of each cell
    reg [7:0]  ch;
    reg [15:0] cc;
    always @* begin
        ch = " ";
        cc = WHITE;
        if (line == 3'd5 && col >= 4'd13) begin
            // days left, bottom right of every game screen
            if (days_on) begin
                cc = YELLOW;
                ch = (col == 4'd13) ? "D" : num_ch(n_days, 1'b0, 1'b0, 1'b0, 8'd0, 4'd2, col - 4'd14);
            end
        end else begin
            case (screen_state)
                `UI_PORTFOLIO: begin
                    if (line == 3'd0) begin                        // NET    $10372.15
                        if (col <= 4'd2) begin ch = str_ch("NET             ", col); cc = CYAN; end
                        else begin ch = num_ch(n_net, 1'b0, 1'b0, 1'b1, "$", 4'd13, col - 4'd3); cc = YELLOW; end
                    end else if (line <= 3'd4) begin               // AMD   10 +123.45
                        if (col <= 4'd3)      begin ch = ticker_ch(rk, col); cc = CYAN; end
                        else if (col <= 4'd7) ch = num_ch(n_rpos, 1'b0, 1'b0, 1'b0, 8'd0, 4'd4, col - 4'd4);
                        else begin
                            ch = num_ch(n_rpnl, n_rpnl != 32'd0, g_rpnl, 1'b1, 8'd0, 4'd8, col - 4'd8);
                            cc = (n_rpnl == 32'd0) ? WHITE : g_rpnl ? RED : GREEN;
                        end
                    end else if (line == 3'd5) begin               // CASH  $8423
                        if (col <= 4'd3) begin ch = str_ch("CASH            ", col); cc = CYAN; end
                        else if (col <= 4'd11) ch = num_ch(n_cash >> 8, 1'b0, 1'b0, 1'b0, "$", 4'd8, col - 4'd4);
                    end
                end

                `UI_STOCKS: begin                                  // (in the button) AMD   213.45
                    if (line <= 3'd3) begin
                        if (col >= 4'd1 && col <= 4'd4) ch = ticker_ch(rk, col - 4'd1);
                        else if (col >= 4'd6 && col <= 4'd11) begin
                            ch = num_ch(n_rpx, 1'b0, 1'b0, 1'b1, 8'd0, 4'd6, col - 4'd6);
                            cc = up[rk] ? GREEN : RED;
                        end
                    end
                end

                `UI_SPECIFIC: begin
                    if (line == 3'd0) begin                        // MCD 305.10 -1.25
                        if (col <= 4'd3)      begin ch = ticker_ch(s, col); cc = CYAN; end
                        else if (col <= 4'd9) ch = num_ch(n_spx, 1'b0, 1'b0, 1'b1, 8'd0, 4'd6, col - 4'd4);
                        else begin
                            ch = num_ch(n_chg, n_chg != 32'd0, neg[`DN_CHG], 1'b1, 8'd0, 4'd6, col - 4'd10);
                            cc = neg[`DN_CHG] ? RED : GREEN;
                        end
                    end else if (line == 3'd5) begin               // POS  10  +123 (P/L in whole dollars)
                        if (col <= 4'd2)       begin ch = str_ch("POS             ", col); cc = CYAN; end
                        else if (col <= 4'd6)  ch = num_ch(n_spos, 1'b0, 1'b0, 1'b0, 8'd0, 4'd4, col - 4'd3);
                        else if (col <= 4'd11) begin
                            ch = num_ch(n_spnl >> 8, (n_spnl >> 8) != 32'd0, g_spnl, 1'b0, 8'd0, 4'd5, col - 4'd7);
                            cc = ((n_spnl >> 8) == 32'd0) ? WHITE : g_spnl ? RED : GREEN;
                        end
                    end
                end

                `UI_BUY_STOCK, `UI_SELL_STOCK, `UI_ORDER_REVIEW: begin
                    if (line == 3'd0) begin                        // BUY    12 MCD
                        if (col <= 4'd3)      begin ch = str_ch(sell ? "SELL            " : "BUY             ", col); cc = side_col; end
                        else if (col <= 4'd7) ch = num_ch(n_qty, 1'b0, 1'b0, 1'b0, 8'd0, 4'd4, col - 4'd4);
                        else if (col >= 4'd9 && col <= 4'd12) begin ch = ticker_ch(s, col - 4'd9); cc = CYAN; end
                    end else if (line == 3'd1) begin               // AT   $305.15
                        if (col <= 4'd1)      begin ch = str_ch("AT              ", col); cc = CYAN; end
                        else ch = num_ch(n_ordpx, 1'b0, 1'b0, 1'b1, "$", 4'd14, col - 4'd2);
                    end else if (line == 3'd2) begin               // TOTAL $3662.80
                        if (col <= 4'd4)      begin ch = str_ch("TOTAL           ", col); cc = CYAN; end
                        else begin
                            ch = num_ch(n_ordt, neg[`DN_ORDTOT], 1'b1, 1'b1, "$", 4'd11, col - 4'd5);
                            cc = YELLOW;
                        end
                    end else if (line == 3'd5 && screen_state != `UI_ORDER_REVIEW) begin
                        if (!sell) begin                           // CASH $8423
                            if (col <= 4'd3)       begin ch = str_ch("CASH            ", col); cc = CYAN; end
                            else if (col <= 4'd11) ch = num_ch(n_cash >> 8, 1'b0, 1'b0, 1'b0, "$", 4'd8, col - 4'd4);
                        end else begin                             // OWN   10
                            if (col <= 4'd2)       begin ch = str_ch("OWN             ", col); cc = CYAN; end
                            else if (col <= 4'd7)  ch = num_ch(n_spos, 1'b0, 1'b0, 1'b0, 8'd0, 4'd5, col - 4'd3);
                        end
                    end
                end

                `UI_QUANTITY: begin
                    case (line)
                        3'd0: begin ch = str_ch("SET QUANTITY    ", col); cc = CYAN; end
                        3'd1: begin
                            if (col <= 4'd3) begin ch = str_ch(sell ? "SELL            " : "BUY             ", col); cc = side_col; end
                            else if (col >= 4'd5 && col <= 4'd8) begin ch = ticker_ch(s, col - 4'd5); cc = CYAN; end
                        end
                        3'd2: begin                                // 0012, the digit being changed in yellow
                            if (col >= 4'd6 && col <= 4'd9) begin
                                ch = "0" + n_qty[4*(9 - col) +: 4];
                                cc = (col == qcur_col) ? YELLOW : WHITE;
                            end
                        end
                        3'd3: ch = str_ch("UP/DOWN: CHANGE ", col);
                        3'd4: ch = str_ch("LEFT/RIGHT: MOVE", col);
                        3'd5: if (col <= 4'd7) begin ch = str_ch("C: DONE         ", col); cc = CYAN; end
                        default: ;
                    endcase
                end

                `UI_ORDER_RESULT: begin
                    if (line == 3'd0)      begin ch = str_ch("SENDING ORDER   ", col); cc = CYAN; end
                    else if (line == 3'd1) ch = str_ch("PLEASE WAIT     ", col);
                end

                `UI_TRADE_RESULT: begin
                    if (line == 3'd0) begin
                        ch = str_ch(trade_result_success ? "ORDER FILLED    " : "REJECTED        ", col);
                        cc = trade_result_success ? GREEN : RED;
                    end else if (line == 3'd1) begin
                        if (!trade_result_success) ch = reason_ch(trade_result_code, col);
                        else if (col <= 4'd3)      begin ch = str_ch(sell ? "SELL            " : "BUY             ", col); cc = side_col; end
                        else if (col <= 4'd7)      ch = num_ch(n_qty, 1'b0, 1'b0, 1'b0, 8'd0, 4'd4, col - 4'd4);
                        else if (col >= 4'd9 && col <= 4'd12) begin ch = ticker_ch(s, col - 4'd9); cc = CYAN; end
                    end
                end

                `UI_GAME_END: begin
                    if (line == 3'd0) begin ch = str_ch("GAME OVER       ", col); cc = YELLOW; end
                    else if (line == 3'd2) begin
                        if (col <= 4'd2) begin ch = str_ch("NET             ", col); cc = CYAN; end
                        else ch = num_ch(n_net, 1'b0, 1'b0, 1'b1, "$", 4'd13, col - 4'd3);
                    end else if (line == 3'd3) begin
                        if (col <= 4'd2) begin ch = str_ch("P/L             ", col); cc = CYAN; end
                        else begin
                            ch = num_ch(n_npnl, n_npnl != 32'd0, neg[`DN_NETPNL], 1'b1, "$", 4'd13, col - 4'd3);
                            cc = neg[`DN_NETPNL] ? RED : GREEN;
                        end
                    end
                end

                default: ;     // title screen: artwork only
            endcase
        end
    end

    // ------------------------------------------------------------ pixel
    wire glyph_pixel;
    font_renderer font_renderer_inst (
        .char_code(ch),
        .glyph_x(gx),
        .glyph_y(gy),
        .pixel_on(glyph_pixel)
    );

    // the quantity screen underlines the digit being changed (just below line 2)
    wire underline = (screen_state == `UI_QUANTITY) && (pixel_y == 6'd36) &&
                     (col == qcur_col) && (gx < 3'd5);

    always @* begin
        pixel_active = (on_line && glyph_pixel) || underline;
        pixel_color  = underline ? YELLOW : cc;
    end
endmodule
