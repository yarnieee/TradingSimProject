`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// B_order_top: Part B (order and execution engine + Order Ticket page).
// This is what the team top level instantiates. Ports follow the Module I/O
// map in the team plan doc; encodings of the D bus are in trading_defs.vh.
//
//   order_entry --submit--> exec_engine --fill--> C, D
//                              ^   |  \--reject--> D
//                    trq/ack   |   v ins
//                            order_book
//   ticket_screen draws the page from all of the above.
//
// B never writes cash or positions; it only reads C's ledger.
module B_order_top #(
    parameter SPREAD          = 5,             // cents per side [ASSUMPTION]
    parameter FEE             = 100,           // cents per execution [ASSUMPTION]
    parameter POS_MAX         = 1023,
    parameter QTY_INIT        = 1,             // [ASSUMPTION]
    parameter TRIG_STEP       = 5,             // cents per notch [ASSUMPTION]
    parameter REJ_SHOW_CYCLES = 200_000_000    // 2 s at 100 MHz
) (
    input  wire        clk,
    input  wire        sys_reset,
    input  wire [1:0]  game_state,     // orders only while GS_PLAYING
    // price bus (A)
    input  wire [15:0] price0,
    input  wire [15:0] price1,
    input  wire [15:0] price2,
    input  wire [15:0] price3,
    input  wire        tick,
    // UI event bus (D)
    input  wire [1:0]  sel_stock,
    input  wire        page_R,         // active right-OLED page; B acts only on PG_R_TICKET (tie 0 until D has pages)
    input  wire [4:0]  btn_pulse,      // debounced 1-clock pulses, bits per BTN_* defines; B's only UI input
    // ledger (C), read-only
    input  wire [31:0] cash,
    input  wire [9:0]  pos0,
    input  wire [9:0]  pos1,
    input  wire [9:0]  pos2,
    input  wire [9:0]  pos3,
    input  wire        ledger_busy,
    // pixel being drawn on the right OLED (top)
    input  wire [6:0]  xR,
    input  wire [5:0]  yR,
    // fill bus (C, D)
    output wire        fill,
    output wire [1:0]  fill_stock,
    output wire        fill_side,
    output wire [7:0]  fill_qty,
    output wire [15:0] fill_price,
    output wire [15:0] fill_fee,
    // reject (D)
    output wire        reject,
    output wire [2:0]  reject_code,
    output wire [3:0]  pending_count,
    // Ticket page pixel (D)
    output wire [15:0] ticket_pixel
);
    // ------------------------------------------------------------ decode D's bus
    wire game_live       = (game_state == `GS_PLAYING);
    wire ticket_active   = (page_R == `PG_R_TICKET);
    wire key_center      = btn_pulse[`BTN_C];
    wire key_up          = btn_pulse[`BTN_U];
    wire key_left        = btn_pulse[`BTN_L];
    wire key_right       = btn_pulse[`BTN_R];
    wire key_down        = btn_pulse[`BTN_D];

    // ------------------------------------------------------------ selected stock
    reg [15:0] sel_price;
    always @* begin
        case (sel_stock)
            2'd0:    sel_price = price0;
            2'd1:    sel_price = price1;
            2'd2:    sel_price = price2;
            default: sel_price = price3;
        endcase
    end

    wire [15:0] sel_bid, sel_ask;
    spread_calc #(.SPREAD(SPREAD)) u_sel_spread (.price(sel_price), .bid(sel_bid), .ask(sel_ask));

    // ------------------------------------------------------------ order entry
    wire        e_side;
    wire [1:0]  e_type;
    wire [7:0]  e_qty;
    wire [15:0] e_trig;
    wire [1:0]  e_focus;
    wire        submit_req;
    wire [1:0]  sub_stock;
    wire        sub_side;
    wire [1:0]  sub_type;
    wire [7:0]  sub_qty;
    wire [15:0] sub_trig;

    order_entry #(.QTY_INIT(QTY_INIT), .TRIG_STEP(TRIG_STEP)) u_entry (
        .clk(clk), .sys_reset(sys_reset), .ticket_active(ticket_active),
        .sel_stock(sel_stock), .sel_price(sel_price),
        .key_up(key_up), .key_down(key_down), .key_left(key_left),
        .key_right(key_right), .key_center(key_center),
        .side(e_side), .otype(e_type), .qty(e_qty), .trig(e_trig), .focus(e_focus),
        .submit_req(submit_req), .sub_stock(sub_stock), .sub_side(sub_side),
        .sub_type(sub_type), .sub_qty(sub_qty), .sub_trig(sub_trig)
    );

    // ------------------------------------------------------------ book <-> engine
    wire        book_full;
    wire        trq, trq_ack;
    wire [2:0]  trq_slot;
    wire [1:0]  trq_stock;
    wire        trq_side;
    wire [1:0]  trq_type;
    wire [7:0]  trq_qty;
    wire [15:0] trq_px;
    wire        ins;
    wire [1:0]  ins_stock;
    wire        ins_side;
    wire [1:0]  ins_type;
    wire [7:0]  ins_qty;
    wire [15:0] ins_trig;
    wire        placed;

    exec_engine #(.SPREAD(SPREAD), .FEE(FEE), .POS_MAX(POS_MAX)) u_exec (
        .clk(clk), .sys_reset(sys_reset), .game_live(game_live),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy),
        .submit_req(submit_req), .sub_stock(sub_stock), .sub_side(sub_side),
        .sub_type(sub_type), .sub_qty(sub_qty), .sub_trig(sub_trig),
        .book_full(book_full),
        .trq(trq), .trq_stock(trq_stock), .trq_side(trq_side), .trq_type(trq_type),
        .trq_qty(trq_qty), .trq_px(trq_px), .trq_ack(trq_ack),
        .ins(ins), .ins_stock(ins_stock), .ins_side(ins_side), .ins_type(ins_type),
        .ins_qty(ins_qty), .ins_trig(ins_trig), .placed(placed),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .reject(reject), .reject_code(reject_code)
    );

    // rd_* left unconnected until the Phase 3 pending list uses them
    order_book #(.SPREAD(SPREAD)) u_book (
        .clk(clk), .sys_reset(sys_reset), .tick(tick), .scan_en(game_live),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .ins(ins), .ins_stock(ins_stock), .ins_side(ins_side), .ins_type(ins_type),
        .ins_qty(ins_qty), .ins_trig(ins_trig),
        .cancel(1'b0), .cancel_idx(3'd0),          // Phase 3
        .full(book_full), .count(pending_count),
        .trq(trq), .trq_slot(trq_slot), .trq_stock(trq_stock), .trq_side(trq_side),
        .trq_type(trq_type), .trq_qty(trq_qty), .trq_px(trq_px), .trq_ack(trq_ack),
        .rd_idx(3'd0), .rd_valid(), .rd_stock(), .rd_side(), .rd_type(),
        .rd_qty(), .rd_trig()
    );

    // ------------------------------------------------------------ screen
    ticket_screen #(.REJ_SHOW_CYCLES(REJ_SHOW_CYCLES)) u_screen (
        .clk(clk), .sys_reset(sys_reset), .pix_x(xR), .pix_y(yR),
        .sel_stock(sel_stock), .bid(sel_bid), .ask(sel_ask),
        .side(e_side), .otype(e_type), .qty(e_qty), .trig(e_trig), .focus(e_focus),
        .pending_count(pending_count),
        .fill(fill), .fill_side(fill_side), .fill_qty(fill_qty), .fill_price(fill_price),
        .placed(placed), .placed_side(ins_side), .placed_type(ins_type),
        .placed_qty(ins_qty), .placed_trig(ins_trig),
        .reject(reject), .reject_code(reject_code),
        .ticket_pix(ticket_pixel)
    );
endmodule

`default_nettype wire
