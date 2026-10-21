`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// exec_engine: the single arbiter between
//   - submits from order_entry (priority), held in a one-deep buffer, and
//   - trigger requests from order_book.
// Every job goes IDLE -> CHECK -> EVAL -> POST -> (PAIR) -> IDLE:
//   CHECK  wait for !ledger_busy (Tricia's ledger has settled the last fill), then latch the
//          execution price: ask for BUY, bid for SELL. A book job keeps the
//          price the book latched when the trigger was seen.
//   EVAL   run order_validate on the latched job, then exactly one of:
//            MKT submit ok   -> pulse fill
//            LMT/STP submit  -> pulse ins (into order_book) and placed
//            book job ok     -> pulse fill, ack the book
//            any failure     -> pulse reject (book jobs report RJ_TRIG_FAIL
//                               and are acked, so the slot is cleared)
//   POST   one dead clock, so the ledger can raise ledger_busy before the next CHECK.
//   PAIR   only after a BUY fill with SL/TP on: place the stop-loss and
//          take-profit (ins_pair) at fill price -/+ 2, 5 or 10%, or report
//          RJ_BOOK_FULL if the book has no room for them (the buy stands).
//          By now a triggered parent has left the book, so its slot can be reused.
// [TEAM] Tricia's ledger must assert ledger_busy on the clock after fill, or earlier.
module exec_engine #(
    parameter SPREAD  = 5,
    parameter FEE     = 100,
    parameter POS_MAX = 1023
) (
    input  wire        clk,
    input  wire        sys_reset,
    input  wire        game_live,
    input  wire [15:0] price0,
    input  wire [15:0] price1,
    input  wire [15:0] price2,
    input  wire [15:0] price3,
    input  wire [31:0] cash,
    input  wire [9:0]  pos0,
    input  wire [9:0]  pos1,
    input  wire [9:0]  pos2,
    input  wire [9:0]  pos3,
    input  wire        ledger_busy,
    // submit from order_entry
    input  wire        submit_req,
    input  wire [1:0]  sub_stock,
    input  wire        sub_side,
    input  wire [1:0]  sub_type,
    input  wire [7:0]  sub_qty,
    input  wire [15:0] sub_trig,
    input  wire [1:0]  sub_brk,        // SL/TP setting (`BRK_*)
    // trigger request from order_book
    input  wire        book_full,
    input  wire [3:0]  free_cnt,
    input  wire        trq,
    input  wire [1:0]  trq_stock,
    input  wire        trq_side,
    input  wire [1:0]  trq_type,
    input  wire [7:0]  trq_qty,
    input  wire [15:0] trq_px,
    input  wire [1:0]  trq_brk,
    output reg         trq_ack,
    // insert into order_book (fields valid while ins is high)
    output reg         ins,
    output wire [1:0]  ins_stock,
    output wire        ins_side,
    output wire [1:0]  ins_type,
    output wire [7:0]  ins_qty,
    output wire [15:0] ins_trig,
    output wire [1:0]  ins_brk,
    output reg         placed,         // a pending order was accepted (for the screen)
    // stop-loss / take-profit pair into order_book (fields valid while ins_pair is high)
    output reg         ins_pair,
    output reg  [1:0]  pair_stock,
    output reg  [7:0]  pair_qty,
    output reg  [15:0] pair_sl,
    output reg  [15:0] pair_tp,
    // fill bus to Tricia and Matthew (fields hold their value after the pulse)
    output reg         fill,
    output reg  [1:0]  fill_stock,
    output reg         fill_side,
    output reg  [7:0]  fill_qty,
    output reg  [15:0] fill_price,
    output reg  [15:0] fill_fee,
    // reject to Matthew
    output reg         reject,
    output reg  [2:0]  reject_code
);
    localparam ST_IDLE  = 3'd0,
               ST_CHECK = 3'd1,
               ST_EVAL  = 3'd2,
               ST_POST  = 3'd3,
               ST_PAIR  = 3'd4;

    localparam [15:0] FEE16 = FEE;

    reg [2:0] state;
    reg       pair_pend;       // the job was a BUY fill with SL/TP on

    // one-deep buffer for a submit pulse that arrives while a job is running
    reg        hold_v;
    reg [1:0]  hold_stock;
    reg        hold_side;
    reg [1:0]  hold_type;
    reg [7:0]  hold_qty;
    reg [15:0] hold_trig;
    reg [1:0]  hold_brk;

    // the job being worked on
    reg        cand_book;      // 1 = triggered book order, 0 = new submit
    reg [1:0]  cand_stock;
    reg        cand_side;
    reg [1:0]  cand_type;
    reg [7:0]  cand_qty;
    reg [15:0] cand_trig;
    reg [15:0] cand_px;        // execution price
    reg [1:0]  cand_brk;

    assign ins_stock = cand_stock;
    assign ins_side  = cand_side;
    assign ins_type  = cand_type;
    assign ins_qty   = cand_qty;
    assign ins_trig  = cand_trig;
    assign ins_brk   = cand_brk;

    // ------------------------------------------------------------ SL/TP prices
    // distance = fill price x 2, 5 or 10%, as px * (pct * 656) >> 16 (656/65536 is
    // 1.001%, so the distance is within 1 cent for prices up to $100). One multiply.
    reg [12:0] brk_k;
    always @* begin
        case (cand_brk)
            `BRK_2:  brk_k = 13'd1312;
            `BRK_5:  brk_k = 13'd3280;
            `BRK_10: brk_k = 13'd6560;
            default: brk_k = 13'd0;
        endcase
    end
    wire [28:0] brk_prod = cand_px * brk_k;
    wire [15:0] brk_off  = brk_prod[28:16];
    wire [16:0] tp_sum   = {1'b0, cand_px} + {1'b0, brk_off};
    wire [15:0] sl_px    = (brk_off >= cand_px) ? 16'd1 : cand_px - brk_off;   // floor at 1 cent
    wire [15:0] tp_px    = tp_sum[16] ? 16'hFFFF : tp_sum[15:0];

    // live bid/ask of the job's stock
    reg [15:0] cand_mid;
    always @* begin
        case (cand_stock)
            2'd0:    cand_mid = price0;
            2'd1:    cand_mid = price1;
            2'd2:    cand_mid = price2;
            default: cand_mid = price3;
        endcase
    end

    wire [15:0] cand_bid, cand_ask;
    spread_calc #(.SPREAD(SPREAD)) u_spread (.price(cand_mid), .bid(cand_bid), .ask(cand_ask));

    wire       v_ok;
    wire [2:0] v_code;
    order_validate #(.FEE(FEE), .POS_MAX(POS_MAX)) u_validate (
        .game_live   (game_live),
        .mkt_open    (cand_mid != 16'd0),
        .retest      (cand_book),
        .stock       (cand_stock),
        .side        (cand_side),
        .otype       (cand_type),
        .qty         (cand_qty),
        .trig        (cand_trig),
        .px_exec     (cand_px),
        .cash        (cash),
        .pos0        (pos0),
        .pos1        (pos1),
        .pos2        (pos2),
        .pos3        (pos3),
        .book_full   (book_full),
        .brk         (cand_brk),
        .free_cnt    (free_cnt),
        .ok          (v_ok),
        .reject_code (v_code)
    );

    always @(posedge clk) begin
        if (sys_reset) begin
            state       <= ST_IDLE;
            hold_v      <= 1'b0;
            hold_stock  <= 2'd0;
            hold_side   <= 1'b0;
            hold_type   <= 2'd0;
            hold_qty    <= 8'd0;
            hold_trig   <= 16'd0;
            hold_brk    <= `BRK_OFF;
            cand_book   <= 1'b0;
            cand_stock  <= 2'd0;
            cand_side   <= 1'b0;
            cand_type   <= 2'd0;
            cand_qty    <= 8'd0;
            cand_trig   <= 16'd0;
            cand_px     <= 16'd0;
            cand_brk    <= `BRK_OFF;
            pair_pend   <= 1'b0;
            trq_ack     <= 1'b0;
            ins         <= 1'b0;
            ins_pair    <= 1'b0;
            pair_stock  <= 2'd0;
            pair_qty    <= 8'd0;
            pair_sl     <= 16'd0;
            pair_tp     <= 16'd0;
            placed      <= 1'b0;
            fill        <= 1'b0;
            fill_stock  <= 2'd0;
            fill_side   <= 1'b0;
            fill_qty    <= 8'd0;
            fill_price  <= 16'd0;
            fill_fee    <= 16'd0;
            reject      <= 1'b0;
            reject_code <= `RJ_NONE;
        end else begin
            // pulses default low
            trq_ack <= 1'b0;
            ins      <= 1'b0;
            ins_pair <= 1'b0;
            placed   <= 1'b0;
            fill     <= 1'b0;
            reject   <= 1'b0;

            // a submit that IDLE cannot take this clock waits in the buffer
            if (submit_req && !hold_v && state != ST_IDLE) begin
                hold_v     <= 1'b1;
                hold_stock <= sub_stock;
                hold_side  <= sub_side;
                hold_type  <= sub_type;
                hold_qty   <= sub_qty;
                hold_trig  <= sub_trig;
                hold_brk   <= sub_brk;
            end

            case (state)
                ST_IDLE: begin
                    if (hold_v) begin
                        hold_v     <= 1'b0;
                        cand_book  <= 1'b0;
                        cand_stock <= hold_stock;
                        cand_side  <= hold_side;
                        cand_type  <= hold_type;
                        cand_qty   <= hold_qty;
                        cand_trig  <= hold_trig;
                        cand_brk   <= hold_brk;
                        state      <= ST_CHECK;
                    end else if (submit_req) begin
                        cand_book  <= 1'b0;
                        cand_stock <= sub_stock;
                        cand_side  <= sub_side;
                        cand_type  <= sub_type;
                        cand_qty   <= sub_qty;
                        cand_trig  <= sub_trig;
                        cand_brk   <= sub_brk;
                        state      <= ST_CHECK;
                    end else if (trq) begin
                        cand_book  <= 1'b1;
                        cand_stock <= trq_stock;
                        cand_side  <= trq_side;
                        cand_type  <= trq_type;
                        cand_qty   <= trq_qty;
                        cand_trig  <= trq_px;
                        cand_px    <= trq_px;
                        cand_brk   <= trq_brk;
                        state      <= ST_CHECK;
                    end
                end

                ST_CHECK: begin
                    if (!ledger_busy) begin
                        if (!cand_book)
                            cand_px <= (cand_side == `SIDE_SELL) ? cand_bid : cand_ask;
                        state <= ST_EVAL;
                    end
                end

                ST_EVAL: begin
                    if (v_ok) begin
                        if (cand_book || cand_type == `OT_MKT) begin
                            fill       <= 1'b1;
                            fill_stock <= cand_stock;
                            fill_side  <= cand_side;
                            fill_qty   <= cand_qty;
                            fill_price <= cand_px;
                            fill_fee   <= FEE16;
                            pair_pend  <= (cand_side == `SIDE_BUY) && (cand_brk != `BRK_OFF);
                        end else begin
                            ins    <= 1'b1;
                            placed <= 1'b1;
                        end
                    end else begin
                        reject      <= 1'b1;
                        reject_code <= cand_book ? `RJ_TRIG_FAIL : v_code;
                    end
                    if (cand_book)
                        trq_ack <= 1'b1;
                    state <= ST_POST;
                end

                ST_POST: begin
                    state <= pair_pend ? ST_PAIR : ST_IDLE;
                end

                default: begin   // ST_PAIR
                    if (free_cnt >= 4'd2) begin
                        ins_pair   <= 1'b1;
                        pair_stock <= cand_stock;
                        pair_qty   <= cand_qty;
                        pair_sl    <= sl_px;
                        pair_tp    <= tp_px;
                    end else begin
                        reject      <= 1'b1;
                        reject_code <= `RJ_BOOK_FULL;
                    end
                    pair_pend <= 1'b0;
                    state     <= ST_IDLE;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
