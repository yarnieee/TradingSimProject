`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"
`include "ticket_layout.vh"

// ticket_screen: pixel colour of the Order Ticket page.
//
// Ticket view (every field except ORDERS focused):
//   y 0-5    left black: the top level overlays D's tab bar
//   y 7-11   >AMD B123.25 A123.35          stock (focusable), bid, ask
//   y 15-24  [ BUY ][ SELL ]  [ MKT ]     side buttons + type button
//   y 27-31  >QTY 010                     focused field yellow
//   y 35-39  >TRG 120.00   >SL/TP  5%     TRG grey when type = MKT
//   y 43-52        [ SUBMIT ]             yellow border when focused
//   y 55-59  FILL B010@123.35  PEND 3     or REJ NO CASH (red, 2 s)
//
// ORDERS view (ORDERS focused): every book slot, one per row
//   y 7-11   ORDERS 3/8  C=CANCEL
//   y 14-59  >1 AMD LMT B010@120.00       cursor yellow; SL legs red, TP legs green
//             2 -                         empty slot
//
// ticket_pix is purely combinational from (pix_x, pix_y) and registered
// state: no RAM reads, so no lookahead is needed. Text is the 3x5 font in 4x6
// cells. Numbers come from one sequential BCD converter that refreshes the 22
// displayed values round-robin, about 400 clocks for a full pass.
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
    output reg  [15:0] ticket_pix
);
    // ------------------------------------------------------------ orientation
    // (px, py) is the page position being drawn. With FLIP_180 = 1 the OLED's
    // pixel (pix_x, pix_y) shows page position (95 - x, 63 - y): the whole page
    // turned 180 degrees, for a Pmod OLED that sits upside down on its header.
    wire [6:0] px = FLIP_180 ? 7'd95 - pix_x : pix_x;
    wire [5:0] py = FLIP_180 ? 6'd63 - pix_y : pix_y;
    // ------------------------------------------------------------ colours (RGB565)
    localparam [15:0] C_BLACK  = 16'h0000,
                      C_WHITE  = 16'hFFFF,
                      C_GREEN  = 16'h07E0,
                      C_RED    = 16'hF800,
                      C_GREY   = 16'h4208,
                      C_YELLOW = 16'hFFE0,
                      C_BLUE   = 16'h001F;

    // focus codes, as in order_entry
    localparam F_QTY = 3'd0, F_TRG = 3'd1, F_SUB = 3'd2, F_BRK = 3'd3, F_ORD = 3'd4, F_STK = 3'd5;

    wire orders_view = (focus == F_ORD);

    // ------------------------------------------------------------ status line state
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
    // values 0-5: bid, ask, qty, trig, message qty, message price
    //        6-13: book slot 0-7 qty;  14-21: book slot 0-7 trigger price
    reg [19:0] bcd_bid, bcd_ask, bcd_qty, bcd_trig, bcd_mqty, bcd_mpx;
    reg [11:0] bcd_sq [0:7];       // slot qty, 3 digits
    reg [19:0] bcd_st [0:7];       // slot trigger price
    reg [4:0]  cv_idx;
    reg        cv_go;
    reg [15:0] cv_bin;
    wire       cv_busy, cv_done;
    wire [19:0] cv_bcd;
    wire [2:0] cv_slot = cv_idx[2:0] - 3'd6;   // slot for values 6-13 and 14-21 (6 and 14 both map to 0)

    always @* begin
        case (cv_idx)
            5'd0:    cv_bin = bid;
            5'd1:    cv_bin = ask;
            5'd2:    cv_bin = {8'd0, qty};
            5'd3:    cv_bin = trig;
            5'd4:    cv_bin = {8'd0, msg_qty};
            5'd5:    cv_bin = msg_px;
            default: cv_bin = (cv_idx < 5'd14) ? {8'd0, bk_qty[8*cv_slot +: 8]} : bk_trig[16*cv_slot +: 16];
        endcase
    end

    b_bin2bcd_seq u_bcd (
        .clk(clk), .sys_reset(sys_reset), .start(cv_go), .bin(cv_bin),
        .busy(cv_busy), .done(cv_done), .bcd(cv_bcd)
    );

    integer n;
    always @(posedge clk) begin
        if (sys_reset) begin
            cv_idx   <= 5'd0;
            cv_go    <= 1'b1;
            bcd_bid  <= 20'd0;
            bcd_ask  <= 20'd0;
            bcd_qty  <= 20'd0;
            bcd_trig <= 20'd0;
            bcd_mqty <= 20'd0;
            bcd_mpx  <= 20'd0;
            for (n = 0; n < 8; n = n + 1) begin
                bcd_sq[n] <= 12'd0;
                bcd_st[n] <= 20'd0;
            end
        end else begin
            cv_go <= 1'b0;
            if (cv_done) begin
                case (cv_idx)
                    5'd0:    bcd_bid  <= cv_bcd;
                    5'd1:    bcd_ask  <= cv_bcd;
                    5'd2:    bcd_qty  <= cv_bcd;
                    5'd3:    bcd_trig <= cv_bcd;
                    5'd4:    bcd_mqty <= cv_bcd;
                    5'd5:    bcd_mpx  <= cv_bcd;
                    default: begin
                        if (cv_idx < 5'd14) bcd_sq[cv_slot] <= cv_bcd[11:0];
                        else                bcd_st[cv_slot] <= cv_bcd;
                    end
                endcase
                cv_idx <= (cv_idx == 5'd21) ? 5'd0 : cv_idx + 5'd1;
                cv_go  <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------ text helpers
    // ASCII byte -> font code, so labels can be written as strings.
    function [5:0] asc;
        input [7:0] a;
        begin
            if (a >= "0" && a <= "9")      asc = a - "0";
            else if (a >= "A" && a <= "Z") asc = a - "A" + 8'd10;
            else begin
                case (a)
                    ".":     asc = `CH_DOT;
                    "+":     asc = `CH_PLUS;
                    "-":     asc = `CH_MINUS;
                    "%":     asc = `CH_PCT;
                    "$":     asc = `CH_DOLLAR;
                    ":":     asc = `CH_COLON;
                    "/":     asc = `CH_SLASH;
                    "@":     asc = `CH_AT;
                    "[":     asc = `CH_LBR;
                    "]":     asc = `CH_RBR;
                    ">":     asc = `CH_GT;
                    "=":     asc = `CH_EQ;
                    default: asc = `CH_SPACE;
                endcase
            end
        end
    endfunction

    // fixed 8-character labels
    localparam L_BLANK = 5'd0,  L_BUY  = 5'd1,  L_SELL = 5'd2,  L_MKT  = 5'd3,
               L_LMT   = 5'd4,  L_STP  = 5'd5,  L_QTY  = 5'd6,  L_TRG  = 5'd7,
               L_SUB   = 5'd8,  L_FILL = 5'd9,  L_REJ  = 5'd10, L_PEND = 5'd11,
               L_SLTP  = 5'd12, L_ORD  = 5'd13, L_CANC = 5'd14, L_SL   = 5'd15,
               L_TK0   = 5'd16,                  // L_TK0 + stock = ticker
               L_TP    = 5'd20, L_OFF  = 5'd21, L_B2   = 5'd22, L_B5   = 5'd23,
               L_B10   = 5'd24;

    function [5:0] lbl_char;
        input [4:0] which;
        input [4:0] k;            // 0..7
        reg   [63:0] s;
        begin
            case (which)
                L_BUY:      s = "BUY     ";
                L_SELL:     s = "SELL    ";
                L_MKT:      s = "MKT     ";
                L_LMT:      s = "LMT     ";
                L_STP:      s = "STP     ";
                L_QTY:      s = "QTY     ";
                L_TRG:      s = "TRG     ";
                L_SUB:      s = "SUBMIT  ";
                L_FILL:     s = "FILL    ";
                L_REJ:      s = "REJ     ";
                L_PEND:     s = "PEND    ";
                L_SLTP:     s = "SL/TP   ";
                L_ORD:      s = "ORDERS  ";
                L_CANC:     s = "C=CANCEL";
                L_SL:       s = "SL      ";
                L_TP:       s = "TP      ";
                L_OFF:      s = "OFF     ";
                L_B2:       s = " 2%     ";
                L_B5:       s = " 5%     ";
                L_B10:      s = "10%     ";
                // stock 0..3: Yi An's AMD and MCD; 2 and 3 have no data yet
                L_TK0:      s = "AMD     ";
                L_TK0 + 1:  s = "MCD     ";
                L_TK0 + 2:  s = "ST3     ";
                L_TK0 + 3:  s = "ST4     ";
                default:    s = "        ";
            endcase
            lbl_char = (k > 5'd7) ? `CH_SPACE : asc(s[63 - 8*k -: 8]);
        end
    endfunction

    // 9-character reject reasons
    function [5:0] rej_char;
        input [2:0] code;
        input [4:0] k;            // 0..8
        reg   [71:0] s;
        begin
            case (code)
                `RJ_NO_CASH:   s = "NO CASH  ";
                `RJ_NO_POS:    s = "NO POS   ";
                `RJ_BOOK_FULL: s = "BOOK FULL";
                `RJ_BAD_QTY:   s = "BAD QTY  ";
                `RJ_BAD_TRIG:  s = "BAD TRIG ";
                `RJ_TRIG_FAIL: s = "TRIG FAIL";
                `RJ_NOT_LIVE:  s = "NOT LIVE ";
                default:       s = "         ";
            endcase
            rej_char = (k > 5'd8) ? `CH_SPACE : asc(s[71 - 8*k -: 8]);
        end
    endfunction

    // price in cents -> "123.45", leading zeros of the dollars blanked
    function [5:0] price_char;
        input [19:0] b;
        input [2:0]  k;           // 0..5
        begin
            case (k)
                3'd0:    price_char = (b[19:16] == 4'd0) ? `CH_SPACE : {2'b00, b[19:16]};
                3'd1:    price_char = (b[19:12] == 8'd0) ? `CH_SPACE : {2'b00, b[15:12]};
                3'd2:    price_char = {2'b00, b[11:8]};
                3'd3:    price_char = `CH_DOT;
                3'd4:    price_char = {2'b00, b[7:4]};
                3'd5:    price_char = {2'b00, b[3:0]};
                default: price_char = `CH_SPACE;
            endcase
        end
    endfunction

    // qty -> "010", always three digits
    function [5:0] qty_char;
        input [11:0] b;
        input [1:0]  k;           // 0..2
        begin
            case (k)
                2'd0:    qty_char = {2'b00, b[11:8]};
                2'd1:    qty_char = {2'b00, b[7:4]};
                default: qty_char = {2'b00, b[3:0]};
            endcase
        end
    endfunction

    function in_text;
        input [6:0] x;
        input [5:0] y;
        input [6:0] x0;
        input [4:0] n;            // characters
        input [5:0] y0;
        begin
            in_text = ({1'b0, x} >= {1'b0, x0}) && ({1'b0, x} < {1'b0, x0} + {1'b0, n, 2'b00})
                   && (y >= y0) && (y < y0 + 6'd5);
        end
    endfunction

    function in_box;
        input [6:0] x;
        input [5:0] y;
        input [6:0] x0, x1;
        input [5:0] y0, y1;
        begin
            in_box = (x >= x0) && (x <= x1) && (y >= y0) && (y <= y1);
        end
    endfunction

    function on_edge;
        input [6:0] x;
        input [5:0] y;
        input [6:0] x0, x1;
        input [5:0] y0, y1;
        begin
            on_edge = in_box(x, y, x0, x1, y0, y1) && (x == x0 || x == x1 || y == y0 || y == y1);
        end
    endfunction

    // ------------------------------------------------------------ ORDERS view rows
    // row k (book slot k) is text at y = 14 + 6k
    localparam [5:0] Y_ROW0 = 6'd14;
    reg       in_row;
    reg [2:0] row;
    integer   r;
    always @* begin
        in_row = 1'b0;
        row    = 3'd0;
        for (r = 0; r < 8; r = r + 1)
            if (py >= Y_ROW0 + 6*r && py < Y_ROW0 + 6*r + 5) begin
                in_row = 1'b1;
                row    = r;
            end
    end

    // the slot on this row
    wire        rw_valid = bk_valid[row];
    wire        rw_side  = bk_side[row];
    wire [1:0]  rw_stock = bk_stock[2*row +: 2];
    wire [1:0]  rw_type  = bk_type[2*row +: 2];
    wire        rw_leg   = bk_leg[row];
    wire [11:0] rw_qty   = bcd_sq[row];
    wire [19:0] rw_trig  = bcd_st[row];

    // ------------------------------------------------------------ text segments
    // {x0, chars, y0} for each run of text
    localparam SEG_NONE = 4'd0,  SEG_HDR  = 4'd1,  SEG_BUY  = 4'd2,  SEG_SELL = 4'd3,
               SEG_TYPE = 4'd4,  SEG_QTY  = 4'd5,  SEG_TRG  = 4'd7,  SEG_BRK  = 4'd8,
               SEG_SUB  = 4'd9,  SEG_STAT = 4'd10, SEG_OHDR = 4'd11, SEG_OROW = 4'd12;

    localparam [5:0] Y_HDR = 6'd7, Y_BTN = 6'd17, Y_SUB = 6'd45;

    reg [3:0] seg;
    reg [6:0] sx0;
    reg [5:0] sy0;

    always @* begin
        seg = SEG_NONE;
        sx0 = 7'd0;
        sy0 = 6'd0;
        if (orders_view) begin
            if      (in_text(px, py, 7'd0, 5'd20, Y_HDR))                         begin seg = SEG_OHDR; sy0 = Y_HDR; end
            else if (in_row && in_text(px, py, 7'd0, 5'd22, Y_ROW0 + 6'd6 * row)) begin seg = SEG_OROW; sy0 = Y_ROW0 + 6'd6 * row; end
        end else begin
            if      (in_text(px, py, 7'd0,  5'd20, Y_HDR))       begin seg = SEG_HDR;  sx0 = 7'd0;  sy0 = Y_HDR;       end
            else if (in_text(px, py, 7'd8,  5'd3,  Y_BTN))       begin seg = SEG_BUY;  sx0 = 7'd8;  sy0 = Y_BTN;       end
            else if (in_text(px, py, 7'd34, 5'd4,  Y_BTN))       begin seg = SEG_SELL; sx0 = 7'd34; sy0 = Y_BTN;       end
            else if (in_text(px, py, 7'd72, 5'd3,  Y_BTN))       begin seg = SEG_TYPE; sx0 = 7'd72; sy0 = Y_BTN;       end
            else if (in_text(px, py, 7'd0,  5'd8,  `TK_QTY_Y0))  begin seg = SEG_QTY;  sx0 = 7'd0;  sy0 = `TK_QTY_Y0;  end
            else if (in_text(px, py, 7'd0,  5'd11, `TK_TRG_Y0))  begin seg = SEG_TRG;  sx0 = 7'd0;  sy0 = `TK_TRG_Y0;  end
            else if (in_text(px, py, 7'd52, 5'd10, `TK_TRG_Y0))  begin seg = SEG_BRK;  sx0 = 7'd52; sy0 = `TK_TRG_Y0;  end
            else if (in_text(px, py, 7'd36, 5'd6,  Y_SUB))       begin seg = SEG_SUB;  sx0 = 7'd36; sy0 = Y_SUB;       end
            else if (in_text(px, py, 7'd0,  5'd24, `TK_STAT_Y0)) begin seg = SEG_STAT; sx0 = 7'd0;  sy0 = `TK_STAT_Y0; end
        end
    end

    wire [6:0] dx = px - sx0;
    wire [5:0] dy = py - sy0;
    wire [4:0] ci = dx[6:2];       // character index within the segment
    wire [1:0] gx = dx[1:0];       // column within the 4-wide cell

    wire mkt     = (otype == `OT_MKT);
    wire rej_on  = (rej_timer != 28'd0);

    reg [5:0]  ch;
    reg [15:0] tcol;

    always @* begin
        ch   = `CH_SPACE;
        tcol = C_WHITE;
        case (seg)
            SEG_HDR: begin
                // ">AMD B123.25 A123.35"
                if (ci == 5'd0)                     ch = (focus == F_STK) ? `CH_GT : `CH_SPACE;
                else if (ci <= 5'd3)                ch = lbl_char(L_TK0 + stock, ci - 5'd1);
                else if (ci == 5'd5)                ch = asc("B");
                else if (ci >= 5'd6 && ci <= 5'd11) ch = price_char(bcd_bid, ci - 5'd6);
                else if (ci == 5'd13)               ch = asc("A");
                else if (ci >= 5'd14)               ch = price_char(bcd_ask, ci - 5'd14);
                if (ci == 5'd0 || (ci <= 5'd3 && focus == F_STK)) tcol = C_YELLOW;
            end
            SEG_BUY: begin
                ch   = lbl_char(L_BUY, ci);
                tcol = (side == `SIDE_BUY) ? C_BLACK : C_WHITE;
            end
            SEG_SELL: begin
                ch   = lbl_char(L_SELL, ci);
                tcol = (side == `SIDE_SELL) ? C_BLACK : C_WHITE;
            end
            SEG_TYPE: begin
                ch = lbl_char(mkt ? L_MKT : (otype == `OT_LMT) ? L_LMT : L_STP, ci);
            end
            SEG_QTY: begin
                if (ci == 5'd0)                    ch = (focus == F_QTY) ? `CH_GT : `CH_SPACE;
                else if (ci <= 5'd3)               ch = lbl_char(L_QTY, ci - 5'd1);
                else if (ci >= 5'd5)               ch = qty_char(bcd_qty[11:0], ci - 5'd5);
                if (ci == 5'd0 || (ci >= 5'd5 && focus == F_QTY)) tcol = C_YELLOW;
            end
            SEG_TRG: begin
                if (ci == 5'd0)                    ch = (focus == F_TRG) ? `CH_GT : `CH_SPACE;
                else if (ci <= 5'd3)               ch = lbl_char(L_TRG, ci - 5'd1);
                else if (ci >= 5'd5)               ch = price_char(bcd_trig, ci - 5'd5);
                if (ci == 5'd0)                         tcol = C_YELLOW;
                else if (mkt)                           tcol = C_GREY;
                else if (ci >= 5'd5 && focus == F_TRG)  tcol = C_YELLOW;
            end
            SEG_BRK: begin
                // ">SL/TP  5%"
                if (ci == 5'd0)                    ch = (focus == F_BRK) ? `CH_GT : `CH_SPACE;
                else if (ci <= 5'd5)               ch = lbl_char(L_SLTP, ci - 5'd1);
                else if (ci >= 5'd7)               ch = lbl_char(L_OFF + brk, ci - 5'd7);
                if (ci == 5'd0 || (ci >= 5'd7 && focus == F_BRK)) tcol = C_YELLOW;
                else if (brk == `BRK_OFF)                         tcol = C_GREY;
            end
            SEG_SUB: begin
                ch = lbl_char(L_SUB, ci);
            end
            SEG_STAT: begin
                if (ci >= 5'd18) begin
                    // "PEND n" at the right, always shown
                    if (ci <= 5'd21)       ch = lbl_char(L_PEND, ci - 5'd18);
                    else if (ci == 5'd23)  ch = {2'b00, pending_count};
                end else if (rej_on) begin
                    // "REJ NO CASH"
                    tcol = C_RED;
                    if (ci <= 5'd2)        ch = lbl_char(L_REJ, ci);
                    else if (ci >= 5'd4)   ch = rej_char(rej_code, ci - 5'd4);
                end else if (msg_kind != MSG_NONE) begin
                    // "FILL B010@123.35" or "LMT  B010@120.00"
                    tcol = (msg_kind == MSG_FILL) ? C_GREEN : C_WHITE;
                    if (ci <= 5'd3)
                        ch = lbl_char((msg_kind == MSG_FILL)    ? L_FILL :
                                      (msg_type == `OT_LMT)     ? L_LMT  : L_STP, ci);
                    else if (ci == 5'd5)   ch = asc(msg_side ? "S" : "B");
                    else if (ci >= 5'd6 && ci <= 5'd8) ch = qty_char(bcd_mqty[11:0], ci - 5'd6);
                    else if (ci == 5'd9)   ch = `CH_AT;
                    else if (ci >= 5'd10)  ch = price_char(bcd_mpx, ci - 5'd10);
                end
            end
            SEG_OHDR: begin
                // "ORDERS 3/8  C=CANCEL"
                if (ci <= 5'd5)            ch = lbl_char(L_ORD, ci);
                else if (ci == 5'd7)       ch = {2'b00, pending_count};
                else if (ci == 5'd8)       ch = `CH_SLASH;
                else if (ci == 5'd9)       ch = 6'd8;
                else if (ci >= 5'd12)      ch = lbl_char(L_CANC, ci - 5'd12);
                if (ci >= 5'd12)           tcol = C_GREY;
            end
            SEG_OROW: begin
                // ">1 AMD LMT B010@120.00"; SL/TP legs show SL or TP as their type
                if (ci == 5'd0)                       ch = (ord_sel == row) ? `CH_GT : `CH_SPACE;
                else if (ci == 5'd1)                  ch = {3'b000, row} + 6'd1;
                else if (!rw_valid) begin
                    if (ci == 5'd3)                   ch = `CH_MINUS;
                end else if (ci >= 5'd3 && ci <= 5'd5) ch = lbl_char(L_TK0 + rw_stock, ci - 5'd3);
                else if (ci >= 5'd7 && ci <= 5'd9)    ch = lbl_char(rw_leg ? ((rw_type == `OT_STP) ? L_SL : L_TP)
                                                                           : ((rw_type == `OT_LMT) ? L_LMT : L_STP), ci - 5'd7);
                else if (ci == 5'd11)                 ch = asc(rw_side ? "S" : "B");
                else if (ci >= 5'd12 && ci <= 5'd14)  ch = qty_char(rw_qty, ci - 5'd12);
                else if (ci == 5'd15)                 ch = `CH_AT;
                else if (ci >= 5'd16)                 ch = price_char(rw_trig, ci - 5'd16);
                if (ci == 5'd0 || (ci == 5'd1 && ord_sel == row)) tcol = C_YELLOW;
                else if (!rw_valid)                              tcol = C_GREY;
                else if (rw_leg)                                 tcol = (rw_type == `OT_STP) ? C_RED : C_GREEN;
            end
            default: ;
        endcase
    end

    wire glyph;
    font_3x5 u_font (.ch(ch), .row(dy[2:0]), .col(gx), .pix(glyph));
    wire text_on = (seg != SEG_NONE) && glyph;

    // ------------------------------------------------------------ final colour
    wire in_buy   = in_box (px, py, `TK_BUY_X0,  `TK_BUY_X1,  `TK_BTN_Y0, `TK_BTN_Y1);
    wire in_sell  = in_box (px, py, `TK_SELL_X0, `TK_SELL_X1, `TK_BTN_Y0, `TK_BTN_Y1);
    wire in_sub   = in_box (px, py, `TK_SUB_X0,  `TK_SUB_X1,  `TK_SUB_Y0, `TK_SUB_Y1);
    wire e_buy    = on_edge(px, py, `TK_BUY_X0,  `TK_BUY_X1,  `TK_BTN_Y0, `TK_BTN_Y1);
    wire e_sell   = on_edge(px, py, `TK_SELL_X0, `TK_SELL_X1, `TK_BTN_Y0, `TK_BTN_Y1);
    wire e_type   = on_edge(px, py, `TK_TYPE_X0, `TK_TYPE_X1, `TK_BTN_Y0, `TK_BTN_Y1);
    wire e_sub    = on_edge(px, py, `TK_SUB_X0,  `TK_SUB_X1,  `TK_SUB_Y0, `TK_SUB_Y1);

    always @* begin
        if (py < 6'd6)                                  ticket_pix = C_BLACK;   // D's tab bar
        else if (text_on)                               ticket_pix = tcol;
        else if (orders_view)                           ticket_pix = C_BLACK;
        else if (in_buy  && side == `SIDE_BUY)          ticket_pix = C_GREEN;
        else if (in_sell && side == `SIDE_SELL)         ticket_pix = C_RED;
        else if (e_buy || e_sell || e_type)             ticket_pix = C_GREY;
        else if (e_sub && focus == F_SUB)               ticket_pix = C_YELLOW;
        else if (in_sub)                                ticket_pix = C_BLUE;
        else                                            ticket_pix = C_BLACK;
    end
endmodule

`default_nettype wire
