# Team integration build (branch-team-integration)

Everyone's work in one build. This branch is `main` with each person's branch merged in:

| Person | Part | Branch | Top module |
|---|---|---|---|
| Yi An | market engine | `branch-yian-market-engine` | `A_top` |
| Douglas | orders | `branch-douglas-orders` | `B_order_top` |
| Tricia | ledger | `branch-tricia-ledger` | `ledger` |
| Matthew | game, display | `branch-matthew-oled-ui` | `game_fsm` + display modules |

plus this `integration/` folder, which joins them. Nobody's modules are edited to make them fit.
Everything that joins the parts is in `Integration_Top.v`, in the section marked ADAPTERS.
The one exception is Yi An's data, cut to 180 days by team decision (see "Data" below).

## Where everyone's files are

Files stay where each person put them, so their own branches keep merging cleanly.

```
TradingSimProject/
├── integration/                                    TEAM (made by Douglas)
│   ├── Integration_Top.v                           wires everyone's parts together
│   ├── Integration.xdc                             pins (Matthew's, plus JA for the second OLED)
│   ├── create_integration_project.tcl              builds the Vivado project
│   ├── run_all_tests.tcl                           Vivado: runs every testbench
│   ├── run_all_tests.sh, run_sim.sh                the same with Icarus (Mac/Linux)
│   ├── tb_integration.v                            the whole game, end to end
│   └── tests/tb_yian_market.v, tb_matthew_game_fsm.v
│
├── TradingSimProject.srcs/sources_1/imports/storage/     YI AN
│   ├── A_top.v                                     (BUFFER_DEPTH set to 180 here)
│   ├── AMD_seed.mem, MCD_seed.mem                  (last 180 days here)
│   └── stock.v, day_ticker.v, lfsr.v, normalise_lfsr.v, market_state.v,
│       startup_seed.v, storage_buffer.v, get_30_values.v
│
├── PartB/                                          DOUGLAS
│   ├── src/shared/trading_defs.vh                  codes shared by everyone
│   ├── src/B_orders/                               B_order_top.v and its modules
│   ├── sim/                                        testbenches and test stand-ins
│   └── AI_USAGE_LOG.md
│
├── TradingSimProject.srcs/sources_1/new/           TRICIA and MATTHEW share this folder
│   ├── ledger.v, seq_divider.v, tb_seq_divider.v   Tricia
│   └── game_fsm.v, OLED_Renderer.v, text_layer.v, font_renderer.v,
│       quantity_7seg.v, binary_to_bcd_14bit.v      Matthew
├── TradingSimProject.srcs/sim_1/new/tb_ledger.v    Tricia
└── TradingSimProject.srcs/sources_1/imports/verilog_code_snippets/   MATTHEW
    └── input_btn/debouncer.v, clocks/slower_clk.v, output_oled/oled_display.v
```

Not used by this build: `TradingSimProject.xpr` (main's old copy), Matthew's `My_Top_Module.v`
(replaced by `Integration_Top`), the older `imports/new/Oled_Display.v` and `slower_clk.v`
(duplicates of Matthew's copies), the mouse files (the mouse is out), and `PartB/board/`
(Douglas's stand-alone demo).

## Opening it in Vivado (Windows)

Do **not** open `TradingSimProject.xpr` on this branch. Everyone's `.xpr` changes conflict
when merged, so this branch keeps `main`'s old one, which does not list the new files.
The script builds a fresh project instead.

1. Clone this branch to a short path with no spaces:
   ```
   git clone -b branch-team-integration https://github.com/yarnieee/TradingSimProject.git C:/EE2026/TradingSimProject
   ```
2. Open Vivado 2025.2 on its own, and in the **Tcl Console**:
   ```
   source C:/EE2026/TradingSimProject/integration/create_integration_project.tcl
   ```
   It creates `C:/EE2026/Integration_vivado` next to the repo, using the repo files in place.
3. Run the tests (next section).
4. Generate Bitstream. Check the utilisation and timing summaries (WNS should be positive),
   then Hardware Manager > Auto Connect > Program Device.

## Testing on another PC

With the project created, in the Vivado **Tcl Console**:
```
source C:/EE2026/TradingSimProject/integration/run_all_tests.tcl
```
It runs each testbench in turn and ends with a one-line-per-test summary. To run only some:
`set only_tbs {tb_integration tb_matthew_game_fsm}` before the `source`. To run one by hand:
under Simulation Sources, right-click the testbench > Set as Top, then Run Behavioral
Simulation, and look for its `PASS:` or `FAIL:` line in the Tcl Console.

| Testbench | Whose | Checks | Expected now |
|---|---|---|---|
| `tb_integration` | everyone | the whole game through Matthew's screens: buy, rejects (no position, closed stock, quantity 0), partial sell; Douglas's and Tricia's parts agree | PASS (15) |
| `tb_yian_market` | Yi An | starts from the newest data (19 Dec 2025); one tick and a new date per day; prices stay between $1 and $655.35, no day moving more than 25% | **FAIL** (2 of 5) until the stock.v fix below; passes with it |
| `tb_matthew_game_fsm` | Matthew | every screen transition, quantity digits and limits, reset | PASS (27) |
| `tb_ledger`, `tb_seq_divider` | Tricia | Tricia's own tests | PASS |
| `tb_BC_ledger` | Douglas + Tricia | 60 random orders against Tricia's real ledger, busy handshake, invariant | PASS (73) |
| `tb_order_validate`, `tb_order_book`, `tb_exec_engine`, `tb_ticket_screen`, `tb_B_order_top` | Douglas | order engine unit and end-to-end tests | PASS (29, 30, 21, 18, 52) |

These results are from Icarus Verilog on a Mac (`./run_all_tests.sh`). The Vivado runner has not been
run yet. If `tb_integration` or `tb_yian_market` reports prices of 0, the simulator did not find
`AMD_seed.mem` / `MCD_seed.mem`: copy both into `Integration_vivado/Integration.sim/sim_1/behav/xsim/`
and rerun.

## Data: last 180 trading days (team decision, 19 Oct)

To save space, Yi An's market engine keeps only the **most recent 180 trading days** of each stock
(was 1800): `AMD_seed.mem` and `MCD_seed.mem` hold their last 180 rows, **4 Apr 2025 to 19 Dec
2025**, and `A_top.v` has `BUFFER_DEPTH = 180`. The 720- and 1800-day chart windows cannot exist
with 180 days, so they are capped at 180 (port names unchanged). These are the only edits to Yi
An's files on this branch; Yi An should carry them into `branch-yian-market-engine`, so the
history of his files stays his.

## On the board

| | |
|---|---|
| sw[0] | reset (up = reset) |
| Buttons | Matthew's screens: title > portfolio > stocks > stock > buy/sell > quantity > confirm |
| JB (right OLED) | Matthew's game screens |
| JA (left OLED) | Douglas's order ticket: bid/ask of the selected stock, last fill or reject, pending orders. Temporary, until Yi An's chart page exists |
| 7-seg | Matthew's quantity |
| led[7:4] | Matthew's screen number |
| led[11:8] | pending orders (Douglas) |
| led[14] / led[15] | flash on reject / fill (Douglas) |

To buy: C (title) > R, C (stocks) > U/D to pick > C > C (buy) > R, C (quantity) > U to set >
C > R, R, C (confirmation). The order is placed on entering the confirm screen: JA shows
`FILL ...` or `REJ ...`, and the LEDs flash.

## How the parts are joined (the adapters in Integration_Top.v)

Each adapter is temporary. It disappears when the owner adds the signal from the Module I/O map.

| Adapter | Why | Replaced when |
|---|---|---|
| price0 = AMD, price1 = MCD, price2/3 = 0 | Yi An has 2 stocks, the plan has 4. Douglas's part treats a 0 price as closed (NOT LIVE) | Yi An outputs `price0..3` |
| `tick` from Yi An's date changing | the day tick is internal to `A_top` | Yi An outputs `tick` |
| The order = the move into Matthew's CONFIRM screen; side from the BUY or SELL screen; quantity = Matthew's `quantity` | `game_fsm` has no order output | Matthew outputs a confirm pulse and side |
| Selected stock: a copy of `game_fsm`'s `stocks_cursor` logic | `stocks_cursor` is internal to `game_fsm` | Matthew outputs `sel_stock` |
| `game_state` = PLAYING except on the title and game-end screens | no `game_state` output yet | Matthew outputs `game_state` |
| Quantity: Douglas's part accepts Matthew's 0-9999 and rejects anything outside 1-255 as BAD QTY | team decision, 19 Oct: orders stay 8-bit | Matthew may cap the quantity editor at 255 (optional) |
| Yi An's history outputs unconnected | not needed until the chart page exists | Yi An's chart page uses them |

## Known issues (owners to fix)

1. **Yi An, `stock.v`, `calculate_next_close`: prices pin at $655.35.** `previous_close` is
   unsigned, so the whole `random_term` expression is evaluated unsigned. When `random_offset`
   is negative it wraps to a huge positive number, the price clamps to 65535, and stays there.
   Checked in isolation: price 21343, offset -25 gives 65535 as written and 18675 with the fix.
2. **Yi An, same function: prices drift down 10% a day.** `stable_term` keeps 90% of the price and
   `random_term` adds at most a few percent back, so even the largest upward move ends lower
   (21343 to 20275). The usual form is `next = previous + previous * VOLATILITY * offset / 10000`.

   With both fixes, `tb_yian_market` passes (tried on a scratch copy, not committed):
   ```verilog
   integer prev_signed;                       // add next to the other integers
   ...
   prev_signed = previous_close;
   stable_term = prev_signed;
   random_term = prev_signed * VOLATILITY * random_offset / 10000;
   result = stable_term + random_term;
   ```
   Even fixed, prices still lean downward over 60 days (AMD $213 to $123), which may come from the
   market-state adjustment or the random value's centre. [ASSUMPTION: not investigated further.]
3. **Yi An, `$readmemh("storage/AMD_seed.mem")`:** the path includes a folder. If Vivado reports it
   cannot open the file during synthesis, change the path to just `AMD_seed.mem` (the script adds
   both .mem files to the project). [ASSUMPTION: Vivado resolves .mem files added to the project
   by file name. Not tested here.] The testbenches already use the plain names.
4. **Size.** A Yosys synthesis with the full 1800 days estimated about 19,800 LUTs (95% of the
   chip), almost all in Yi An's market engine; Douglas's, Tricia's and Matthew's parts together
   are about 2,300. The 180-day data cuts the seed ROMs by 10x; the per-day price and calendar
   arithmetic (divides by 100 and 10000) also costs LUTs. Check Vivado's utilisation report.
   [ASSUMPTION: the 180-day build was not synthesised here.]
5. **`TradingSimProject.xpr` on this branch is `main`'s** and does not list the new files. Use the
   script. When the branches go into `main`, one person should rebuild the `.xpr` (Add Sources in
   Vivado) rather than merging the XML.
