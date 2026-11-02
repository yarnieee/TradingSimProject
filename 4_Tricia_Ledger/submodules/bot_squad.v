`timescale 1ns / 1ps
`default_nettype none

// bot_squad.v: four more bots, each with its own strategy, cash and holdings.
//
//   bot 0  OVERNIGHT  at the close: buys QTY of every stock it can afford;
//                     at the next open: sells everything.  Never holds during the day.
//   bot 1  MOMENTUM   at the open, per stock: holds none -> buys QTY once the price has
//                     gone up MOM_N days in a row; holds some -> sells all on the first
//                     down day.  ref = yesterday's price and adds = up days in a row
//                     (saturating at 3), both written at every open.  (Replaced DAY TRADE,
//                     which could only lose: open and close have the same price.)
//   bot 2  AVG DOWN   at the open, per stock: holds none -> buys QTY.  Holds some ->
//                     sells all once its value at the bid is K_OUT above what it paid;
//                     otherwise buys QTY more when the price is K_ADD below its last
//                     buy, at most MAX_ADDS times.
//   bot 3  SL / TP    at the open, per stock: holds some -> sells all when the price is
//                     K_TP above its buy (take profit) or K_SL below it (stop loss).
//                     Holds none -> buys QTY (so after selling it buys again the next day).
//
// The market has one price a day, so "open" (open_tick, the start of a day) and
// "close" (close_tick, late in the day) see the same price: the overnight bot
// gains or loses each day's move.
//
// Trades work like the player's: buys pay the ask (price + SPREAD) and sells get
// the bid (price - SPREAD, at least 1), each with a FEE; a buy needs
// ask x QTY + FEE <= cash.  As in ledger.v, the cost basis includes the buy fee and
// profit/loss = shares x price - cost basis.  Percentages are x k >> 16
// (656 = 1%, 3280 = 5%, 6560 = 10%), as in the order engine.
//
// One engine serves all four bots: on open_tick / close_tick it visits bot 0..3,
// stock 0..3 in turn (6 clocks each); between those it keeps re-valuing every bot
// (net worth = cash + shares x price) and the details of bot `sel` for the screens.
// All bot state is in small RAMs (one write a clock), cleared at reset.
// trade pulses once per trade with its bot, stock, side and price.
module bot_squad #(
    parameter [31:0] START_CASH = 32'd1_000_000,   // cents
    parameter [7:0]  QTY        = 8'd20,           // shares per buy
    parameter [15:0] SPREAD     = 16'd5,
    parameter [15:0] FEE        = 16'd100,
    parameter [12:0] K_ADD      = 13'd3280,        // AVG DOWN: buy more 5% below the last buy
    parameter [12:0] K_OUT      = 13'd3280,        // AVG DOWN: sell all 5% above cost
    parameter [1:0]  MAX_ADDS   = 2'd3,
    parameter [12:0] K_TP       = 13'd6560,        // SL / TP: take profit at +10%
    parameter [12:0] K_SL       = 13'd3280,        //          stop loss at -5%
    parameter [1:0]  MOM_N      = 2'd2             // MOMENTUM: up days in a row before a buy (1-3)
) (
    input  wire        clk,
    input  wire        rst,                 // new game
    input  wire        run,                 // 1: allowed to trade
    input  wire        open_tick,           // start of a trading day (prices are new)
    input  wire        close_tick,          // end of the trading day
    input  wire [15:0] price0, price1, price2, price3,
    input  wire [1:0]  sel,                 // the bot whose details go to the screens
    output reg  [127:0] value,              // net worth of bot b at [32*b +: 32], cents
    output reg  [31:0] sel_cash,
    output reg  [39:0] sel_pos,             // shares of stock k at [10*k +: 10]
    output reg  [127:0] sel_upnl,           // profit/loss of stock k at [32*k +: 32] (signed)
    output reg         trade,               // 1 clock per trade
    output reg  [1:0]  trade_bot,
    output reg  [1:0]  trade_stock,
    output reg         trade_side,          // 0 buy, 1 sell
    output reg  [15:0] trade_price
);
    localparam [3:0] S_CLEAR = 4'd0, S_IDLE = 4'd1,
                     S_T_RD  = 4'd2, S_T_M0 = 4'd3, S_T_M1 = 4'd4, S_T_M2 = 4'd5,
                     S_T_DEC = 4'd6, S_T_WR = 4'd7,
                     S_V_RD  = 4'd8, S_V_MUL = 4'd9, S_V_ACC = 4'd10;
    localparam [1:0] B_NIGHT = 2'd0, B_MOM = 2'd1, B_AVG = 2'd2, B_SLTP = 2'd3;

    reg  [3:0] state;
    reg  [3:0] i;                         // {bot, stock}
    wire [1:0] b = i[3:2];
    wire [1:0] k = i[1:0];
    reg        open_pend, close_pend, at_open;

    // ------------------------------------------------------------ bot state (RAM)
    reg [31:0] cash_m [0:3];
    reg [9:0]  pos_m  [0:15];
    reg [31:0] cb_m   [0:15];             // cost basis, fees included
    reg [15:0] ref_m  [0:15];             // AVG DOWN: last buy; SL / TP: entry price
    reg [1:0]  adds_m [0:15];             // AVG DOWN: buys added

    // the step being worked on (registered reads)
    reg [31:0] r_cash, r_cb;
    reg [9:0]  r_pos;
    reg [15:0] r_ref, r_px;
    reg [1:0]  r_adds;
    reg [31:0] r_cost;                    // ask x QTY + FEE

    reg [15:0] px_k;
    always @(*) begin
        case (k)
            2'd0:    px_k = price0;
            2'd1:    px_k = price1;
            2'd2:    px_k = price2;
            default: px_k = price3;
        endcase
    end

    // bid / ask, as spread_calc
    wire [16:0] ask_full = {1'b0, r_px} + {1'b0, SPREAD};
    wire [15:0] ask      = ask_full[16] ? 16'hFFFF : ask_full[15:0];
    wire [15:0] bid      = (r_px > SPREAD) ? r_px - SPREAD : 16'd1;
    wire [31:0] buy_cost = ask * QTY + FEE;    // registered in r_cost

    // products of a step, one per clock (each multiplier has registers on both sides)
    reg [25:0] p_sell;                    // bid x shares (valuing: price x shares)
    reg [28:0] p_ref1;                    // ref x K (add / take profit)
    reg [28:0] p_ref2;                    // ref x K_SL
    reg [37:0] p_cb;                      // cost basis x K_OUT
    reg [31:0] acc;                       // net worth being added up

    // ------------------------------------------------------------ the decision for this step
    wire        held     = (r_pos != 10'd0);
    wire        can_buy  = (r_cost <= r_cash) && (r_pos <= 10'd1023 - QTY);
    wire        can_sell = ({6'd0, p_sell} + r_cash >= {16'd0, FEE});
    wire [15:0] d1       = p_ref1[28:16];                  // ref x K / 65536
    wire [15:0] d2       = p_ref2[28:16];
    wire [31:0] cb_out   = r_cb + p_cb[37:16];             // cost + K_OUT
    wire        tp_hit   = ({1'b0, r_px} >= {1'b0, r_ref} + {1'b0, d1});
    wire        sl_hit   = (r_px <= ((r_ref > d2) ? r_ref - d2 : 16'd0));
    wire        add_hit  = (r_px <= ((r_ref > d1) ? r_ref - d1 : 16'd0));
    // MOMENTUM: today against yesterday (r_ref), and the up-day streak including today
    wire        up_day   = (r_px > r_ref) && (r_ref != 16'd0);
    wire        down_day = (r_px < r_ref);
    wire [1:0]  streak   = !up_day ? 2'd0 : (r_adds == 2'd3) ? 2'd3 : r_adds + 2'd1;

    reg do_buy, do_sell;
    always @(*) begin
        do_buy  = 1'b0;
        do_sell = 1'b0;
        case (b)
            B_NIGHT: if (at_open) do_sell = held && can_sell;
                     else         do_buy  = !held && can_buy;
            B_MOM:   if (at_open) begin
                         if (held) do_sell = down_day && can_sell;
                         else      do_buy  = (streak >= MOM_N) && can_buy;
                     end
            B_AVG:   if (at_open) begin
                         if (!held)                                    do_buy  = can_buy;
                         else if ({6'd0, p_sell} >= cb_out)            do_sell = can_sell;
                         else if (r_adds < MAX_ADDS && add_hit)        do_buy  = can_buy;
                     end
            default: if (at_open) begin                             // SL / TP
                         if (held) do_sell = (tp_hit || sl_hit) && can_sell;
                         else      do_buy  = can_buy;
                     end
        endcase
    end
    always @(posedge clk) begin
        trade <= 1'b0;
        if (rst) begin
            state      <= S_CLEAR;
            i          <= 4'd0;
            open_pend  <= 1'b0;
            close_pend <= 1'b0;
            at_open    <= 1'b0;
            value      <= {4{START_CASH}};
            sel_cash   <= START_CASH;
            sel_pos    <= 40'd0;
            sel_upnl   <= 128'd0;
        end else begin
            if (open_tick)  open_pend  <= 1'b1;
            if (close_tick) close_pend <= 1'b1;

            case (state)
                S_CLEAR: begin                                  // a new game: everyone starts flat
                    if (i[3:2] == 2'd0) cash_m[i[1:0]] <= START_CASH;
                    pos_m[i]  <= 10'd0;
                    cb_m[i]   <= 32'd0;
                    ref_m[i]  <= 16'd0;
                    adds_m[i] <= 2'd0;
                    i <= i + 4'd1;
                    if (i == 4'd15) state <= S_IDLE;
                end

                S_IDLE: begin
                    i <= 4'd0;
                    if (open_pend || close_pend) begin
                        at_open    <= open_pend;
                        open_pend  <= 1'b0;
                        close_pend <= 1'b0;
                        state      <= run ? S_T_RD : S_V_RD;
                    end else
                        state <= S_V_RD;
                end

                // -------------------------------------------------- trading: one bot and stock
                S_T_RD: begin
                    r_cash <= cash_m[b];
                    r_pos  <= pos_m[i];
                    r_cb   <= cb_m[i];
                    r_ref  <= ref_m[i];
                    r_adds <= adds_m[i];
                    r_px   <= px_k;
                    state  <= S_T_M0;
                end
                S_T_M0: begin p_sell <= bid * r_pos; r_cost <= buy_cost;           state <= S_T_M1; end
                S_T_M1: begin p_ref1 <= r_ref * ((b == B_AVG) ? K_ADD : K_TP);    state <= S_T_M2; end
                S_T_M2: begin
                    p_ref2 <= r_ref * K_SL;
                    p_cb   <= r_cb[24:0] * K_OUT;
                    state  <= S_T_DEC;
                end
                S_T_DEC: state <= S_T_WR;                       // decision below settles
                S_T_WR: begin
                    if (do_buy) begin
                        cash_m[b] <= r_cash - r_cost;
                        pos_m[i]  <= r_pos + QTY;
                        cb_m[i]   <= r_cb + r_cost;
                        ref_m[i]  <= r_px;
                        adds_m[i] <= (r_pos == 10'd0) ? 2'd0 : r_adds + 2'd1;
                    end else if (do_sell) begin
                        cash_m[b] <= r_cash + p_sell - FEE;
                        pos_m[i]  <= 10'd0;
                        cb_m[i]   <= 32'd0;
                        adds_m[i] <= 2'd0;
                    end
                    if (b == B_MOM && at_open) begin            // MOMENTUM: remember today
                        ref_m[i]  <= r_px;                      // (overrides the writes above)
                        adds_m[i] <= streak;
                    end
                    if (do_buy || do_sell) begin
                        trade       <= 1'b1;
                        trade_bot   <= b;
                        trade_stock <= k;
                        trade_side  <= do_sell;
                        trade_price <= do_sell ? bid : ask;
                    end
                    i     <= i + 4'd1;
                    state <= (i == 4'd15) ? S_IDLE : S_T_RD;
                end

                // -------------------------------------------------- valuing: cash + shares x price
                S_V_RD: begin
                    r_cash <= cash_m[b];
                    r_pos  <= pos_m[i];
                    r_cb   <= cb_m[i];
                    r_px   <= px_k;
                    state  <= S_V_MUL;
                end
                S_V_MUL: begin
                    p_sell <= r_px * r_pos;                     // the shares' value at the price
                    state  <= S_V_ACC;
                end
                S_V_ACC: begin
                    acc <= ((k == 2'd0) ? r_cash : acc) + p_sell;
                    if (k == 2'd3)
                        value[32*b +: 32] <= ((k == 2'd0) ? r_cash : acc) + p_sell;
                    if (b == sel) begin
                        sel_pos[10*k +: 10]  <= r_pos;
                        sel_upnl[32*k +: 32] <= {6'd0, p_sell} - r_cb;
                        if (k == 2'd0) sel_cash <= r_cash;
                    end
                    i     <= i + 4'd1;
                    state <= (i == 4'd15) ? S_IDLE : S_V_RD;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
