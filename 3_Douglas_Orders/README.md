# Douglas: order engine

Checks each order against cash and positions, fills it, sends the fill to Tricia's ledger, and
draws the order ticket page (left OLED).

## Files

| File | What it does |
|---|---|
| `B_order_top.v` | top module |
| `submodules/order_entry.v` | takes the order from Matthew's confirm screen |
| `submodules/order_validate.v` | accepts or rejects the order |
| `submodules/exec_engine.v` | fills or rejects, one order at a time |
| `submodules/order_book.v` | holds up to 8 limit/stop orders |
| `submodules/spread_calc.v` | price to bid and ask |
| `submodules/ticket_screen.v` | draws the ticket page |
| `submodules/b_bin2bcd_seq.v`, `stub_font.v`, `ticket_layout.vh` | helpers for the page |
| `tb/` | tests |
| `board_test/` | board test of this part on its own (not in the team build) |

## Rules

- Buys fill at price + 5c, sells at price - 5c, plus a $1 fee.
- Quantity must be 1-255.
- A stock with price 0 is closed.
- The ticket page is drawn upside down (`TICKET_FLIP_180`), because the left OLED is mounted upside down.
