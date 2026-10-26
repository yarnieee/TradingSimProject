// trading_defs.vh
// [TEAM] Codes and widths shared by everyone (Yi An, Douglas, Tricia, Matthew).
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

// ---------------------------------------------------------------- stop-loss / take-profit (Douglas)
// Distance of the automatic stop-loss and take-profit from a buy's fill price.
`define BRK_OFF 2'd0
`define BRK_2   2'd1   // 2%
`define BRK_5   2'd2   // 5%
`define BRK_10  2'd3   // 10%

// ---------------------------------------------------------------- reject codes
`define RJ_NONE      3'd0
`define RJ_NO_CASH   3'd1   // buy cost + fee > cash
`define RJ_NO_POS    3'd2   // sell qty > position
`define RJ_BOOK_FULL 3'd3   // no free pending slot
`define RJ_BAD_QTY   3'd4   // qty == 0
`define RJ_BAD_TRIG  3'd5   // LMT/STP with trigger == 0
`define RJ_TRIG_FAIL 3'd6   // pending order hit but failed re-validation -> cancelled
`define RJ_NOT_LIVE  3'd7   // game not in PLAYING state

// ---------------------------------------------------------------- UI bus (from Matthew)
// [TEAM][ASSUMPTION] Encodings Matthew owns. Proposed in the Module I/O map, for
// Matthew to confirm. Every part decodes these, so change them only here.
// (No mouse: ui_click, ui_screen, ui_x, ui_y and qty_delta were removed 17 Oct.)
`define GS_MENU        2'd0   // game_state
`define GS_PLAYING     2'd1
`define GS_RESULT      2'd2
`define PG_L_CHART     1'b0   // page_L
`define PG_L_OVERVIEW  1'b1
`define PG_R_TICKET    1'b0   // page_R
`define PG_R_PORTFOLIO 1'b1

// ---------------------------------------------------------------- game screen states (Matthew)
// These encodings are shared by the FSM, display top, OLED renderers, and
// tests. Keep them in one place so a state insertion cannot silently split
// the UI decoders across different numeric values.
`define UI_TITLE        4'd0
`define UI_PORTFOLIO    4'd1
`define UI_STOCKS       4'd2
`define UI_SPECIFIC     4'd3
`define UI_BUY_STOCK    4'd4
`define UI_SELL_STOCK   4'd5
`define UI_QUANTITY     4'd6
`define UI_ORDER_REVIEW 4'd7
`define UI_ORDER_RESULT 4'd8
`define UI_TRADE_RESULT 4'd9
`define UI_GAME_END     4'd10
`define UI_ORDER_TYPE   4'd11   // order type, trigger price, SL/TP (from BUY / SELL)

// ---------------------------------------------------------------- display numbers (Matthew)
// Fields of display_numbers: each is 8 decimal digits (32-bit BCD) plus a
// minus flag. Money is in cents unless noted.
`define DN_CASH    0    // cash
`define DN_NET     1    // portfolio value (cash + holdings)
`define DN_PX0     2    // price of stock 0..3: DN_PX0 + k
`define DN_POS0    6    // shares held of stock 0..3: DN_POS0 + k
`define DN_PNL0    10   // profit/loss of stock 0..3 (value - cost basis): DN_PNL0 + k
`define DN_CHG     14   // selected stock: price now - price 30 days ago
`define DN_QTY     15   // quantity being entered
`define DN_DAYS    16   // trading days left
`define DN_ORDPX   17   // order price: ask for a buy, bid for a sell
`define DN_ORDTOT  18   // order total: buy pays price x qty + fee, sell gets price x qty - fee
`define DN_NETPNL  19   // portfolio value - starting cash
`define DN_TRIG    20   // trigger price on the ORDER TYPE screen
`define DN_SL      21   // selected stock's stop-loss level in the book (0 = none)
`define DN_TP      22   // selected stock's take-profit level in the book (0 = none)
`define DN_BCASH   23   // bot: cash
`define DN_BNET    24   // bot: value (cash + holdings)
`define DN_BNETPNL 25   // bot: value - starting cash
`define DN_BPOS0   26   // bot: shares of stock 0..3: DN_BPOS0 + k
`define DN_BPNL0   30   // bot: profit/loss of stock 0..3: DN_BPNL0 + k
`define DN_LOGPX0  34   // bot log entry 0..4 (0 newest): price, DN_LOGPX0 + n
`define DN_LOGDAY0 39   // bot log entry 0..4: day, DN_LOGDAY0 + n
`define DN_N       44

// btn_pulse bit positions, in Basys3 master XDC order (btnC, btnU, btnL, btnR, btnD)
`define BTN_C 0
`define BTN_U 1
`define BTN_L 2
`define BTN_R 3
`define BTN_D 4

// ---------------------------------------------------------------- font
// [TEAM][ASSUMPTION] Character codes of the 3x5 font (font_3x5.v).
// Digits 0..9 are codes 0..9, so a BCD digit d is char {2'b00, d}.
// Letters A..Z are codes 10..35. 48..62 were added on 21 Oct; nothing earlier changed.
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
`define CH_LT     6'd48
`define CH_EQ     6'd49
`define CH_LPAR   6'd50
`define CH_RPAR   6'd51
`define CH_COMMA  6'd52
`define CH_EXCL   6'd53
`define CH_QUEST  6'd54
`define CH_STAR   6'd55
`define CH_HASH   6'd56
`define CH_UNDER  6'd57
`define CH_APOS   6'd58
`define CH_AMP    6'd59
`define CH_UP     6'd60   // up arrow
`define CH_DOWN   6'd61   // down arrow
`define CH_BLOCK  6'd62   // filled cell

`endif
