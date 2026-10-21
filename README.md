# EE2026 Trading Simulator

The team build: everyone's parts joined in one Vivado project for the Basys3.

## Folders

| Folder | Owner | Top module |
|---|---|---|
| `0_Integrated_Top/` | team | `Integration_Top.v`, plus pins, Vivado scripts, whole-game test |
| `1_Shared_Modules/` | team | debouncer, clock divider, OLED driver, shared codes |
| `2_YiAn_Market_Engine/` | Yi An | `A_top.v` |
| `3_Douglas_Orders/` | Douglas | `B_order_top.v` |
| `4_Tricia_Ledger/` | Tricia | `ledger.v` |
| `5_Matthew_Display/` | Matthew | `D_display_top.v` |
| `9_Not_Used/` | | old files, not in the build |

Each person's folder: top module, `submodules/`, `tb/` (tests).

Naming (team doc): top modules are `A_`/`B_`/`C_`/`D_<description>_top` (A Yi An, B Douglas,
C Tricia, D Matthew). Still to rename by their owners: `A_top` to `A_market_top`, `ledger` to
`C_portfolio_top` (the names in the doc's Module I/O map).

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

- **sw[0]:** reset
- **Buttons:** move through the game screens
- **Right OLED:** game screens
- **Left OLED:** order ticket
- **7-seg:** quantity
- **LEDs:** fill / reject flash, pending orders

To buy: pick a stock, choose BUY, set the quantity, then choose confirm.
