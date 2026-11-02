`timescale 1ns / 1ps
`default_nettype none

// bot_difficulty.v: how hard each bot is to beat, for the screens (Member C).
// Constants only (no logic, no clock). The display side can instantiate it:
//     wire [9:0] bot_level;
//     bot_difficulty levels (.level(bot_level));
//     ... bot_level[2*bot_sel +: 2] ...          // same numbering as bot_sel
//
//   bot_sel  bot              level    suggested text
//   0        MA BOT           HARD     "HARD"
//   1        OVERNIGHT        EASY     "EASY"
//   2        MOMENTUM         HARD     "HARD"
//   3        AVG DOWN         EASY     "EASY"
//   4        SL / TP          MEDIUM   "MED "
//
// Why these levels (claude_report/bots_v2: 20 games x 120 days of Yi An's market):
//   HARD   = makes money in most games and beats a buy-and-hold player in all 20
//            (MA +85.6 %, MOMENTUM +83.6 % on average; they share 1st place 10/10)
//   MEDIUM = loses on average but beats buy-and-hold in 16 of 20 (SL/TP -28 %)
//   EASY   = loses money in almost every game (OVERNIGHT -60 %, AVG DOWN -61 %)
// Re-check these if the market model or a bot's rule changes.
module bot_difficulty (
    output wire [9:0]  level                // level of bot n at [2*n +: 2]: 1 easy, 2 medium, 3 hard
);
    localparam [1:0] EASY = 2'd1, MEDIUM = 2'd2, HARD = 2'd3;

    assign level = {MEDIUM,                 // 4  SL / TP
                    EASY,                   // 3  AVG DOWN
                    HARD,                   // 2  MOMENTUM
                    EASY,                   // 1  OVERNIGHT
                    HARD};                  // 0  MA BOT
endmodule

`default_nettype wire
