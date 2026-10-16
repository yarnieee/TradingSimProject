// ticket_layout.vh
// Boxes on the Order Ticket page (right OLED, 96x64), all bounds inclusive.
// ticket_screen draws from these. (They were also mouse hit regions until the
// mouse was removed from the project on 17 Oct.)
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

// QTY and TRG text lines
`define TK_QTY_Y0    6'd27
`define TK_QTY_Y1    6'd32
`define TK_TRG_Y0    6'd35
`define TK_TRG_Y1    6'd40

// SUBMIT button
`define TK_SUB_X0    7'd22
`define TK_SUB_X1    7'd73
`define TK_SUB_Y0    6'd43
`define TK_SUB_Y1    6'd52

// status line
`define TK_STAT_Y0   6'd55
`define TK_STAT_Y1   6'd60

`endif
