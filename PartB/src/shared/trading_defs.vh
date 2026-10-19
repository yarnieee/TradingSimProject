// trading_defs.vh
// [TEAM] Codes and widths shared by parts A, B, C and D.
// Change only by team agreement: every part decodes these values.

`ifndef TRADING_DEFS_VH
`define TRADING_DEFS_VH

// ---------------------------------------------------------------- widths
`define W_PRICE 16     // cents, unsigned: $0.00 - $655.35
`define W_QTY    8     // order qty 1..255
`define W_POS   10     // position 0..1023 (no shorts in core)
`define W_CASH  32     // cents, unsigned

// ---------------------------------------------------------------- side
`define SIDE_BUY  1'b0
`define SIDE_SELL 1'b1

// ---------------------------------------------------------------- order type
`define OT_MKT 2'd0
`define OT_LMT 2'd1
`define OT_STP 2'd2

// ---------------------------------------------------------------- reject codes
`define RJ_NONE      3'd0
`define RJ_NO_CASH   3'd1   // buy cost + fee > cash
`define RJ_NO_POS    3'd2   // sell qty > position
`define RJ_BOOK_FULL 3'd3   // no free pending slot
`define RJ_BAD_QTY   3'd4   // qty == 0
`define RJ_BAD_TRIG  3'd5   // LMT/STP with trigger == 0
`define RJ_TRIG_FAIL 3'd6   // pending order hit but failed re-validation -> cancelled
`define RJ_NOT_LIVE  3'd7   // game not in PLAYING state

// ---------------------------------------------------------------- UI bus (from D)
// [TEAM][ASSUMPTION] Encodings D owns. Proposed in the Module I/O map, for
// Matthew to confirm. Every part decodes these, so change them only here.
// (No mouse: ui_click, ui_screen, ui_x, ui_y and qty_delta were removed 17 Oct.)
`define GS_MENU        2'd0   // game_state
`define GS_PLAYING     2'd1
`define GS_RESULT      2'd2
`define PG_L_CHART     1'b0   // page_L
`define PG_L_OVERVIEW  1'b1
`define PG_R_TICKET    1'b0   // page_R
`define PG_R_PORTFOLIO 1'b1
// btn_pulse bit positions, in Basys3 master XDC order (btnC, btnU, btnL, btnR, btnD)
`define BTN_C 0
`define BTN_U 1
`define BTN_L 2
`define BTN_R 3
`define BTN_D 4

// ---------------------------------------------------------------- font
// [TEAM][ASSUMPTION] Character codes for the shared font ROM (D owns it).
// Digits 0..9 are codes 0..9, so a BCD digit d is char {2'b00, d}.
// Letters A..Z are codes 10..35.
`define CH_W      6         // char code width
`define CH_0      6'd0
`define CH_A      6'd10
`define CH_SPACE  6'd36
`define CH_DOT    6'd37
`define CH_PLUS   6'd38
`define CH_MINUS  6'd39
`define CH_PCT    6'd40
`define CH_DOLLAR 6'd41
`define CH_COLON  6'd42
`define CH_SLASH  6'd43
`define CH_AT     6'd44
`define CH_LBR    6'd45
`define CH_RBR    6'd46
`define CH_GT     6'd47

`endif
