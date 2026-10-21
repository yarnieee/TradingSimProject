# Douglas: order engine and Order Ticket page

Branch `branch-douglas-orders`. The order and execution engine (Component B in the team
plan): it takes an order, checks it against cash and positions, fills it at the bid or ask,
keeps limit and stop orders in an 8-slot book, sends fills to Tricia's ledger, and draws the
Order Ticket page.

Target: Vivado 2025.2, Basys3 (`xc7a35tcpg236-1`), Verilog-2001, one 100 MHz clock,
synchronous active-high `sys_reset`.

## Where the files are

In the team build (`branch-team-integration`) everything is in this folder:

```
3_Douglas_Orders/
├── B_order_top.v            top module: what the team build instantiates
├── submodules/
│   ├── order_entry.v        ticket fields: buttons, or a whole order from Matthew's confirm screen
│   ├── order_validate.v     the checks: ok, or a reject code
│   ├── exec_engine.v        one job at a time: submits and book triggers -> fill / reject / book insert
│   ├── order_book.v         8-slot book for limit and stop orders, scanned after every tick
│   ├── spread_calc.v        price -> bid and ask
│   ├── ticket_screen.v      Order Ticket page pixels (FLIP_180 turns it upside down)
│   ├── b_bin2bcd_seq.v      binary to decimal digits for the page
│   ├── stub_font.v          3x5 font, until Matthew's font module is shared
│   └── ticket_layout.vh     where the ticket's boxes are drawn
├── tb/                      tests (below), stub_market.v, stub_ledger.v, hex2png.py
├── board_test/              B_demo_top.v, b_demo_btn.v, tb_B_demo_top.v, B_demo.xdc
├── README.md
└── AI_USAGE_LOG.md          what was AI-generated
```

`trading_defs.vh` (codes shared by everyone) is in `1_Shared_Modules/`. On `branch-douglas-orders`
itself the same files are in `TradingSimProject.srcs/` (design in `sources_1/new/`, tests in
`sim_1/new/`).

## Testing in Vivado

`0_Integrated_Top/create_integration_project.tcl` adds these testbenches to the team project, and
`0_Integrated_Top/run_all_tests.tcl` runs them. See the README at the repo root.

| Testbench | Checks | Result |
|---|---|---|
| `tb_order_validate` | every reject code and the order they are checked in | PASS (29) |
| `tb_order_book` | insert, cancel, full book, the four trigger rules, gaps, slot order, rescan, reset | PASS (30) |
| `tb_exec_engine` | fills, rejects, waiting on `ledger_busy`, priority, book triggers | PASS (21) |
| `tb_ticket_screen` | key pixels of the page, and the upside-down (FLIP_180) version matching it pixel for pixel; writes frame dumps | PASS (21) |
| `tb_B_order_top` | the spec's 13 scenarios plus orders from Matthew's confirm screen and closed stocks | PASS (52) |
| `tb_BC_ledger` | 60 random orders against Tricia's real ledger | PASS (73) |

## How it works

```
order_entry --submit--> exec_engine --fill--> Tricia's ledger, Matthew
                          ^    |   \--reject--> Matthew
                 trq/ack  |    v insert
                        order_book
ticket_screen draws from all of the above
```

- `exec_engine` runs one job at a time: IDLE, CHECK (wait for `!ledger_busy`, latch the price),
  EVAL (validate, then fill, insert into the book, or reject), POST (one clock so the ledger can
  raise `ledger_busy`). New orders go before book triggers.
- `order_book` checks one slot per clock after each tick through one shared comparator, and
  hands each hit to `exec_engine`, which checks it again against current cash and position.
  If that fails the order is cancelled (`TRIG FAIL`), so cash can never go negative even though
  pending orders don't reserve anything.
- Market buys fill at the ask (price + 5c), sells at the bid (price - 5c), with a $1 fee.

## Ports (`B_order_top`, follows the team's Module I/O map)

| From / to | Signals |
|---|---|
| top | `clk`, `xR [6:0]`, `yR [5:0]` (pixel being drawn) |
| from Yi An | `price0..3 [15:0]`, `tick` |
| from Tricia | `cash [31:0]`, `pos0..3 [9:0]`, `ledger_busy` |
| from Matthew | `sys_reset`, `game_state [1:0]`, `sel_stock [1:0]`, `page_R`, `btn_pulse [4:0]`, and a whole order from the confirm screen: `ord_req` (pulse), `ord_side`, `ord_type [1:0]`, `ord_qty [13:0]`, `ord_trig [15:0]` |
| to Tricia and Matthew | `fill`, `fill_stock [1:0]`, `fill_side`, `fill_qty [7:0]`, `fill_price [15:0]`, `fill_fee [15:0]` |
| to Matthew | `reject`, `reject_code [2:0]`, `pending_count [3:0]`, `ticket_pixel [15:0]` |

- Matthew's quantity is 0-9999; orders are accepted for 1-255 and anything else is rejected as
  `BAD QTY` (team decision, 19 Oct).
- A stock with price 0 (no data from Yi An yet) is closed: orders are rejected as `NOT LIVE`
  and its pending orders never trigger.
- The encodings of Matthew's signals (`game_state`, `page_R`, button bit order) are in
  `trading_defs.vh`, as proposed defaults until Matthew confirms them.

## Stand-alone board test (`board_test/`)

`B_demo_top` puts the order engine on the board by itself: the ticket on the OLED in JB, the five
buttons, a fake market (sw[1:0] makes it flat, rise or fall), sw[3:2] picks the stock, sw[15]
resets, LEDs show position, pending orders, fills and rejects. The team build replaces it; it is
kept for debugging. To use it, make a Vivado project with `board_test/*.v`, `B_order_top.v`,
`submodules/*`, `tb/stub_market.v`, `tb/stub_ledger.v`, `1_Shared_Modules/trading_defs.vh` and
`board_test/B_demo.xdc`, with `B_demo_top` as top. It uses the course `Oled_Display` module
(in `9_Not_Used/old_duplicates/`).

## Decisions (judgement calls, change them if the team disagrees)

| # | What | Why |
|---|---|---|
| 1 | No mouse: the five buttons, or Matthew's confirm screen, are the only input (team, 17 Oct) | the mouse was removed from the project |
| 2 | Decimal digits are made by a sequential converter (16 clocks per value) | a combinational one is a likely timing failure at 100 MHz (inference, not measured) |
| 3 | A buy that would take a position past 1023 is rejected as `BAD QTY` | positions are 10 bits and would wrap in the ledger; no spare reject code |
| 4 | A sell whose proceeds are below the $1 fee, with cash near 0, is rejected as `NO CASH` | otherwise cash goes negative |
| 5 | A triggered order fills at the bid/ask the book saw when it triggered | a limit order never fills worse than its limit |
| 6 | The book only scans while the game is PLAYING | no trading outside the game |
| 7 | A limit that is already marketable waits for the next tick instead of filling at once | one code path for pending orders |
| 8 | A reject shows for 2 s, then the last fill or placed order shows again | the spec only described fill and reject |
| 9 | The trigger price re-centres on the market when the stock changes | so it starts near the price |
| 10 | Quantity starts at 1 | the spec gave no default |
| 11 | Orders stay 1-255 shares; Matthew's 0-9999 is checked here (team, 19 Oct) | no change needed to Tricia's ledger or Matthew's code |
| 12 | Stocks with no price are closed | Yi An's engine has 2 stocks for now; the plan has 4 |

## For the team

- **Tricia:** `ledger_busy` must go high on the clock after `fill`, and cash and positions must be
  updated on the clock it drops. Her ledger does this (tested in `tb_BC_ledger`).
- **Yi An:** the book scans on the clock after `tick`, so all four new prices must be visible by
  then. Pulse `tick` after the last stock updates.
- **Matthew:** the ticket page needs a 3x5 font with `stub_font.v`'s port (`ch`, `row`, `col` in,
  `pix` out). Character codes are in `trading_defs.vh`.
