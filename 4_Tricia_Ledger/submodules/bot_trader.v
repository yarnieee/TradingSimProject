`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// bot_trader: the computer player the user competes against (team plan,
// Component C: "a bot trader with its own ledger trades an 8-day moving-average
// momentum rule"). [AI-written 26 Oct for Tricia to review.]
//
// After every market tick, for each stock in turn:
//   ma   = average of the last 8 daily prices (newest 8 of the 30 samples)
//   up   = price > ma + ma/64      (about 1.5% above: rising)
//   down = price < ma - ma/64      (about 1.5% below: falling)
//   up   and no shares  -> buy BOT_QTY shares at the ask (price + SPREAD), if cash allows
//   down and has shares -> sell all of them at the bid (price - SPREAD)
// Every trade pays FEE. The bot has its own cash, shares and cost basis (buy
// cost including the fee), separate from the player's ledger; it never sends
// fills to the order engine. Then its total value (cash + shares x price) is
// worked out with one multiplier, one stock per clock.
//
// The last 5 trades are kept for the bot's activity screen, newest first:
// log entry n is bits [n] (valid, side), [2n+1:2n] (stock), [16n+15:16n]
// (price) and [8n+7:8n] (day).
module bot_trader #(
    parameter [31:0] START_CASH = 32'd1_000_000,  // cents ($10,000), as the player
    parameter [15:0] SPREAD     = 16'd5,
    parameter [15:0] FEE        = 16'd100,
    parameter [9:0]  BOT_QTY    = 10'd10
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         tick,           // one pulse per trading day
    input  wire         game_live,      // trade only while the game is running
    input  wire [7:0]   day,            // trading day number, for the log
    input  wire [15:0]  price0,
    input  wire [15:0]  price1,
    input  wire [15:0]  price2,
    input  wire [15:0]  price3,
    input  wire [479:0] samples0,       // 30 daily prices per stock, newest at [479:464]
    input  wire [479:0] samples1,
    input  wire [479:0] samples2,
    input  wire [479:0] samples3,
    output reg  [31:0]  cash,
    output reg  [9:0]   pos0,
    output reg  [9:0]   pos1,
    output reg  [9:0]   pos2,
    output reg  [9:0]   pos3,
    output reg  [31:0]  cb0,
    output reg  [31:0]  cb1,
    output reg  [31:0]  cb2,
    output reg  [31:0]  cb3,
    output reg  [31:0]  value,          // cash + shares x price, after each tick
    output reg  [7:0]   signal,         // per stock [2k+1:2k]: 1 up, 2 down, 0 neither
    output reg  [7:0]   trades,         // trades so far
    output reg  [4:0]   log_valid,
    output reg  [4:0]   log_side,       // 0 buy, 1 sell
    output reg  [9:0]   log_stock,
    output reg  [79:0]  log_price,
    output reg  [39:0]  log_day
);
    localparam S_IDLE = 2'd0, S_WAIT = 2'd1, S_TRADE = 2'd2, S_VALUE = 2'd3;
    reg [1:0] state;
    reg [1:0] k;               // stock being looked at
    reg [2:0] wait_cnt;

    // ------------------------------------------------------------ stock k
    reg [15:0]  px;
    reg [479:0] smp;
    reg [9:0]   pos;
    always @* begin
        case (k)
            2'd0:    begin px = price0; smp = samples0; pos = pos0; end
            2'd1:    begin px = price1; smp = samples1; pos = pos1; end
            2'd2:    begin px = price2; smp = samples2; pos = pos2; end
            default: begin px = price3; smp = samples3; pos = pos3; end
        endcase
    end

    // 8-day moving average of the newest samples (22..29)
    wire [18:0] sum8 = smp[22*16 +: 16] + smp[23*16 +: 16] + smp[24*16 +: 16] + smp[25*16 +: 16]
                     + smp[26*16 +: 16] + smp[27*16 +: 16] + smp[28*16 +: 16] + smp[29*16 +: 16];
    wire [15:0] ma   = sum8[18:3];
    wire [16:0] hi   = {1'b0, ma} + {7'd0, ma[15:6]};
    wire [15:0] lo   = ma - {6'd0, ma[15:6]};
    wire        up   = ({1'b0, px} > hi);
    wire        down = (px < lo);

    wire [16:0] ask_full = {1'b0, px} + {1'b0, SPREAD};
    wire [15:0] ask      = ask_full[16] ? 16'hFFFF : ask_full[15:0];
    wire [15:0] bid      = (px > SPREAD) ? px - SPREAD : 16'd0;
    // one multiplier: buy cost, sale proceeds, then holdings value
    wire [15:0] mul_a    = (state == S_VALUE) ? px  : (pos == 10'd0) ? ask : bid;
    wire [9:0]  mul_b    = (state == S_VALUE) ? pos : (pos == 10'd0) ? BOT_QTY : pos;
    wire [25:0] prod     = mul_a * mul_b;
    wire [31:0] buy_cost = {6'd0, prod} + FEE;

    reg [31:0] val_acc;

    task set_pos;
        input [1:0]  i;
        input [9:0]  p;
        input [31:0] c;
        begin
            case (i)
                2'd0:    begin pos0 <= p; cb0 <= c; end
                2'd1:    begin pos1 <= p; cb1 <= c; end
                2'd2:    begin pos2 <= p; cb2 <= c; end
                default: begin pos3 <= p; cb3 <= c; end
            endcase
        end
    endtask

    task log_trade;            // push a trade onto the front of the log
        input       sd;
        input [1:0] stk;
        input [15:0] p;
        begin
            log_valid <= {log_valid[3:0], 1'b1};
            log_side  <= {log_side[3:0], sd};
            log_stock <= {log_stock[7:0], stk};
            log_price <= {log_price[63:0], p};
            log_day   <= {log_day[31:0], day};
            trades    <= trades + 8'd1;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            k         <= 2'd0;
            wait_cnt  <= 3'd0;
            cash      <= START_CASH;
            value     <= START_CASH;
            val_acc   <= 32'd0;
            pos0 <= 10'd0; pos1 <= 10'd0; pos2 <= 10'd0; pos3 <= 10'd0;
            cb0  <= 32'd0; cb1  <= 32'd0; cb2  <= 32'd0; cb3  <= 32'd0;
            signal    <= 8'd0;
            trades    <= 8'd0;
            log_valid <= 5'd0;
            log_side  <= 5'd0;
            log_stock <= 10'd0;
            log_price <= 80'd0;
            log_day   <= 40'd0;
        end else begin
            case (state)
                S_IDLE: if (tick && game_live) begin
                    wait_cnt <= 3'd0;
                    state    <= S_WAIT;
                end
                S_WAIT: begin                    // let the new day's prices and history settle
                    wait_cnt <= wait_cnt + 3'd1;
                    if (wait_cnt == 3'd7) begin
                        k     <= 2'd0;
                        state <= S_TRADE;
                    end
                end
                S_TRADE: begin
                    signal[2*k +: 2] <= up ? 2'd1 : down ? 2'd2 : 2'd0;
                    if (px != 16'd0) begin
                        if (up && pos == 10'd0 && cash >= buy_cost) begin
                            cash <= cash - buy_cost;
                            set_pos(k, BOT_QTY, buy_cost);
                            log_trade(1'b0, k, ask);
                        end else if (down && pos != 10'd0) begin
                            cash <= cash + {6'd0, prod} - FEE;
                            set_pos(k, 10'd0, 32'd0);
                            log_trade(1'b1, k, bid);
                        end
                    end
                    k <= k + 2'd1;
                    if (k == 2'd3) begin
                        val_acc <= 32'd0;
                        state   <= S_VALUE;
                    end
                end
                default: begin                   // S_VALUE: cash + sum of shares x price
                    if (k == 2'd3) begin
                        value <= cash + val_acc + {6'd0, prod};
                        state <= S_IDLE;
                    end else
                        val_acc <= val_acc + {6'd0, prod};
                    k <= k + 2'd1;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
