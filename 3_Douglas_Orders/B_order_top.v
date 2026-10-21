`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// B_order_top: Douglas's order and execution engine + Order Ticket page.
// This is what the team top level instantiates. Ports follow the Module I/O
// map in the team plan doc; encodings of Matthew's signals are in trading_defs.vh.
//
//   order_entry --submit--> exec_engine --fill--> Tricia, Matthew
//        |                     ^   |  \--reject--> Matthew
//        | cancel    trq/ack   |   v ins, ins_pair (stop-loss + take-profit)
//        +------------------> order_book
//   ticket_screen draws the page from all of the above.
//
// The ticket has its own stock, which follows Matthew's sel_stock and can also
// be changed with the buttons, so the ticket can place any order by itself.
//
// The order engine never writes cash or positions; it only reads Tricia's ledger.
//
// ============================================================== INPUTS AND OUTPUTS
// How each port connects to the other top modules in the team build
// (Integration_Top, branch-team-integration). "now" = how it is wired today;
// "plan" = what the Module I/O map asks for, if different.
//
// INPUTS
//   Port           Width  From                          Use here
//   clk            1      board 100 MHz clock           everything
//   sys_reset      1      Integration_Top (sw[0],       clears the book, ticket, messages
//                         synchronised)
//   game_state     [1:0]  Matthew: D_display_top          orders and book scans only while PLAYING
//                         (PLAYING except title / game-end screens)
//   price0..3      [15:0] Yi An: A_top                  bid/ask, order checks, book triggers
//                         now: price0 = AMD, price1 = MCD, price2/3 = 0 (closed)
//                         plan: A_top outputs price0..3 itself
//   tick           1      Yi An: A_top                  starts a book scan (one pulse per trading day)
//                         now: made in Integration_Top from AMD's date changing
//   sel_stock      [1:0]  Matthew: D_display_top          stock for his orders; the ticket follows it
//   page_R         1      Matthew                       0 = ticket has the buttons, 1 = it ignores them
//                         now: tied to 1 (Matthew's screens own the buttons)
//   btn_pulse      [4:0]  Matthew (debounced buttons)   ticket fields, submit, cancel
//                         now: tied to 0
//   ord_req        1      Matthew: D_display_top          places his order (entering the CONFIRM screen)
//   ord_side       1      Matthew: D_display_top          BUY or SELL screen he came from
//   ord_type       [1:0]  Matthew                       now: tied to MKT
//   ord_qty        [13:0] Matthew: game_fsm quantity    1-255 accepted, else BAD QTY
//   ord_trig       [15:0] Matthew                       now: tied to 0 (market orders only)
//   cash           [31:0] Tricia: ledger                buy checks (cost + fee <= cash)
//   pos0..3        [9:0]  Tricia: ledger                sell checks (qty <= position)
//   ledger_busy    1      Tricia: ledger                waits for it to drop before the next order
//   xR, yR         [6:0], Matthew: D_display_top          pixel the left OLED (JA) is drawing
//                  [5:0]  (left_x, left_y)              (named xR/yR from the plan's right OLED)
//
// OUTPUTS
//   Port           Width  To                            Meaning
//   fill           1      Tricia: ledger;               one pulse per filled order
//                         Integration_Top: led[15]
//   fill_stock     [1:0]  Tricia: ledger                which stock
//   fill_side      1      Tricia: ledger                0 buy, 1 sell
//   fill_qty       [7:0]  Tricia: ledger                shares
//   fill_price     [15:0] Tricia: ledger                cents per share (ask for buys, bid for sells)
//   fill_fee       [15:0] Tricia: ledger                cents ($1 flat)
//   reject         1      Integration_Top: led[14]      one pulse per rejected order
//                         plan: Matthew (reject screen)
//   reject_code    [2:0]  plan: Matthew                 why (codes in trading_defs.vh); now unused
//   pending_count  [3:0]  Integration_Top: led[11:8]    orders waiting in the book, 0-8
//   ticket_pixel   [15:0] Matthew: D_display_top          RGB565 colour of the ticket page at (xR, yR),
//                         (left_pixel) -> left OLED JA  drawn rotated 180 degrees (TICKET_FLIP_180)
module B_order_top #(
    parameter SPREAD          = 5,             // cents per side [ASSUMPTION]
    parameter FEE             = 100,           // cents per execution [ASSUMPTION]
    parameter POS_MAX         = 1023,
    parameter QTY_INIT        = 1,             // [ASSUMPTION]
    parameter TRIG_STEP       = 5,             // cents per notch [ASSUMPTION]
    parameter REJ_SHOW_CYCLES = 200_000_000,   // 2 s at 100 MHz
    parameter TICKET_FLIP_180 = 0              // 1: ticket page drawn rotated 180 degrees (upside-down OLED)
) (
    input  wire        clk,
    input  wire        sys_reset,
    input  wire [1:0]  game_state,     // orders only while GS_PLAYING
    // price bus (Yi An)
    input  wire [15:0] price0,
    input  wire [15:0] price1,
    input  wire [15:0] price2,
    input  wire [15:0] price3,
    input  wire        tick,
    // UI event bus (Matthew)
    input  wire [1:0]  sel_stock,
    input  wire        page_R,         // active right-OLED page; buttons act only on PG_R_TICKET (tie 0 until Matthew has pages)
    input  wire [4:0]  btn_pulse,      // debounced 1-clock pulses, bits per BTN_* defines
    // complete order from Matthew's confirm screen, for stock sel_stock
    input  wire        ord_req,        // 1-clock pulse
    input  wire        ord_side,
    input  wire [1:0]  ord_type,       // `OT_MKT for prototype 1
    input  wire [13:0] ord_qty,        // Matthew's 0..9999; accepted 1..255, else RJ_BAD_QTY
    input  wire [15:0] ord_trig,       // LMT/STP only
    // ledger (Tricia), read-only
    input  wire [31:0] cash,
    input  wire [9:0]  pos0,
    input  wire [9:0]  pos1,
    input  wire [9:0]  pos2,
    input  wire [9:0]  pos3,
    input  wire        ledger_busy,
    // pixel being drawn on the right OLED (top)
    input  wire [6:0]  xR,
    input  wire [5:0]  yR,
    // fill bus (Tricia, Matthew)
    output wire        fill,
    output wire [1:0]  fill_stock,
    output wire        fill_side,
    output wire [7:0]  fill_qty,
    output wire [15:0] fill_price,
    output wire [15:0] fill_fee,
    // reject (Matthew)
    output wire        reject,
    output wire [2:0]  reject_code,
    output wire [3:0]  pending_count,
    // Ticket page pixel (Matthew)
    output wire [15:0] ticket_pixel
);
    // ------------------------------------------------------------ decode Matthew's signals
    wire game_live       = (game_state == `GS_PLAYING);
    wire ticket_active   = (page_R == `PG_R_TICKET);
    wire key_center      = btn_pulse[`BTN_C];
    wire key_up          = btn_pulse[`BTN_U];
    wire key_left        = btn_pulse[`BTN_L];
    wire key_right       = btn_pulse[`BTN_R];
    wire key_down        = btn_pulse[`BTN_D];
    // out-of-range quantities become 0, which order_validate rejects as RJ_BAD_QTY
    wire [7:0] ord_qty8  = (ord_qty == 14'd0 || ord_qty > 14'd255) ? 8'd0 : ord_qty[7:0];

    // ------------------------------------------------------------ the ticket's stock
    wire [1:0]  e_stock;
    reg  [15:0] tk_price;
    always @* begin
        case (e_stock)
            2'd0:    tk_price = price0;
            2'd1:    tk_price = price1;
            2'd2:    tk_price = price2;
            default: tk_price = price3;
        endcase
    end

    wire [15:0] tk_bid, tk_ask;
    spread_calc #(.SPREAD(SPREAD)) u_tk_spread (.price(tk_price), .bid(tk_bid), .ask(tk_ask));

    // ------------------------------------------------------------ order entry
    wire        e_side;
    wire [1:0]  e_type;
    wire [7:0]  e_qty;
    wire [15:0] e_trig;
    wire [1:0]  e_brk;
    wire [2:0]  e_ord_sel;
    wire [2:0]  e_focus;
    wire        submit_req;
    wire [1:0]  sub_stock;
    wire        sub_side;
    wire [1:0]  sub_type;
    wire [7:0]  sub_qty;
    wire [15:0] sub_trig;
    wire [1:0]  sub_brk;
    wire        cancel_req;
    wire [2:0]  cancel_idx;

    order_entry #(.QTY_INIT(QTY_INIT), .TRIG_STEP(TRIG_STEP)) u_entry (
        .clk(clk), .sys_reset(sys_reset), .ticket_active(ticket_active),
        .sel_stock(sel_stock), .tk_price(tk_price),
        .key_up(key_up), .key_down(key_down), .key_left(key_left),
        .key_right(key_right), .key_center(key_center),
        .ext_load(ord_req), .ext_side(ord_side), .ext_type(ord_type),
        .ext_qty(ord_qty8), .ext_trig(ord_trig),
        .stock(e_stock), .side(e_side), .otype(e_type), .qty(e_qty), .trig(e_trig),
        .brk(e_brk), .ord_sel(e_ord_sel), .focus(e_focus),
        .submit_req(submit_req), .sub_stock(sub_stock), .sub_side(sub_side),
        .sub_type(sub_type), .sub_qty(sub_qty), .sub_trig(sub_trig), .sub_brk(sub_brk),
        .cancel_req(cancel_req), .cancel_idx(cancel_idx)
    );

    // ------------------------------------------------------------ book <-> engine
    wire        book_full;
    wire [3:0]  free_cnt;
    wire        trq, trq_ack;
    wire [2:0]  trq_slot;
    wire [1:0]  trq_stock;
    wire        trq_side;
    wire [1:0]  trq_type;
    wire [7:0]  trq_qty;
    wire [15:0] trq_px;
    wire [1:0]  trq_brk;
    wire        ins;
    wire [1:0]  ins_stock;
    wire        ins_side;
    wire [1:0]  ins_type;
    wire [7:0]  ins_qty;
    wire [15:0] ins_trig;
    wire [1:0]  ins_brk;
    wire        ins_pair;
    wire [1:0]  pair_stock;
    wire [7:0]  pair_qty;
    wire [15:0] pair_sl, pair_tp;
    wire        placed;
    wire [7:0]   bk_valid, bk_side, bk_leg;
    wire [15:0]  bk_stock, bk_type;
    wire [63:0]  bk_qty;
    wire [127:0] bk_trig;

    exec_engine #(.SPREAD(SPREAD), .FEE(FEE), .POS_MAX(POS_MAX)) u_exec (
        .clk(clk), .sys_reset(sys_reset), .game_live(game_live),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy),
        .submit_req(submit_req), .sub_stock(sub_stock), .sub_side(sub_side),
        .sub_type(sub_type), .sub_qty(sub_qty), .sub_trig(sub_trig), .sub_brk(sub_brk),
        .book_full(book_full), .free_cnt(free_cnt),
        .trq(trq), .trq_stock(trq_stock), .trq_side(trq_side), .trq_type(trq_type),
        .trq_qty(trq_qty), .trq_px(trq_px), .trq_brk(trq_brk), .trq_ack(trq_ack),
        .ins(ins), .ins_stock(ins_stock), .ins_side(ins_side), .ins_type(ins_type),
        .ins_qty(ins_qty), .ins_trig(ins_trig), .ins_brk(ins_brk), .placed(placed),
        .ins_pair(ins_pair), .pair_stock(pair_stock), .pair_qty(pair_qty),
        .pair_sl(pair_sl), .pair_tp(pair_tp),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .reject(reject), .reject_code(reject_code)
    );

    // rd_* is for testbenches; the ORDERS view reads every slot through all_*
    order_book #(.SPREAD(SPREAD)) u_book (
        .clk(clk), .sys_reset(sys_reset), .tick(tick), .scan_en(game_live),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .ins(ins), .ins_stock(ins_stock), .ins_side(ins_side), .ins_type(ins_type),
        .ins_qty(ins_qty), .ins_trig(ins_trig), .ins_brk(ins_brk),
        .ins_pair(ins_pair), .pair_stock(pair_stock), .pair_qty(pair_qty),
        .pair_sl(pair_sl), .pair_tp(pair_tp),
        .cancel(cancel_req), .cancel_idx(cancel_idx),
        .full(book_full), .count(pending_count), .free_cnt(free_cnt),
        .trq(trq), .trq_slot(trq_slot), .trq_stock(trq_stock), .trq_side(trq_side),
        .trq_type(trq_type), .trq_qty(trq_qty), .trq_px(trq_px), .trq_brk(trq_brk),
        .trq_ack(trq_ack),
        .rd_idx(3'd0), .rd_valid(), .rd_stock(), .rd_side(), .rd_type(),
        .rd_qty(), .rd_trig(),
        .all_valid(bk_valid), .all_side(bk_side), .all_stock(bk_stock), .all_type(bk_type),
        .all_qty(bk_qty), .all_trig(bk_trig), .all_leg(bk_leg)
    );

    // ------------------------------------------------------------ screen
    ticket_screen #(.REJ_SHOW_CYCLES(REJ_SHOW_CYCLES), .FLIP_180(TICKET_FLIP_180)) u_screen (
        .clk(clk), .sys_reset(sys_reset), .pix_x(xR), .pix_y(yR),
        .stock(e_stock), .bid(tk_bid), .ask(tk_ask),
        .side(e_side), .otype(e_type), .qty(e_qty), .trig(e_trig), .brk(e_brk),
        .ord_sel(e_ord_sel), .focus(e_focus), .pending_count(pending_count),
        .bk_valid(bk_valid), .bk_side(bk_side), .bk_stock(bk_stock), .bk_type(bk_type),
        .bk_qty(bk_qty), .bk_trig(bk_trig), .bk_leg(bk_leg),
        .fill(fill), .fill_side(fill_side), .fill_qty(fill_qty), .fill_price(fill_price),
        .placed(placed), .placed_side(ins_side), .placed_type(ins_type),
        .placed_qty(ins_qty), .placed_trig(ins_trig),
        .reject(reject), .reject_code(reject_code),
        .ticket_pix(ticket_pixel)
    );
endmodule

`default_nettype wire
