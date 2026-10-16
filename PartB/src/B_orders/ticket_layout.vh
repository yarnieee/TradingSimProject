// ticket_layout.vh
// Boxes on the Order Ticket page (right OLED, 96x64), all bounds inclusive.
// order_entry hit-tests clicks against these and ticket_screen draws them,
// so the clickable area and the drawn button can never drift apart.
// [ASSUMPTION] Whole layout is a proposal; tune after looking at the frame dump.

`ifndef TICKET_LAYOUT_VH
`define TICKET_LAYOUT_VH

// row of three buttons: BUY, SELL, order type
`define TK_BTN_Y0    6'd15
`define TK_BTN_Y1    6'd24
`define TK_BUY_X0    7'd2
`define TK_BUY_X1    7'd25
`define TK_SELL_X0   7'd28
`define TK_SELL_X1   7'd55
`define TK_TYPE_X0   7'd62
`define TK_TYPE_X1   7'd93

// [-] and [+] next to QTY and TRG. Spec had x 62-70 / 74-82; widened to
// 62-72 / 74-84 so the hit area covers the drawn "[-]" and "[+]" glyphs.
`define TK_MINUS_X0  7'd62
`define TK_MINUS_X1  7'd72
`define TK_PLUS_X0   7'd74
`define TK_PLUS_X1   7'd84
`define TK_QTY_Y0    6'd27
`define TK_QTY_Y1    6'd32
`define TK_TRG_Y0    6'd35
`define TK_TRG_Y1    6'd40

// SUBMIT button
`define TK_SUB_X0    7'd22
`define TK_SUB_X1    7'd73
`define TK_SUB_Y0    6'd43
`define TK_SUB_Y1    6'd52

// status line (Phase 3: click opens the pending list)
`define TK_STAT_Y0   6'd55
`define TK_STAT_Y1   6'd60

`endif
