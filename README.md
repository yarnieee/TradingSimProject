# EE2026 Trading Simulator

The team build: everyone's parts joined in one Vivado project for the Basys3.

## Folders

| Folder | Owner | Top module |
|---|---|---|
| `0_Integrated_Top/` | team | `Integration_Top.v`, plus pins, Vivado scripts, whole-game test |
| `1_Shared_Modules/` | team | debouncer, clock divider, OLED driver, shared codes |
| `2_YiAn_Market_Engine/` | Yi An | `A_top.v` |
| `3_Douglas_Orders/` | Douglas | `B_order_top.v` |
| `4_Tricia_Ledger/` | Tricia | `C_portfolio_top.v` |
| `5_Matthew_Display/` | Matthew | `D_display_top.v` |
| `9_Not_Used/` | | old files, not in the build |

Each person's folder: top module, `submodules/`, `tb/` (tests).

Naming (team doc): top modules are `A_`/`B_`/`C_`/`D_<description>_top` (A Yi An, B Douglas,
C Tricia, D Matthew). Still to rename by its owner: `A_top` to `A_market_top`.

## Open in Vivado

1. Clone to a short path with no spaces:
   ```
   git clone -b branch-team-integration https://github.com/yarnieee/TradingSimProject.git C:/EE2026/TradingSimProject
   ```
2. Open Vivado 2025.2 and type in the Tcl Console:
   ```
   source C:/EE2026/TradingSimProject/0_Integrated_Top/create_integration_project.tcl
   ```
3. Generate Bitstream, then program the board.

After a `git pull`, run step 2 again.

## Run the tests

In the Tcl Console:
```
source C:/EE2026/TradingSimProject/0_Integrated_Top/run_all_tests.tcl
```
Each test prints `PASS` or `FAIL`.

## Using the board

| Control | What it does |
|---|---|
| sw[0] | reset (up = reset, down = play) |
| Buttons | move through the game screens (U D L R move, C selects) |
| sw[3:2] | order type: `00` market, `01` limit, `10` stop |
| sw[5:4] | stop-loss / take-profit for a buy: `00` off, `01` 2%, `10` 5%, `11` 10% |
| sw[7:6] | trigger distance from the price: `00` 1%, `01` 2%, `10` 5%, `11` 10% |
| sw[15] | view: down = you (the game), up = the bot (buttons do nothing while up) |

Screens: the right OLED shows the game, the left OLED your order ticket (and title artwork on the
title screen). The 7-seg shows the quantity being set; LEDs flash on a fill (led 15) or a
reject (led 14) and show pending orders (led 11-8).

**Buying or selling**
1. From HOME, go to MARKET, pick a stock, then BUY or SELL.
2. QTY: set the quantity (U/D change a digit, L/R move between digits, C to finish).
3. Set the switches for the order type (the BUY / SELL screen shows what they say).
4. NEXT, check the review screen, C to send.
5. The result says FILLED (market orders), PLACED (limit / stop orders, now waiting in the book)
   or REJECTED and why.

**Order types**
- Market: fills now, at price + 5c (buy) or price - 5c (sell), plus a $1 fee.
- Limit: buy at or below a price under today's (sw[7:6] below), sell at or above one over it.
- Stop: buy when the price rises to a level above today's, sell when it falls to one below.
- Stop-loss / take-profit (buys): when the buy fills, a stop sell below and a limit sell above it
  are placed; when one fills the other is cancelled. They show as dashed red / green lines on the
  stock's chart.

**Bot view (sw[15] up)**: the right OLED shows the bot's value against yours and its holdings, the
left its last trades. Tricia's bot trades every day on its own ledger: it buys 20 shares when a price
is above its 8-day average, and sells them when it falls below.

**Days**: a game is 60 trading days of 2 seconds each, about 2 minutes (`FINAL_TRADING_DAY` in
`Integration_Top`). The header shows the days left (`D57`, red in the last 5) and a yellow bar along
its bottom edge fills as the game goes on. After the last day the GAME OVER screen shows your result.
