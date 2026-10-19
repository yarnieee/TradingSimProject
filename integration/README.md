# Integration build: all four parts (branch-integration)

This branch is `main` plus everyone's branch merged in (A `branch-yian-market-engine`,
B `branch-douglas-orders`, C `branch-tricia-ledger`, D `branch-matthew-oled-ui`), plus this
folder. **Nobody's own files are edited here.** Everything that joins the parts is in
`Integration_Top.v`, in a section marked ADAPTERS.

| File | What |
|---|---|
| `Integration_Top.v` | top module wiring A, B, C and D |
| `Integration.xdc` | pins (D's pins, plus JA for the second OLED) |
| `create_integration_project.tcl` | builds the Vivado project from everyone's files |
| `tb_integration.v` | plays the game through D's screens and checks B and C |

## Opening it in Vivado (Windows)

Do **not** open `TradingSimProject.xpr` on this branch. Everyone's `.xpr` changes conflict
when merged, so this branch keeps `main`'s old one, which does not list the new files.
The script builds a fresh project instead.

1. Clone this branch to a short path with no spaces:
   ```
   git clone -b branch-integration https://github.com/yarnieee/TradingSimProject.git C:/EE2026/TradingSimProject
   ```
2. Open Vivado 2025.2 on its own, and in the **Tcl Console**:
   ```
   source C:/EE2026/TradingSimProject/integration/create_integration_project.tcl
   ```
   It creates `C:/EE2026/Integration_vivado` next to the repo, using the repo files in place.
3. Optional check: Run Simulation > Run Behavioral Simulation. Look for
   `PASS: tb_integration` in the Tcl Console (this takes several minutes; A's history logic is slow to simulate).
4. Generate Bitstream. Check the timing summary (WNS should be positive), then Hardware
   Manager > Auto Connect > Program Device.

## On the board

| | |
|---|---|
| sw[0] | reset (up = reset) |
| Buttons | D's screens: title > portfolio > stocks > stock > buy/sell > quantity > confirm |
| JB (right OLED) | D's game screens |
| JA (left OLED) | B's order ticket: bid/ask of the selected stock, last fill or reject, pending orders. Temporary, until A's chart page exists |
| 7-seg | D's quantity |
| led[7:4] | D's screen number |
| led[11:8] | pending orders (B) |
| led[14] / led[15] | flash on reject / fill (B) |

To buy: C (title) > R, C (stocks) > U/D to pick, C > C (buy) > R, C (quantity) > U to set
> C > R, R, C (confirmation). The order is placed on entering the confirm screen: JA shows
`FILL ...` or `REJ ...`, and the LEDs flash.

## How the parts are joined (the adapters)

Each adapter is temporary. It disappears when the owner adds the signal from the Module I/O map.

| Adapter | Why | Replaced when |
|---|---|---|
| price0 = AMD, price1 = MCD, price2/3 = 0 | A has 2 stocks, the plan has 4. B treats a 0 price as a closed stock and rejects it as NOT LIVE | A outputs `price0..3` |
| `tick` from A's date changing | A's day tick is internal | A outputs `tick` |
| Order = the move into D's CONFIRM screen; side from BUY or SELL screen; quantity = D's `quantity` | D has no order output | D outputs a confirm pulse and side |
| Selected stock: a copy of game_fsm's `stocks_cursor` logic | `stocks_cursor` is internal to game_fsm | D outputs `sel_stock` |
| `game_state` = PLAYING except on title and game-end screens | D has no `game_state` output | D outputs `game_state` |
| Quantity: B accepts D's 0-9999 and rejects anything outside 1-255 as BAD QTY | team decision, 19 Oct: orders stay 8-bit | Matthew may cap the quantity editor at 255 (optional) |
| A's history outputs unconnected | the 1800-day history in registers would not fit the chip | A's chart page uses a smaller history (about 96 points) or block RAM |

## Known issues (owners to fix)

1. **A, `stock.v`, `calculate_next_close`: prices pin at $655.35.** `previous_close` is
   unsigned, so the whole `random_term` expression is evaluated unsigned. When `random_offset`
   is negative, it wraps to a huge positive number and the price clamps to 65535, where it
   stays. Fix: copy it into a signed integer first, for example
   `integer p; p = previous_close;` and use `p` in both terms. Checked in isolation: price 21343,
   offset -25 gives 65535 as written and 18675 with the fix.
2. **A, same function: prices drift down 10% a day.** `stable_term` keeps 90% of the price and
   `random_term` adds at most a few percent back, so even the largest upward move ends lower
   (21343 to 20275). The usual form is `next = previous + previous * VOLATILITY * offset / 10000`.
3. **A, `$readmemh("storage/AMD_seed.mem")`:** the path includes a folder. If Vivado reports it
   cannot open the file, change the path to just `AMD_seed.mem` (the script adds both .mem files
   to the project). [ASSUMPTION: Vivado resolves .mem files added to the project by file name.
   Not tested here.]
4. **`TradingSimProject.xpr` on this branch is `main`'s** and does not list the new files. Use the
   script. When the branches go into `main`, one person should rebuild the `.xpr` (add sources
   in Vivado) rather than merging the XML.

## What has been checked (Icarus Verilog + Yosys, not yet Vivado or a board)

`tb_integration` plays the game with real button presses (debounce shortened to 50 clocks,
a trading day to 4000 clocks) and checks: A produces prices and a tick; D's screens move as
expected; buying 3 AMD through D's screens fills in B and updates C's cash and position
exactly; selling a stock you don't hold is rejected by B and never reaches C; a stock with no
price is rejected; quantity 0 is rejected; a partial sell goes through C's divider and C's
invariant holds; C never rejects a fill from B. 15 checks pass. A's price bug above is
reported as a warning.
