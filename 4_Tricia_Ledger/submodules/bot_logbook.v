`timescale 1ns / 1ps
`default_nettype none

// bot_logbook.v: the recent trades of every bot, for the bot screens.
//   bot 0      Tricia's moving-average bot (bot_trader), trade a_*
//   bots 1-4   bot_squad's bots 0-3, trade q_*
// Each bot keeps its last 8 trades in one small RAM ({bot, slot}); log_* are the
// last 5 of bot `sel`, newest first, in the layout the screens already use.
// A trade from the moving-average bot that arrives on the same clock as one
// from bot_squad waits one clock (they are never closer than a few clocks apart).
module bot_logbook (
    input  wire        clk,
    input  wire        rst,                // new game: empty logs
    input  wire [7:0]  day,                // trading day of the trade
    input  wire        a_trade,
    input  wire        a_side,
    input  wire [1:0]  a_stock,
    input  wire [15:0] a_price,
    input  wire        q_trade,
    input  wire [1:0]  q_bot,
    input  wire        q_side,
    input  wire [1:0]  q_stock,
    input  wire [15:0] q_price,
    input  wire [2:0]  sel,                // 0..4
    output reg  [4:0]  log_valid,          // entry n (0 newest) at bit n
    output reg  [4:0]  log_side,
    output reg  [9:0]  log_stock,
    output reg  [79:0] log_price,
    output reg  [39:0] log_day
);
    reg [26:0] mem [0:63];                 // {side, stock, price, day}
    reg [2:0]  head [0:4];                 // next slot to write
    reg [2:0]  cnt  [0:4];                 // trades so far, up to 5

    // a moving-average trade waiting for a free clock
    reg        a_pend;
    reg [18:0] a_word;                     // {side, stock, price}

    wire        w_q   = q_trade;
    wire        w_a   = !q_trade && a_pend;
    wire [2:0]  w_bot = w_q ? {1'b0, q_bot} + 3'd1 : 3'd0;
    wire [26:0] w_dat = w_q ? {q_side, q_stock, q_price, day} : {a_word, day};

    integer n;
    always @(posedge clk) begin
        if (rst) begin
            a_pend <= 1'b0;
            for (n = 0; n < 5; n = n + 1) begin head[n] <= 3'd0; cnt[n] <= 3'd0; end
        end else begin
            if (a_trade) begin
                a_pend <= 1'b1;
                a_word <= {a_side, a_stock, a_price};
            end else if (w_a)
                a_pend <= 1'b0;
            if (w_q || w_a) begin
                mem[{w_bot, head[w_bot]}] <= w_dat;
                head[w_bot] <= head[w_bot] + 3'd1;
                if (cnt[w_bot] != 3'd5) cnt[w_bot] <= cnt[w_bot] + 3'd1;
            end
        end
    end

    // copy the chosen bot's last 5 to the outputs, one a clock, over and over
    reg  [2:0]  rn;                        // entry 0..4
    wire [2:0]  rslot = head[sel] - 3'd1 - rn;
    wire [26:0] rd    = mem[{sel, rslot}];
    always @(posedge clk) begin
        if (rst) begin
            rn        <= 3'd0;
            log_valid <= 5'd0;
        end else begin
            log_valid[rn]          <= (rn < cnt[sel]);
            log_side[rn]           <= rd[26];
            log_stock[2*rn +: 2]   <= rd[25:24];
            log_price[16*rn +: 16] <= rd[23:8];
            log_day[8*rn +: 8]     <= rd[7:0];
            rn <= (rn == 3'd4) ? 3'd0 : rn + 3'd1;
        end
    end
endmodule

`default_nettype wire
