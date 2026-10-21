`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// order_book: 8-slot pending book for LMT and STP orders.
//
// Insert : into the lowest free slot (exec_engine has already validated it).
// Cancel : by slot index (Phase 3 pending list). Ignored for the slot that is
//          currently waiting on exec_engine, which will clear it anyway.
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
    // cancel (Phase 3)
    input  wire        cancel,
    input  wire [2:0]  cancel_idx,
    // status
    output wire        full,
    output wire [3:0]  count,
    // trigger request to exec_engine
    output reg         trq,
    output reg  [2:0]  trq_slot,
    output reg  [1:0]  trq_stock,
    output reg         trq_side,
    output reg  [1:0]  trq_type,
    output reg  [7:0]  trq_qty,
    output reg  [15:0] trq_px,
    input  wire        trq_ack,
    // read port (Phase 3 pending list, and testbenches)
    input  wire [2:0]  rd_idx,
    output wire        rd_valid,
    output wire [1:0]  rd_stock,
    output wire        rd_side,
    output wire [1:0]  rd_type,
    output wire [7:0]  rd_qty,
    output wire [15:0] rd_trig
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

    assign full  = &valid;
    assign count = valid[0] + valid[1] + valid[2] + valid[3]
                 + valid[4] + valid[5] + valid[6] + valid[7];

    assign rd_valid = valid[rd_idx];
    assign rd_stock = s_stock[rd_idx];
    assign rd_side  = s_side[rd_idx];
    assign rd_type  = s_type[rd_idx];
    assign rd_qty   = s_qty[rd_idx];
    assign rd_trig  = s_trig[rd_idx];

    // lowest free slot
    reg [2:0] free_idx;
    integer i;
    always @* begin
        free_idx = 3'd0;
        for (i = 7; i >= 0; i = i - 1)
            if (!valid[i]) free_idx = i;
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

    // ------------------------------------------------------------ sequential
    always @(posedge clk) begin
        if (sys_reset) begin
            valid     <= 8'd0;
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

            // slot updates; insert last so it wins over a cancel of an empty slot
            if (state == S_WAIT && trq_ack)
                valid[idx] <= 1'b0;
            if (cancel && !(state == S_WAIT && cancel_idx == idx))
                valid[cancel_idx] <= 1'b0;
            if (ins && !full) begin
                valid[free_idx]   <= 1'b1;
                s_side[free_idx]  <= ins_side;
                s_stock[free_idx] <= ins_stock;
                s_type[free_idx]  <= ins_type;
                s_qty[free_idx]   <= ins_qty;
                s_trig[free_idx]  <= ins_trig;
            end
        end
    end
endmodule

`default_nettype wire
