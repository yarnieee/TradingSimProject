# Douglas: order engine

Checks each order against cash and positions, fills it at the bid or ask, keeps limit, stop,
stop-loss and take-profit orders in an 8-slot book, sends fills to Tricia's ledger, and draws
the order ticket page.

## Files (`TradingSimProject.srcs/`)

| File | What it does |
|---|---|
| `sources_1/new/B_order_top.v` | top module |
| `order_entry.v` | the ticket's fields and buttons, or an order from Matthew's confirm screen |
| `order_validate.v` | accepts or rejects an order |
| `exec_engine.v` | fills or rejects, one order at a time; places the stop-loss/take-profit pair |
| `order_book.v` | 8 pending orders, checked every tick; linked stop-loss/take-profit pairs; cancel |
| `spread_calc.v` | price to bid and ask |
| `ticket_screen.v` | draws the ticket page and the ORDERS list |
| `font_3x5.v` | 3x5 font (63 characters) |
| `b_bin2bcd_seq.v`, `ticket_layout.vh`, `trading_defs.vh` | helpers, shared codes |
| `B_demo_top.v`, `b_demo_btn.v`, `constrs_1/new/B_demo.xdc` | board test of this part on its own |
| `sim_1/new/` | tests |

## Using the ticket

Left/right moves between the fields: **stock > QTY > TRG > SL/TP > SUBMIT > ORDERS**.

| Field | Up / down | Centre |
|---|---|---|
| stock | next / previous stock | |
| QTY | quantity +1 / -1 | BUY / SELL |
| TRG | trigger price +5c / -5c | MKT / LMT / STP |
| SL/TP | OFF, 2%, 5%, 10% | |
| SUBMIT | | place the order |
| ORDERS | move the cursor | cancel that order |

- **SL/TP:** when a buy fills, two sell orders are placed: a stop-loss below the fill price and a
  take-profit above it, by the chosen %. When one fills or is cancelled, the other is removed.
  Orders from Matthew's confirm screen also use this setting.
- **ORDERS** lists all 8 slots. Stop-loss legs show as SL (red), take-profit legs as TP (green).

## Rules

- Buys fill at price + 5c, sells at price - 5c, plus a $1 fee.
- Quantity must be 1-255. A stock with price 0 is closed.
- A buy with SL/TP needs 2 free slots (3 if it is a limit or stop order).
- A pending order is checked again when it triggers; if it now fails, it is cancelled (TRIG FAIL).

## Tests

| Testbench | Checks |
|---|---|
| `tb_order_validate` | 36 |
| `tb_order_book` | 47 |
| `tb_exec_engine` | 31 |
| `tb_ticket_screen` | 41 |
| `tb_B_order_top` | 78 |
| `tb_BC_ledger` (with Tricia's ledger) | 73 |
| `tb_B_demo_top` | 8 |

## In the team build

The ticket needs the buttons to place limit, stop and SL/TP orders. `page_R = 0` (Ticket) and
`btn_pulse` give it the buttons; Matthew's screens should ignore them while that is on, e.g. while
a switch is up. Matthew's market orders work without this.
