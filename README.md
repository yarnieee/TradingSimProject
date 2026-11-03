# EE2026 Trading Simulator

The team build: everyone's parts joined in one Vivado project for the Basys3.

## Folders

| Folder | Owner | Top module |
|---|---|---|
| `0_Integrated_Top/` | team | `Integration_Top.v`, plus pins, Vivado scripts, whole-game test |
| `1_Shared_Modules/` | team | debouncer, clock divider, OLED driver, shared codes |
| `2_YiAn_Market_Engine/` | Yi An | `A_top.v` |
| `3_Douglas_Orders/` | Douglas | `B_order_top.v`, `B_sound_top.v` |
| `4_Tricia_Ledger/` | Tricia | `C_portfolio_top.v` |
| `5_Matthew_Display/` | Matthew | `D_display_top.v` |
| `9_Not_Used/` | | old files, not in the build |

Each person's folder: top module, `submodules/`, `tb/` (tests).

Naming (team doc): top modules are `A_`/`B_`/`C_`/`D_<description>_top` (A Yi An, B Douglas,
C Tricia, D Matthew). Still to rename by its owner: `A_top` to `A_market_top`.

## Open in Vivado

This is `branch-douglas-sound`: `main` plus sound effects on the JXADC port (not yet merged into `main`).
`main` is the team's tested copy; work goes into a branch first and is merged into `main` once its
tests pass.

1. Clone this branch to a short path with no spaces:
   ```
   git clone -b branch-douglas-sound https://github.com/yarnieee/TradingSimProject.git C:/EE2026/TradingSimProject
   ```
   Already have a clone? In it:
   ```
   git fetch
   git checkout branch-douglas-sound
   git pull
   ```
   (Back to `main` later: `git checkout main`, then `git pull`.)
2. Open Vivado 2025.2 and type in the Tcl Console:
   ```
   source C:/EE2026/TradingSimProject/0_Integrated_Top/create_integration_project.tcl
   ```
   The project is made in `C:/EE2026/Integration_vivado` (next to the clone), replacing any
   project already there. To put it elsewhere, first type `set proj_dir C:/EE2026/other_folder`.
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
| sw[13] | up = no sound |
| sw[14] | up = your pending orders on the left OLED: BTNU / BTND choose one, BTNC cancels it (the game buttons do nothing) |
| sw[15] | view: down = you (the game), up = the bots (BTNL / BTNR choose which bot; the game buttons do nothing) |

**VGA monitor** (plug a monitor into the Basys3 VGA port): shows everything at once in widescreen
1280 x 720 (fills a 24" monitor), updated live: the four stocks with their 30-day change in $ and %, your net worth, cash, profit/loss, return and largest
drawdown, the selected stock's 30-day chart with your stop-loss / take-profit levels, your holdings,
every pending order, a leaderboard of you and the 5 bots in place order (net worth, return), the order you
are making, what the buttons do on the current screen, and what the switches are set to.
The progress bar along the top is green, turns yellow at 60 days left and red at 10.

Screens: the right OLED shows the game, the left OLED your order ticket (and title artwork on the
title screen; the monitor shows its own Bull vs Bear title screen with the five bots and a blinking
PRESS START, drawn by `5_Matthew_Display/title_screen/make_title_screen.py`). The 7-seg shows the quantity being set; LEDs flash on a fill (led 15) or a
reject (led 14) and show pending orders (led 11-8).

**Sound** (a Pmod AMP2 with a speaker in the top row of the JXADC port; a small speaker or
piezo between JXADC pin 1 and GND also works; sw[13] up mutes):

| When | Sound |
|---|---|
| any button | a short click |
| BTNU / BTND on the quantity screen | a rising / falling blip |
| an order is sent | a woosh, then a bell when it fills (a limit order's bell rings when it triggers) |
| the game ends | a short tune |

To hear the sounds without the board: run `tb_sound`, then
`python3 3_Douglas_Orders/tb/sound_to_wav.py <its folder>` turns `sound_*.txt` into `.wav` files.

**Buying or selling**
1. From HOME, go to MARKET, pick a stock, then BUY or SELL.
2. QTY: set the quantity (U/D change a digit, L/R move between digits, C to finish).
3. Set the switches for the order type (the BUY / SELL screen shows what they say).
4. NEXT, check the review screen, C to send (any other button goes back).
5. The result says FILLED (market orders), PLACED (limit / stop orders, now waiting in the book)
   or REJECTED and why.

**Order types**
- Market: fills now, at price + 5c (buy) or price - 5c (sell), plus a $1 fee.
- Limit: buy at or below a price under today's (sw[7:6] below), sell at or above one over it.
- Stop: buy when the price rises to a level above today's, sell when it falls to one below.
- Stop-loss / take-profit (buys): when the buy fills, a stop sell below and a limit sell above it
  are placed; when one fills the other is cancelled. They show as dashed red / green lines on the
  stock's chart.

**Bots**: five bots play against you, each with its own $10,000. All trade 20 shares at a time with
the same spread and fee as you. The market has one price a day, so a bot's "open" is the start of
the day and its "close" is 4.5 s in, at the same price.

| Bot | Rule |
|---|---|
| MA BOT (Tricia's) | buys when a price is above its 8-day average, sells when it falls below |
| OVERNIGHT | buys at the close, sells everything at the next open |
| MOMENTUM | buys once a price has gone up 2 days in a row, sells everything on the first down day |
| AVG DOWN | buys, then buys more each time the price is 5% below its last buy (up to 3 times); sells all at 5% above what it paid |
| SL / TP | buys, then sells at +10% (take profit) or -3% (stop loss); buys again the next day |

**Bot view (sw[15] up)**: BTNL / BTNR choose a bot. The right OLED shows its value against yours and
its holdings, the left its last 5 trades and its rule. The monitor's leaderboard marks it with `>`.

**Cancelling an order**: flip sw[14] up. The left OLED lists the pending orders; BTNU / BTND move
the cursor, BTNC cancels that order (and its linked stop-loss / take-profit leg). Flip it down to
play on. Orders can be cancelled, not edited: cancel and place a new one.

**Days**: a game is 120 trading days of 5 seconds each, 10 minutes (`FINAL_TRADING_DAY` and
`DAY_MAX_COUNT` in `Integration_Top`). The header shows the days left (`D117`, red in the last 5) and a yellow bar along
its bottom edge fills as the game goes on. The market starts when you press START, with a new
random seed taken at that moment, so every game has a different market. After the last day the market stops, the GAME OVER screen
shows your result, your place among you and the bots, and who finished first; the bot view says FINAL.
The monitor flashes a big GAME OVER for about 3 s, then shows the final results: 1st to 6th with
name, net worth, profit / loss and return, and where you finished.
