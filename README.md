# EE2026 Trading Simulator: team build

Branch `branch-team-integration`. Everyone's work in one build, laid out by person:

```
0_Integrated_Top/          the board's top module, its pins, the Vivado scripts, the whole-game test
│   Integration_Top.v        wires everyone's parts together
│   Integration.xdc          pins (Matthew's, plus JA for the second OLED)
│   create_integration_project.tcl   builds the Vivado project
│   run_all_tests.tcl        runs every testbench in Vivado
│   tb_integration.v         the whole game, end to end
│
1_Shared_Modules/          used by the top or by everyone
│   debouncer.v, slower_clk.v, oled_display.v, trading_defs.vh
│
2_YiAn_Market_Engine/      YI AN        top module: A_top.v
│   submodules/              lfsr, normalise_lfsr, startup_seed, day_ticker, market_state,
│                            stock, storage_buffer, get_30_values, get_latest_values
│   data/                    AMD_seed.mem, MCD_seed.mem (last 180 trading days)
│   tb/                      tb_yian_market.v
│
3_Douglas_Orders/          DOUGLAS      top module: B_order_top.v
│   submodules/              order_entry, order_validate, exec_engine, order_book, spread_calc,
│                            ticket_screen, b_bin2bcd_seq, stub_font, ticket_layout.vh
│   tb/                      5 order engine tests, tb_BC_ledger, test stand-ins
│   board_test/              stand-alone board test of the order engine (not in the team build)
│   README.md, AI_USAGE_LOG.md
│
4_Tricia_Ledger/           TRICIA       top module: ledger.v
│   submodules/              ledger_fsm, ledger_validate, seq_divider
│   tb/                      tb_ledger.v, tb_seq_divider.v
│
5_Matthew_Display/         MATTHEW      game_fsm.v, OLED_Renderer.v, quantity_7seg.v
│   submodules/              text_layer, font_renderer, binary_to_bcd_14bit
│   tb/                      tb_matthew_game_fsm.v
│
9_Not_Used/                kept for reference, not in the build: the old top level and its pins,
                           older duplicate files, the mouse files, unused code snippets, the old .xpr
```

Each person's branch (`branch-yian-market-engine`, `branch-douglas-orders`, `branch-tricia-ledger`,
`branch-matthew-oled-ui`) is merged in here, and the files are then placed in that person's
folder. Matthew has no single top module yet: his three blocks are wired straight into
`Integration_Top`.

## Opening it in Vivado (Windows)

1. Clone this branch to a short path with no spaces:
   ```
   git clone -b branch-team-integration https://github.com/yarnieee/TradingSimProject.git C:/EE2026/TradingSimProject
   ```
2. Open Vivado 2025.2 on its own (there is no `.xpr` to open), and in the **Tcl Console**:
   ```
   source C:/EE2026/TradingSimProject/0_Integrated_Top/create_integration_project.tcl
   ```
   It creates `C:/EE2026/Integration_vivado` next to the repo, using the repo files in place.
3. Run the tests (next section).
4. Generate Bitstream. Check the utilisation and timing summaries (WNS should be positive), then
   Hardware Manager > Auto Connect > Program Device.

If you already have `Integration_vivado` from before, run step 2 again: the files have moved.

## Testing

In the Vivado **Tcl Console**, with the project created:
```
source C:/EE2026/TradingSimProject/0_Integrated_Top/run_all_tests.tcl
```
It runs each testbench and ends with a one-line-per-test summary. To run only some:
`set only_tbs {tb_integration tb_matthew_game_fsm}` before the `source`. To run one by hand: under
Simulation Sources, right-click it > Set as Top, then Run Behavioral Simulation, and look for its
`PASS:` or `FAIL:` line in the Tcl Console.

| Testbench | Folder | Checks | Expected now |
|---|---|---|---|
| `tb_integration` | 0_Integrated_Top | the whole game through Matthew's screens: buy, rejects (no position, closed stock, quantity 0), partial sell; order engine and ledger agree | PASS (15) |
| `tb_yian_market` | 2_YiAn_Market_Engine | starts from the newest data (19 Dec 2025); one tick and a new date per day; prices stay between $1 and $655.35, no day moving more than 25% | **FAIL** (2 of 5) until the stock.v fix below |
| `tb_order_validate`, `tb_order_book`, `tb_exec_engine`, `tb_ticket_screen`, `tb_B_order_top` | 3_Douglas_Orders | order engine tests, including the upside-down ticket fix | PASS (29, 30, 21, 21, 52) |
| `tb_BC_ledger` | 3_Douglas_Orders | 60 random orders against Tricia's real ledger | PASS (73) |
| `tb_ledger`, `tb_seq_divider` | 4_Tricia_Ledger | Tricia's own tests | PASS |
| `tb_matthew_game_fsm` | 5_Matthew_Display | every screen transition, quantity digits and limits, reset | PASS (27) |

These were checked in simulation before this branch was pushed; the Vivado runner itself has not
been run yet. If `tb_integration` or `tb_yian_market` reports prices of 0, the simulator did not find
`AMD_seed.mem` / `MCD_seed.mem`: copy both into `Integration_vivado/Integration.sim/sim_1/behav/xsim/`
and rerun.

## On the board

| | |
|---|---|
| sw[0] | reset (up = reset) |
| Buttons | Matthew's screens: title > portfolio > stocks > stock > buy/sell > quantity > confirm |
| JB (right OLED) | Matthew's game screens |
| JA (left OLED) | Douglas's order ticket: bid/ask of the selected stock, last fill or reject, pending orders. Drawn rotated 180 degrees, because that OLED sits upside down on the board. Temporary, until Yi An's chart page exists |
| 7-seg | Matthew's quantity |
| led[7:4] | Matthew's screen number |
| led[11:8] | pending orders |
| led[14] / led[15] | flash on reject / fill |

To buy: C (title) > R, C (stocks) > U/D to pick > C > C (buy) > R, C (quantity) > U to set > C >
R, R, C (confirmation). The order is placed on entering the confirm screen.

## Data: last 180 trading days (team decision, 19 Oct)

Yi An's `A_top` keeps the most recent 180 trading days (`BUFFER_DEPTH = 180`, and the 720/1800-day
outputs are gone). `data/AMD_seed.mem` and `data/MCD_seed.mem` hold their last 180 rows,
**4 Apr 2025 to 19 Dec 2025**. Yi An's own branch still has the full 1800-row files, which with a
depth of 180 would load the *oldest* 180 days (2018); use the trimmed files.

## How the parts are joined (in Integration_Top.v)

Each of these is temporary, until the owner adds the signal from the Module I/O map.

| Join | Why | Replaced when |
|---|---|---|
| price0 = AMD, price1 = MCD, price2/3 = 0 | Yi An has 2 stocks, the plan has 4; a 0 price means closed | Yi An outputs `price0..3` |
| `tick` from Yi An's date changing | the day tick is inside `A_top` | Yi An outputs `tick` |
| Seed files pointed at by name (`defparam`) | `A_top` asks for `storage/data/...`, a folder that does not exist here | Yi An uses plain file names |
| The order = the move into Matthew's CONFIRM screen; side from BUY or SELL; quantity = Matthew's `quantity` | `game_fsm` has no order output | Matthew outputs a confirm pulse and side |
| Selected stock: a copy of `game_fsm`'s `stocks_cursor` logic | `stocks_cursor` is inside `game_fsm` | Matthew outputs `sel_stock` |
| `game_state` = PLAYING except on the title and game-end screens | no `game_state` output yet | Matthew outputs `game_state` |
| Quantities outside 1-255 rejected as BAD QTY | team decision, 19 Oct: orders stay 8-bit | Matthew may cap his quantity at 255 |

## Known issues (owners to fix)

1. **Yi An, `stock.v`, `calculate_next_close`: prices pin at $655.35.** `previous_close` is
   unsigned, so the whole `random_term` expression is evaluated unsigned. When `random_offset`
   is negative it wraps to a huge number, and the price clamps to 65535 and stays there.
2. **Yi An, same function: prices drift down 10% a day.** `stable_term` keeps 90% of the price and
   `random_term` adds at most a few percent back. With both fixes, `tb_yian_market` passes
   (tried on a scratch copy, not committed):
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
3. **Seed files in Vivado.** The script adds both `.mem` files to the project and `Integration_Top`
   points at them by name. [ASSUMPTION: Vivado finds `.mem` files added to the project by name, in
   synthesis and simulation. Not tested here.] If it reports it cannot open `AMD_seed.mem`, copy
   both files into the synthesis or simulation run folder.
4. **Size.** With the old 1800 days, a Yosys estimate put the build at about 95% of the chip's LUTs,
   almost all in the market engine; the other three parts together are about 2,300 LUTs. The
   180-day data cuts that a lot, but check Vivado's utilisation report.
