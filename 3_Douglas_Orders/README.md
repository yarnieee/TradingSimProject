# Douglas: order engine

Checks each order against cash and positions, fills it, sends the fill to Tricia's ledger, keeps
limit, stop, stop-loss and take-profit orders in an 8-slot book, and draws the order ticket page
(left OLED).

## Files

| File | What it does |
|---|---|
| `B_order_top.v` | top module (its header lists every input and output and where it connects) |
| `submodules/order_entry.v` | the ticket's fields and buttons, or an order from Matthew's confirm screen |
| `submodules/order_validate.v` | accepts or rejects an order |
| `submodules/exec_engine.v` | fills or rejects, one order at a time; places the stop-loss/take-profit pair |
| `submodules/order_book.v` | 8 pending orders, checked every tick; linked stop-loss/take-profit pairs; cancel |
| `submodules/spread_calc.v` | price to bid and ask |
| `submodules/ticket_screen.v` | draws the ticket page and the ORDERS list |
| `submodules/font_3x5.v` | 3x5 font (63 characters) |
| `submodules/b_bin2bcd_seq.v`, `ticket_layout.vh` | helpers for the page |
| `tb/` | tests |
| `board_test/` | board test of this part on its own (not in the team build) |

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

- MKT fills now. LMT waits for a better price (buy at or below, sell at or above the trigger).
  STP (stop) waits for the price to move past the trigger (buy at or above, sell at or below).
- SL/TP: when a buy fills, a stop-loss below and a take-profit above it are placed. When one fills
  or is cancelled, the other is removed.

## Rules

- Buys fill at price + 5c, sells at price - 5c, plus a $1 fee.
- Quantity must be 1-255. A stock with price 0 is closed.
- A buy with SL/TP needs 2 free slots (3 if it is a limit or stop order).
- The ticket page is drawn upside down (`TICKET_FLIP_180`), because the left OLED is mounted upside down.
