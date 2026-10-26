`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// ticket_screen: pixel colour of the Order Ticket page, on the shared
// text_grid layout (header bar + six rows of 16 cells, Matthew's 5x7 font).
//
// Ticket view (every field except ORDERS focused):
//   row 0   TICKET  FILLED 12       header; the last fill / placed order / reject (2 s)
//   row 1   MCD  BID  305.05        stock (focusable)
//   row 2        ASK  305.15
//   row 3   BUY  QTY       12       BUY/SELL (green/red); centre on QTY toggles it
//   row 4   MKT  TRG   305.10       order type; trigger grey for MKT
//   row 5   SL/TP  5%   OPEN 2      stop-loss/take-profit; pending orders
//   row 6   SUBMIT    ORDERS        buttons
// The focused field is black on yellow.
//
// ORDERS view (ORDERS focused): five book slots at a time, scrolling with the
// cursor; stop-loss legs red (SL), take-profit legs green (TP).
//   row 0   ORDERS 2/8
//   row 1   1 NVDA SL  173.60     the cursor's row is black on yellow
//   row 6   C: CANCEL ORDER
//
// Numbers come from one sequential BCD converter that refreshes the 14
// displayed values round-robin, about 250 clocks for a full pass.
module ticket_screen #(
    parameter REJ_SHOW_CYCLES = 200_000_000,   // 2 s at 100 MHz
    parameter FLIP_180        = 0              // 1: rotate the page 180 degrees (OLED mounted upside down)
) (
    input  wire        clk,
    input  wire        sys_reset,
    input  wire [6:0]  pix_x,
    input  wire [5:0]  pix_y,
    // live ticket state
    input  wire [1:0]  stock,
    input  wire [15:0] bid,
    input  wire [15:0] ask,
    input  wire        side,
    input  wire [1:0]  otype,
    input  wire [7:0]  qty,
    input  wire [15:0] trig,
    input  wire [1:0]  brk,
    input  wire [2:0]  ord_sel,
    input  wire [2:0]  focus,
    input  wire [3:0]  pending_count,
    // the book, every slot (order_book all_* outputs)
    input  wire [7:0]   bk_valid,
    input  wire [7:0]   bk_side,
    input  wire [15:0]  bk_stock,
    input  wire [15:0]  bk_type,
    input  wire [63:0]  bk_qty,
    input  wire [127:0] bk_trig,
    input  wire [7:0]   bk_leg,
    // events
    input  wire        fill,
    input  wire        fill_side,
    input  wire [7:0]  fill_qty,
    input  wire [15:0] fill_price,
    input  wire        placed,
    input  wire        placed_side,
    input  wire [1:0]  placed_type,
    input  wire [7:0]  placed_qty,
    input  wire [15:0] placed_trig,
    input  wire        reject,
    input  wire [2:0]  reject_code,
    output wire [15:0] ticket_pix
);
    // ------------------------------------------------------------ orientation
    // (px, py) is the page position being drawn. With FLIP_180 = 1 the OLED's
    // pixel (pix_x, pix_y) shows page position (95 - x, 63 - y): the whole page
    // turned 180 degrees, for a Pmod OLED that sits upside down on its header.
    wire [6:0] px = FLIP_180 ? 7'd95 - pix_x : pix_x;
    wire [5:0] py = FLIP_180 ? 6'd63 - pix_y : pix_y;

    // ------------------------------------------------------------ colours (RGB565)
    localparam [15:0] BLACK  = 16'h0000,
                      WHITE  = 16'hFFFF,
                      CYAN   = 16'h07FF,
                      YELLOW = 16'hFFE0,
                      GREEN  = 16'h07E0,
                      RED    = 16'hF8A2,
                      GREY   = 16'h8C51,
                      HDR    = 16'h0012,     // header bar
                      BTN    = 16'h3186;     // unselected button

    localparam F_QTY = 3'd0, F_TRG = 3'd1, F_SUB = 3'd2, F_BRK = 3'd3, F_ORD = 3'd4, F_STK = 3'd5;

    wire orders_view = (focus == F_ORD);

    // ------------------------------------------------------------ status message state
    localparam MSG_NONE = 2'd0, MSG_FILL = 2'd1, MSG_PLACED = 2'd2;

    reg [1:0]  msg_kind;
    reg        msg_side;
    reg [1:0]  msg_type;
    reg [7:0]  msg_qty;
    reg [15:0] msg_px;
    reg [2:0]  rej_code;
    reg [27:0] rej_timer;          // non-zero while the reject message shows

    always @(posedge clk) begin
        if (sys_reset) begin
            msg_kind  <= MSG_NONE;
            msg_side  <= 1'b0;
            msg_type  <= 2'd0;
            msg_qty   <= 8'd0;
            msg_px    <= 16'd0;
            rej_code  <= `RJ_NONE;
            rej_timer <= 28'd0;
        end else if (fill) begin
            msg_kind  <= MSG_FILL;
            msg_side  <= fill_side;
            msg_qty   <= fill_qty;
            msg_px    <= fill_price;
            rej_timer <= 28'd0;
        end else if (placed) begin
            msg_kind  <= MSG_PLACED;
            msg_side  <= placed_side;
            msg_type  <= placed_type;
            msg_qty   <= placed_qty;
            msg_px    <= placed_trig;
            rej_timer <= 28'd0;
        end else if (reject) begin
            rej_code  <= reject_code;
            rej_timer <= REJ_SHOW_CYCLES;
        end else if (rej_timer != 28'd0) begin
            rej_timer <= rej_timer - 28'd1;
        end
    end

    // ------------------------------------------------------------ number refresh
    // values 0-5: bid, ask, qty, trig, message qty, message price; 6-13: book slot 0-7 trigger
    reg [19:0] bcd_bid, bcd_ask, bcd_qty, bcd_trig, bcd_mqty, bcd_mpx;
    reg [19:0] bcd_st [0:7];
    reg [3:0]  cv_idx;
    reg        cv_go;
    reg [15:0] cv_bin;
    wire       cv_busy, cv_done;
    wire [19:0] cv_bcd;
    wire [2:0] cv_slot = cv_idx[2:0] - 3'd6;   // values 6-13 -> slots 0-7

    always @* begin
        case (cv_idx)
            4'd0:    cv_bin = bid;
            4'd1:    cv_bin = ask;
            4'd2:    cv_bin = {8'd0, qty};
            4'd3:    cv_bin = trig;
            4'd4:    cv_bin = {8'd0, msg_qty};
            4'd5:    cv_bin = msg_px;
            default: cv_bin = bk_trig[16*cv_slot +: 16];
        endcase
    end

    b_bin2bcd_seq u_bcd (
        .clk(clk), .sys_reset(sys_reset), .start(cv_go), .bin(cv_bin),
        .busy(cv_busy), .done(cv_done), .bcd(cv_bcd)
    );

    integer n;
    always @(posedge clk) begin
        if (sys_reset) begin
            cv_idx   <= 4'd0;
            cv_go    <= 1'b1;
            bcd_bid  <= 20'd0;
            bcd_ask  <= 20'd0;
            bcd_qty  <= 20'd0;
            bcd_trig <= 20'd0;
            bcd_mqty <= 20'd0;
            bcd_mpx  <= 20'd0;
            for (n = 0; n < 8; n = n + 1) bcd_st[n] <= 20'd0;
        end else begin
            cv_go <= 1'b0;
            if (cv_done) begin
                case (cv_idx)
                    4'd0:    bcd_bid  <= cv_bcd;
                    4'd1:    bcd_ask  <= cv_bcd;
                    4'd2:    bcd_qty  <= cv_bcd;
                    4'd3:    bcd_trig <= cv_bcd;
                    4'd4:    bcd_mqty <= cv_bcd;
                    4'd5:    bcd_mpx  <= cv_bcd;
                    default: bcd_st[cv_slot] <= cv_bcd;
                endcase
                cv_idx <= (cv_idx == 4'd13) ? 4'd0 : cv_idx + 4'd1;
                cv_go  <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------ text helpers
    function [7:0] str_ch;                 // character c of a 16-character string
        input [127:0] s;
        input [3:0]   c;
        begin
            str_ch = s[127 - 8*c -: 8];
        end
    endfunction

    function [7:0] ticker_ch;              // AMD, MCD, NVDA, GME
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

    // a 5-digit BCD value, right-aligned in w cells; dp2 = last two digits are cents
    function [7:0] num_ch;
        input [19:0] d;
        input        dp2;
        input [3:0]  w;
        input [3:0]  p;
        integer r, msd, rm, j, i;
        begin
            r = w - 1 - p;
            msd = dp2 ? 2 : 0;
            for (j = 0; j < 5; j = j + 1)
                if (d[4*j +: 4] != 4'd0 && j > msd) msd = j;
            rm = (dp2 && msd >= 2) ? msd + 1 : msd;
            num_ch = " ";
            if (r <= rm) begin
                if (dp2 && r == 2) num_ch = ".";
                else begin
                    i = (dp2 && r > 2) ? r - 1 : r;
                    num_ch = "0" + d[4*i +: 4];
                end
            end
        end
    endfunction

    function [7:0] rej_ch;                 // short reject reasons, 9 cells
        input [2:0] code;
        input [3:0] c;
        begin
            case (code)
                `RJ_NO_CASH:   rej_ch = str_ch("NO CASH         ", c);
                `RJ_NO_POS:    rej_ch = str_ch("NO SHARES       ", c);
                `RJ_BOOK_FULL: rej_ch = str_ch("BOOK FULL       ", c);
                `RJ_BAD_QTY:   rej_ch = str_ch("BAD QTY         ", c);
                `RJ_BAD_TRIG:  rej_ch = str_ch("BAD TRIG        ", c);
                `RJ_TRIG_FAIL: rej_ch = str_ch("TRIG FAIL       ", c);
                `RJ_NOT_LIVE:  rej_ch = str_ch("CLOSED          ", c);
                default:       rej_ch = str_ch("                ", c);
            endcase
        end
    endfunction

    // ------------------------------------------------------------ layout
    wire [2:0]  row;
    wire [3:0]  col;
    wire        is_big;
    reg  [7:0]  ch;
    reg  [15:0] fg, bg;

    text_grid grid (
        .x(px), .y(py), .big(1'b0),
        .row(row), .col(col), .is_big(is_big),
        .ch(ch), .fg(fg), .bg(bg), .color(ticket_pix)
    );

    // ORDERS view: rows 1-5 show slots first..first+4
    wire [2:0] first = (ord_sel > 3'd4) ? ord_sel - 3'd4 : 3'd0;
    wire [2:0] slot  = first + row - 3'd1;
    wire        sl_valid = bk_valid[slot];
    wire        sl_side  = bk_side[slot];
    wire [1:0]  sl_stock = bk_stock[2*slot +: 2];
    wire [1:0]  sl_type  = bk_type[2*slot +: 2];
    wire        sl_leg   = bk_leg[slot];
    wire [19:0] sl_trig  = bcd_st[slot];

    wire mkt    = (otype == `OT_MKT);
    wire rej_on = (rej_timer != 28'd0);

    always @* begin
        ch = " ";
        fg = WHITE;
        bg = BLACK;
        if (row == 3'd0) begin
            // -------------------------------------------------------- header bar
            bg = HDR;
            if (orders_view) begin                                  // ORDERS 2/8
                if (col <= 4'd5)       ch = str_ch("ORDERS          ", col);
                else if (col == 4'd7)  ch = "0" + pending_count;
                else if (col == 4'd8)  ch = "/";
                else if (col == 4'd9)  ch = "8";
            end else if (col <= 4'd5) begin
                ch = str_ch("TICKET          ", col);
            end else if (col >= 4'd7) begin                         // status, 9 cells
                if (rej_on) begin
                    ch = rej_ch(rej_code, col - 4'd7);
                    fg = RED;
                end else if (msg_kind != MSG_NONE) begin            // FILLED 12 / PLACED 12
                    if (col <= 4'd12) ch = str_ch((msg_kind == MSG_FILL) ? "FILLED          " : "PLACED          ", col - 4'd7);
                    else              ch = num_ch(bcd_mqty, 1'b0, 4'd3, col - 4'd13);
                    fg = (msg_kind == MSG_FILL) ? GREEN : WHITE;
                end
            end
        end else if (orders_view) begin
            // -------------------------------------------------------- ORDERS list
            if (row <= 3'd5) begin                                  // 1 NVDA SL 173.60 (cursor row yellow)
                if (col == 4'd0) ch = "1" + slot;
                else if (!sl_valid) begin
                    if (col == 4'd2) ch = "-";
                    fg = GREY;
                end else if (col >= 4'd2 && col <= 4'd5) begin
                    ch = ticker_ch(sl_stock, col - 4'd2);
                    fg = CYAN;
                end else if (col >= 4'd7 && col <= 4'd8) begin
                    ch = str_ch(sl_leg ? ((sl_type == `OT_STP) ? "SL              " : "TP              ")
                                       : ((sl_type == `OT_LMT) ? "LM              " : "ST              "), col - 4'd7);
                    fg = sl_leg ? ((sl_type == `OT_STP) ? RED : GREEN) : (sl_side ? RED : GREEN);
                end else if (col >= 4'd10) ch = num_ch(sl_trig, 1'b1, 4'd6, col - 4'd10);
                if (slot == ord_sel) begin bg = YELLOW; fg = BLACK; end
            end else begin
                ch = str_ch("C: CANCEL ORDER ", col);
                fg = GREY;
            end
        end else begin
            // -------------------------------------------------------- ticket
            case (row)
                3'd1: begin                                         // MCD  BID  305.05
                    if (col <= 4'd3) begin
                        ch = ticker_ch(stock, col);
                        fg = CYAN;
                        if (focus == F_STK) begin bg = YELLOW; fg = BLACK; end
                    end else if (col >= 4'd5 && col <= 4'd7) begin ch = str_ch("BID             ", col - 4'd5); fg = GREY; end
                    else if (col >= 4'd9) ch = num_ch(bcd_bid, 1'b1, 4'd7, col - 4'd9);
                end
                3'd2: begin                                         //      ASK  305.15
                    if (col >= 4'd5 && col <= 4'd7) begin ch = str_ch("ASK             ", col - 4'd5); fg = GREY; end
                    else if (col >= 4'd9) ch = num_ch(bcd_ask, 1'b1, 4'd7, col - 4'd9);
                end
                3'd3: begin                                         // BUY  QTY       12
                    if (col <= 4'd3) begin
                        ch = str_ch(side ? "SELL            " : "BUY             ", col);
                        bg = side ? RED : GREEN; fg = BLACK;
                    end else if (col >= 4'd5) begin
                        if (col <= 4'd7) begin ch = str_ch("QTY             ", col - 4'd5); fg = CYAN; end
                        else             ch = num_ch(bcd_qty, 1'b0, 4'd7, col - 4'd9);
                        if (focus == F_QTY) begin bg = YELLOW; fg = BLACK; end
                    end
                end
                3'd4: begin                                         // MKT  TRG   305.10
                    if (col <= 4'd2) begin
                        ch = str_ch(mkt ? "MKT             " : (otype == `OT_LMT) ? "LMT             " : "STP             ", col);
                        bg = BTN;
                    end else if (col >= 4'd5) begin
                        if (col <= 4'd7) begin ch = str_ch("TRG             ", col - 4'd5); fg = mkt ? GREY : CYAN; end
                        else begin ch = num_ch(bcd_trig, 1'b1, 4'd7, col - 4'd9); fg = mkt ? GREY : WHITE; end
                    end
                    if (focus == F_TRG && col != 4'd3 && col != 4'd4) begin bg = YELLOW; fg = BLACK; end
                end
                3'd5: begin                                         // SL/TP  5%   OPEN 2
                    if (col <= 4'd4) begin ch = str_ch("SL/TP           ", col); fg = CYAN; end
                    else if (col >= 4'd6 && col <= 4'd8)
                        ch = str_ch((brk == `BRK_OFF) ? "OFF             " : (brk == `BRK_2) ? " 2%             " :
                                    (brk == `BRK_5)   ? " 5%             " : "10%             ", col - 4'd6);
                    else if (col >= 4'd10 && col <= 4'd13) begin ch = str_ch("OPEN            ", col - 4'd10); fg = GREY; end
                    else if (col == 4'd15) ch = "0" + pending_count;
                    if (focus == F_BRK && col <= 4'd8) begin bg = YELLOW; fg = BLACK; end
                    else if (brk == `BRK_OFF && col >= 4'd6 && col <= 4'd8) fg = GREY;
                end
                3'd6: begin                                         // SUBMIT    ORDERS
                    if (col <= 4'd6) begin
                        ch = str_ch(" SUBMIT         ", col);
                        if (focus == F_SUB) begin bg = YELLOW; fg = BLACK; end
                        else bg = BTN;
                    end else if (col >= 4'd9) begin
                        ch = str_ch(" ORDERS         ", col - 4'd9);
                        bg = BTN;
                    end
                end
                default: ;
            endcase
        end
    end
endmodule

`default_nettype wire
