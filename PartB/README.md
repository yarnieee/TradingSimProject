# EE2026 FPGA Paper Trading Simulator: Part B

Order and execution engine, plus the Order Ticket page (right OLED, page 1).
Build spec: `EE2026_PartB_order_engine_spec.md`. Team plan: `EE2026_trading_sim_plan.md`.

Target: Vivado 2025.2, Basys3 (`xc7a35tcpg236-1`), Verilog-2001, one 100 MHz clock,
synchronous active-high `sys_reset`.

All paths in this README are relative to this `PartB/` folder. The files are not yet
added to `TradingSimProject.xpr`; see "In Vivado" below.

## Status (5 Oct 2026)

| Phase | Scope | State |
|---|---|---|
| P1 | MKT orders, validation, fill bus, button fallback, ticket page v1 | built, simulated |
| P2 | 4 stocks, LMT/STP book, trigger scan, re-validation, mouse, scroll | built, simulated |
| P3 | pending list view, cancel by click, SL/TP shortcuts | not started (`order_book` already has the cancel and read ports) |

"Simulated" means Icarus Verilog only. A Yosys `synth_xilinx` pass found no inferred
latches and estimated about 1,150 LUTs, 460 FFs and 2 DSPs for `part_b_top` with the stub
font (roughly 5.5% of the xc7a35t's LUTs). That is an estimate from a different tool.
**Not yet done:** Vivado synthesis, timing and utilisation, and anything on the board.

## Layout

```
src/shared/trading_defs.vh      [TEAM] widths, side/type/reject codes, font char codes
src/B_orders/ticket_layout.vh   button boxes: shared by hit-testing and drawing
src/B_orders/part_b_top.v       what the team top level instantiates
src/B_orders/order_entry.v      ticket fields, click/scroll/button decoding
src/B_orders/order_validate.v   combinational checks -> ok / reject_code
src/B_orders/order_book.v       8-slot pending book, time-shared trigger scan
src/B_orders/exec_engine.v      arbiter: submits + book triggers -> fill / reject / insert
src/B_orders/spread_calc.v      mid -> bid/ask
src/B_orders/b_bin2bcd_seq.v    sequential double-dabble (B's copy until D's exists)
src/B_orders/ticket_screen.v    Ticket page pixel logic
sim/stubs/stub_market.v         fake prices + tick (A)
sim/stubs/stub_ledger.v         behavioural ledger (C), fails the sim on bad state
sim/stubs/stub_font.v           3x5 font (D), synthesisable
sim/B_orders/tb_*.v             self-checking testbenches
sim/run_iverilog.sh             runs every testbench, converts frame dumps to PNG
tools/hex2png.py                frame dump -> PNG
```

## Running the tests

With Icarus Verilog (`brew install icarus-verilog`) and Python 3 with Pillow:

```bash
PartB/sim/run_iverilog.sh
```

(from the repo root; the script finds its own paths, so it works from anywhere)

Expected output, one line per testbench:

```
PASS: tb_order_validate (27 checks)
PASS: tb_order_book (30 checks)
PASS: tb_exec_engine (21 checks)
PASS: tb_ticket_screen (18 checks)
PASS: tb_part_b_top (46 checks)
```

Logs, frame dumps (`ticket_frame*.hex`) and PNGs land in `sim/out/`.

### In Vivado

1. In `TradingSimProject.xpr`, use Add Sources > Add Files and **untick "Copy sources
   into project"**, so these `PartB/` files stay the only copy. Add `src/shared/*.vh` and
   `src/B_orders/*` as design sources, plus `sim/stubs/stub_font.v` (the ticket page
   needs a font until D's ROM is in).
2. Add `sim/stubs/stub_market.v`, `sim/stubs/stub_ledger.v` and `sim/B_orders/tb_*.v`
   as simulation sources. Set the testbench you want as the simulation top.
3. If Vivado cannot find `trading_defs.vh` or `ticket_layout.vh`, add `src/shared`
   and `src/B_orders` under Settings > General > Verilog options > Include directories.
4. Run behavioural simulation for at least 200 us (`tb_part_b_top` ends at about 183 us).
   Look for the `PASS:` line in the Tcl console. The frame dumps are written to the
   simulation run directory (`<project>.sim/sim_1/behav/xsim/`).

## How it fits together

```
order_entry --submit--> exec_engine --fill--> C, D
                         ^    |   \--reject--> D
                trq/ack  |    v ins
                       order_book
ticket_screen draws from all of the above
```

- `exec_engine` runs one job at a time: IDLE, CHECK (wait for `!ledger_busy`, latch the
  price), EVAL (validate, then fill, insert or reject), POST (one dead clock so C can raise
  `ledger_busy`). Submits beat book triggers.
- `order_book` scans one slot per clock after each tick through one comparator path, and
  hands each hit to `exec_engine`, which re-validates it against current cash and position.
  A failed re-validation cancels the order with `RJ_TRIG_FAIL`, so cash can never go negative
  even though pending orders do not reserve anything.

## Decisions and deviations from the spec

Each one is a judgement call; change it if the team disagrees.

| # | What | Why |
|---|---|---|
| 1 | QTY/TRG `[-]` hit regions are x 62-72 and `[+]` 74-84 (spec: 62-70, 74-82) | the drawn `[-][+]` glyphs end at x 72 and 84; the hit area now matches what is drawn |
| 2 | Number conversion is a sequential double-dabble (16 clocks per value), not combinational | a 16-stage add-3 chain is a likely timing failure at 100 MHz (inference, not measured). One converter refreshes all six values round-robin |
| 3 | Extra check: BUY that would push a position past 1023 is rejected as `RJ_BAD_QTY` | position is 10 bits and would wrap in C. All 8 reject codes are used, so this reuses one |
| 4 | Extra check: SELL whose proceeds are below the $1 fee, with cash near 0, is `RJ_NO_CASH` | otherwise cash goes negative (e.g. sell 1 share at $0.95 with $0.04 cash) |
| 5 | A triggered order fills at the bid/ask the book saw when it triggered | guarantees a limit order never fills worse than its limit, even if it queues behind other fills |
| 6 | The book only scans while `game_live`; if the game ends mid-scan, remaining hits are cancelled with `RJ_TRIG_FAIL` | no trading outside PLAYING |
| 7 | A marketable limit (e.g. LMT BUY above the ask) rests until the next tick, it does not fill on submit | keeps one code path for pending orders |
| 8 | Status line: a reject shows for 2 s, then falls back to the last fill or placed message. Placed orders show as `LMT  B010@120.00` in white | spec only described fill and reject |
| 9 | `trig` re-centres on the market when the stock changes, and once after reset when the price first becomes non-zero | spec covered stock change only; after reset the trigger would otherwise start at 0 |
| 10 | `qty` starts at 1 after reset | spec gave no default |
| 11 | Scenario 4 (qty 0) cannot be reached through the UI, since qty clamps to 1..255 | `tb_part_b_top` forces the register to 0 to test the path; the unit testbenches also cover it |
| 12 | `stub_font` has the 3x5 set only, no 5x7 | Part B does not use 5x7 |
| 13 | Not built: `sw[7:0]` as a binary quantity (team plan section 5) | not in the Part B port list in the spec |

## For the team

- **[TEAM] `ledger_busy` from C:** must go high on the clock after `fill`, or earlier,
  and C's cash and positions must already be updated on the clock it drops.
  `stub_ledger.v` is a working reference model.
- **[TEAM] `tick` from A:** `order_book` starts scanning on the clock after `tick`. All four
  new prices must be visible by then. If A updates the stocks one after another, it should
  pulse `tick` after the last one.
- **[TEAM] `ui_screen`:** the plan has it as 2 bits; the Part B spec and this code use 1 bit
  (0 left, 1 right).
- **[TEAM] Font:** the ticket page needs a 3x5 font with the port of `stub_font.v`
  (`ch`, `row`, `col` in, `pix` out, combinational). Character codes are in `trading_defs.vh`.
- **[TEAM]** `ledger_busy` and `ticket_active` still need adding to the plan's interface table.
