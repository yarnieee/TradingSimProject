`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// order_book: 8-slot pending book for LMT and STP orders.
//
// Insert : into the lowest free slot (exec_engine has already validated it).
//          A pending BUY keeps its SL/TP setting (ins_brk) and hands it back
//          with its trigger request, so exec_engine can place the pair when it fills.
// Pair   : ins_pair places a stop-loss and a take-profit for a filled BUY in
//          the two lowest free slots, linked to each other:
//            STP SELL qty @ pair_sl    (the stop-loss)
//            LMT SELL qty @ pair_tp    (the take-profit)
//          Ignored if fewer than two slots are free (exec_engine checks first).
// Linked : when either leg leaves the book (filled, failed, or cancelled) the
//          other leg is removed too: one cancels the other.
// Cancel : by slot index, from the ORDERS view. Ignored for an empty slot, and
//          for the slot that is waiting on exec_engine (it is leaving anyway).
// Scan   : after each tick the FSM walks the slots one per clock with ONE
//          shared comparator path. On a hit it raises trq with the slot's
//          fields and the fill price, waits for trq_ack, clears the slot and
//          carries on. A tick that lands mid-scan sets rescan, so slots
//          already passed are checked against the newest prices too.
//          [ASSUMPTION] This time-sharing is the resource optimisation for the report.
//
// Trigger rules (bid/ask from spread_calc):
//   LMT BUY  ask <= trig   fills at ask
//   LMT SELL bid >= trig   fills at bid
//   STP BUY  ask >= trig   fills at ask (can be worse on a gap)
//   STP SELL bid <= trig   fills at bid (can be worse on a gap)
//
// ins and ins_pair never arrive on the same clock: exec_engine pulses them
// from different states.
module order_book #(
    parameter SPREAD = 5
) (
    input  wire        clk,
    input  wire        sys_reset,
    input  wire        tick,
    input  wire        scan_en,        // game_live: no triggering outside PLAYING
    input  wire [15:0] price0,
    input  wire [15:0] price1,
    input  wire [15:0] price2,
    input  wire [15:0] price3,
    // insert (from exec_engine)
    input  wire        ins,
    input  wire [1:0]  ins_stock,
    input  wire        ins_side,
    input  wire [1:0]  ins_type,
    input  wire [7:0]  ins_qty,
    input  wire [15:0] ins_trig,
    input  wire [1:0]  ins_brk,
    // stop-loss / take-profit pair (from exec_engine)
    input  wire        ins_pair,
    input  wire [1:0]  pair_stock,
    input  wire [7:0]  pair_qty,
    input  wire [15:0] pair_sl,
    input  wire [15:0] pair_tp,
    // cancel (ORDERS view)
    input  wire        cancel,
    input  wire [2:0]  cancel_idx,
    // status
    output wire        full,
    output wire [3:0]  count,
    output wire [3:0]  free_cnt,
    // trigger request to exec_engine
    output reg         trq,
    output reg  [2:0]  trq_slot,
    output reg  [1:0]  trq_stock,
    output reg         trq_side,
    output reg  [1:0]  trq_type,
    output reg  [7:0]  trq_qty,
    output reg  [15:0] trq_px,
    output reg  [1:0]  trq_brk,
    input  wire        trq_ack,
    // read port (testbenches)
    input  wire [2:0]  rd_idx,
    output wire        rd_valid,
    output wire [1:0]  rd_stock,
    output wire        rd_side,
    output wire [1:0]  rd_type,
    output wire [7:0]  rd_qty,
    output wire [15:0] rd_trig,
    // every slot at once (ORDERS view); slot k is bits [k], [2k+1:2k], [8k+7:8k], [16k+15:16k]
    output wire [7:0]   all_valid,
    output wire [7:0]   all_side,
    output wire [15:0]  all_stock,
    output wire [15:0]  all_type,
    output wire [63:0]  all_qty,
    output wire [127:0] all_trig,
    output wire [7:0]   all_leg        // 1: an SL/TP leg (STP = stop-loss, LMT = take-profit)
);
    localparam S_IDLE = 2'd0,
               S_SCAN = 2'd1,
               S_WAIT = 2'd2;

    // ------------------------------------------------------------ slots
    reg [7:0]  valid;
    reg [7:0]  s_side;
    reg [1:0]  s_stock [0:7];
    reg [1:0]  s_type  [0:7];
    reg [7:0]  s_qty   [0:7];
    reg [15:0] s_trig  [0:7];
    reg [1:0]  s_brk   [0:7];      // SL/TP setting of a pending BUY
    reg [7:0]  lnk_v;              // slot is one leg of an SL/TP pair
    reg [2:0]  s_lnk   [0:7];      // the other leg's slot

    assign count    = valid[0] + valid[1] + valid[2] + valid[3]
                    + valid[4] + valid[5] + valid[6] + valid[7];
    assign full     = &valid;
    assign free_cnt = 4'd8 - count;

    assign rd_valid = valid[rd_idx];
    assign rd_stock = s_stock[rd_idx];
    assign rd_side  = s_side[rd_idx];
    assign rd_type  = s_type[rd_idx];
    assign rd_qty   = s_qty[rd_idx];
    assign rd_trig  = s_trig[rd_idx];

    assign all_valid = valid;
    assign all_side  = s_side;
    assign all_leg   = lnk_v & valid;
    genvar gk;
    generate
        for (gk = 0; gk < 8; gk = gk + 1) begin : g_all
            assign all_stock[2*gk+1:2*gk]   = s_stock[gk];
            assign all_type[2*gk+1:2*gk]    = s_type[gk];
            assign all_qty[8*gk+7:8*gk]     = s_qty[gk];
            assign all_trig[16*gk+15:16*gk] = s_trig[gk];
        end
    endgenerate

    // lowest and second-lowest free slots
    reg [2:0] free_idx, free_idx2;
    integer i;
    always @* begin
        free_idx = 3'd0;
        for (i = 7; i >= 0; i = i - 1)
            if (!valid[i]) free_idx = i;
        free_idx2 = 3'd0;
        for (i = 7; i >= 0; i = i - 1)
            if (!valid[i] && i != free_idx) free_idx2 = i;
    end

    // ------------------------------------------------------------ scan path
    reg [1:0] state;
    reg [2:0] idx;
    reg       rescan;

    wire [1:0]  sc_stock = s_stock[idx];
    wire        sc_side  = s_side[idx];
    wire [1:0]  sc_type  = s_type[idx];
    wire [15:0] sc_trig  = s_trig[idx];

    reg [15:0] sc_mid;
    always @* begin
        case (sc_stock)
            2'd0:    sc_mid = price0;
            2'd1:    sc_mid = price1;
            2'd2:    sc_mid = price2;
            default: sc_mid = price3;
        endcase
    end

    wire [15:0] sc_bid, sc_ask;
    spread_calc #(.SPREAD(SPREAD)) u_spread (.price(sc_mid), .bid(sc_bid), .ask(sc_ask));

    reg sc_cond;
    always @* begin
        case ({sc_type, sc_side})
            {`OT_LMT, `SIDE_BUY }: sc_cond = (sc_ask <= sc_trig);
            {`OT_LMT, `SIDE_SELL}: sc_cond = (sc_bid >= sc_trig);
            {`OT_STP, `SIDE_BUY }: sc_cond = (sc_ask >= sc_trig);
            {`OT_STP, `SIDE_SELL}: sc_cond = (sc_bid <= sc_trig);
            default:               sc_cond = 1'b0;
        endcase
    end
    wire sc_hit = valid[idx] && sc_cond && (sc_mid != 16'd0);   // no price: no trigger

    wire new_tick = tick && scan_en;

    // the slot exec_engine is working on (it leaves the book on trq_ack)
    wire       waiting   = (state == S_WAIT);
    wire       ack_now   = waiting && trq_ack;
    wire       can_ok    = cancel && valid[cancel_idx] && !(waiting && cancel_idx == idx);
    wire [2:0] can_other = s_lnk[cancel_idx];

    // ------------------------------------------------------------ sequential
    always @(posedge clk) begin
        if (sys_reset) begin
            valid     <= 8'd0;
            lnk_v     <= 8'd0;
            state     <= S_IDLE;
            idx       <= 3'd0;
            rescan    <= 1'b0;
            trq       <= 1'b0;
            trq_slot  <= 3'd0;
            trq_stock <= 2'd0;
            trq_side  <= 1'b0;
            trq_type  <= 2'd0;
            trq_qty   <= 8'd0;
            trq_px    <= 16'd0;
            trq_brk   <= `BRK_OFF;
        end else begin
            case (state)
                S_IDLE: begin
                    if (new_tick || rescan) begin
                        idx    <= 3'd0;
                        rescan <= 1'b0;
                        state  <= S_SCAN;
                    end
                end
                S_SCAN: begin
                    if (new_tick) rescan <= 1'b1;
                    if (sc_hit) begin
                        trq       <= 1'b1;
                        trq_slot  <= idx;
                        trq_stock <= sc_stock;
                        trq_side  <= sc_side;
                        trq_type  <= sc_type;
                        trq_qty   <= s_qty[idx];
                        trq_px    <= (sc_side == `SIDE_SELL) ? sc_bid : sc_ask;
                        trq_brk   <= s_brk[idx];
                        state     <= S_WAIT;
                    end else if (idx == 3'd7) begin
                        state <= S_IDLE;
                    end else begin
                        idx <= idx + 3'd1;
                    end
                end
                S_WAIT: begin
                    if (new_tick) rescan <= 1'b1;
                    if (trq_ack) begin
                        trq <= 1'b0;
                        if (idx == 3'd7) begin
                            state <= S_IDLE;
                        end else begin
                            idx   <= idx + 3'd1;
                            state <= S_SCAN;
                        end
                    end
                end
                default: state <= S_IDLE;
            endcase

            // ---- slots leave: the triggered slot, a cancelled slot, and their linked legs
            if (ack_now) begin
                valid[idx] <= 1'b0;
                if (lnk_v[idx]) valid[s_lnk[idx]] <= 1'b0;
            end
            if (can_ok) begin
                valid[cancel_idx] <= 1'b0;
                if (lnk_v[cancel_idx]) begin
                    if (waiting && can_other == idx)
                        lnk_v[idx] <= 1'b0;        // the other leg is filling: let it go alone
                    else
                        valid[can_other] <= 1'b0;
                end
            end

            // ---- slots arrive (last, so they win over a clear of a free slot)
            if (ins && !full) begin
                valid[free_idx]   <= 1'b1;
                s_side[free_idx]  <= ins_side;
                s_stock[free_idx] <= ins_stock;
                s_type[free_idx]  <= ins_type;
                s_qty[free_idx]   <= ins_qty;
                s_trig[free_idx]  <= ins_trig;
                s_brk[free_idx]   <= (ins_side == `SIDE_BUY) ? ins_brk : `BRK_OFF;
                lnk_v[free_idx]   <= 1'b0;
            end
            if (ins_pair && free_cnt >= 4'd2) begin
                valid[free_idx]    <= 1'b1;            // stop-loss
                s_side[free_idx]   <= `SIDE_SELL;
                s_stock[free_idx]  <= pair_stock;
                s_type[free_idx]   <= `OT_STP;
                s_qty[free_idx]    <= pair_qty;
                s_trig[free_idx]   <= pair_sl;
                s_brk[free_idx]    <= `BRK_OFF;
                lnk_v[free_idx]    <= 1'b1;
                s_lnk[free_idx]    <= free_idx2;
                valid[free_idx2]   <= 1'b1;            // take-profit
                s_side[free_idx2]  <= `SIDE_SELL;
                s_stock[free_idx2] <= pair_stock;
                s_type[free_idx2]  <= `OT_LMT;
                s_qty[free_idx2]   <= pair_qty;
                s_trig[free_idx2]  <= pair_tp;
                s_brk[free_idx2]   <= `BRK_OFF;
                lnk_v[free_idx2]   <= 1'b1;
                s_lnk[free_idx2]   <= free_idx;
            end
        end
    end
endmodule

`default_nettype wire
