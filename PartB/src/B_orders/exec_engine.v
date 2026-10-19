`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// exec_engine: the single arbiter between
//   - submits from order_entry (priority), held in a one-deep buffer, and
//   - trigger requests from order_book.
// Every job goes IDLE -> CHECK -> EVAL -> POST -> IDLE:
//   CHECK  wait for !ledger_busy (C has settled the last fill), then latch the
//          execution price: ask for BUY, bid for SELL. A book job keeps the
//          price the book latched when the trigger was seen.
//   EVAL   run order_validate on the latched job, then exactly one of:
//            MKT submit ok   -> pulse fill
//            LMT/STP submit  -> pulse ins (into order_book) and placed
//            book job ok     -> pulse fill, ack the book
//            any failure     -> pulse reject (book jobs report RJ_TRIG_FAIL
//                               and are acked, so the slot is cleared)
//   POST   one dead clock, so C can raise ledger_busy before the next CHECK.
// [TEAM] C must assert ledger_busy on the clock after fill, or earlier.
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
    // trigger request from order_book
    input  wire        book_full,
    input  wire        trq,
    input  wire [1:0]  trq_stock,
    input  wire        trq_side,
    input  wire [1:0]  trq_type,
    input  wire [7:0]  trq_qty,
    input  wire [15:0] trq_px,
    output reg         trq_ack,
    // insert into order_book (fields valid while ins is high)
    output reg         ins,
    output wire [1:0]  ins_stock,
    output wire        ins_side,
    output wire [1:0]  ins_type,
    output wire [7:0]  ins_qty,
    output wire [15:0] ins_trig,
    output reg         placed,         // a pending order was accepted (for the screen)
    // fill bus to C and D (fields hold their value after the pulse)
    output reg         fill,
    output reg  [1:0]  fill_stock,
    output reg         fill_side,
    output reg  [7:0]  fill_qty,
    output reg  [15:0] fill_price,
    output reg  [15:0] fill_fee,
    // reject to D
    output reg         reject,
    output reg  [2:0]  reject_code
);
    localparam ST_IDLE  = 2'd0,
               ST_CHECK = 2'd1,
               ST_EVAL  = 2'd2,
               ST_POST  = 2'd3;

    localparam [15:0] FEE16 = FEE;

    reg [1:0] state;

    // one-deep buffer for a submit pulse that arrives while a job is running
    reg        hold_v;
    reg [1:0]  hold_stock;
    reg        hold_side;
    reg [1:0]  hold_type;
    reg [7:0]  hold_qty;
    reg [15:0] hold_trig;

    // the job being worked on
    reg        cand_book;      // 1 = triggered book order, 0 = new submit
    reg [1:0]  cand_stock;
    reg        cand_side;
    reg [1:0]  cand_type;
    reg [7:0]  cand_qty;
    reg [15:0] cand_trig;
    reg [15:0] cand_px;        // execution price

    assign ins_stock = cand_stock;
    assign ins_side  = cand_side;
    assign ins_type  = cand_type;
    assign ins_qty   = cand_qty;
    assign ins_trig  = cand_trig;

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
            cand_book   <= 1'b0;
            cand_stock  <= 2'd0;
            cand_side   <= 1'b0;
            cand_type   <= 2'd0;
            cand_qty    <= 8'd0;
            cand_trig   <= 16'd0;
            cand_px     <= 16'd0;
            trq_ack     <= 1'b0;
            ins         <= 1'b0;
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
            ins     <= 1'b0;
            placed  <= 1'b0;
            fill    <= 1'b0;
            reject  <= 1'b0;

            // a submit that IDLE cannot take this clock waits in the buffer
            if (submit_req && !hold_v && state != ST_IDLE) begin
                hold_v     <= 1'b1;
                hold_stock <= sub_stock;
                hold_side  <= sub_side;
                hold_type  <= sub_type;
                hold_qty   <= sub_qty;
                hold_trig  <= sub_trig;
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
                        state      <= ST_CHECK;
                    end else if (submit_req) begin
                        cand_book  <= 1'b0;
                        cand_stock <= sub_stock;
                        cand_side  <= sub_side;
                        cand_type  <= sub_type;
                        cand_qty   <= sub_qty;
                        cand_trig  <= sub_trig;
                        state      <= ST_CHECK;
                    end else if (trq) begin
                        cand_book  <= 1'b1;
                        cand_stock <= trq_stock;
                        cand_side  <= trq_side;
                        cand_type  <= trq_type;
                        cand_qty   <= trq_qty;
                        cand_trig  <= trq_px;
                        cand_px    <= trq_px;
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

                default: begin   // ST_POST
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
