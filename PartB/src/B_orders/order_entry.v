`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"
`include "ticket_layout.vh"

// order_entry: Order Ticket field state and input decoding.
//
// Inputs are only acted on while the Ticket page is showing (ticket_active).
// If several arrive on the same clock: click > scroll > button.
//
// Mouse (click on right OLED): hit-tested against ticket_layout.vh.
// Scroll : qty +/- 1 per notch, trig +/- TRIG_STEP cents per notch, on the
//          focused field. Nothing on the SUBMIT focus.
// Buttons [ASSUMPTION] mapping is a proposal:
//   left/right  move focus (qty -> trig -> submit, wrapping)
//   up/down     change the focused value by one step
//   center      qty: toggle BUY/SELL, trig: cycle MKT/LMT/STP, submit: submit
//
// trig is re-centred on the market when sel_stock changes, and once after
// reset as soon as the selected price is non-zero. [ASSUMPTION]
// qty is clamped to 1..255, trig to 0..65535 (0 is caught by RJ_BAD_TRIG).
module order_entry #(
    parameter QTY_INIT  = 1,     // [ASSUMPTION]
    parameter TRIG_STEP = 5      // cents per notch [ASSUMPTION]
) (
    input  wire        clk,
    input  wire        sys_reset,
    input  wire        ticket_active,
    input  wire [1:0]  sel_stock,
    input  wire [15:0] sel_price,      // mid price of sel_stock
    input  wire        ui_click,
    input  wire        ui_screen,      // 1 = right OLED
    input  wire [6:0]  ui_x,
    input  wire [5:0]  ui_y,
    input  wire [3:0]  qty_delta,      // signed
    input  wire        qty_delta_valid,
    input  wire        key_up,
    input  wire        key_down,
    input  wire        key_left,
    input  wire        key_right,
    input  wire        key_center,
    // live fields (for ticket_screen)
    output reg         side,
    output reg  [1:0]  otype,
    output reg  [7:0]  qty,
    output reg  [15:0] trig,
    output reg  [1:0]  focus,
    // submit
    output reg         submit_req,
    output reg  [1:0]  sub_stock,
    output reg         sub_side,
    output reg  [1:0]  sub_type,
    output reg  [7:0]  sub_qty,
    output reg  [15:0] sub_trig
);
    localparam F_QTY = 2'd0,
               F_TRG = 2'd1,
               F_SUB = 2'd2;

    localparam signed [4:0] STEP_UP   =  5'sd1;
    localparam signed [4:0] STEP_DOWN = -5'sd1;

    // ------------------------------------------------------------ helpers
    function in_box;
        input [6:0] x;
        input [5:0] y;
        input [6:0] x0, x1;
        input [5:0] y0, y1;
        begin
            in_box = (x >= x0) && (x <= x1) && (y >= y0) && (y <= y1);
        end
    endfunction

    function [7:0] qty_add;
        input [7:0]        q;
        input signed [4:0] d;
        reg signed [9:0]   s;
        begin
            s = $signed({2'b00, q}) + d;
            if (s < 10'sd1)        qty_add = 8'd1;
            else if (s > 10'sd255) qty_add = 8'd255;
            else                   qty_add = s[7:0];
        end
    endfunction

    function [15:0] trig_add;
        input [15:0]       t;
        input signed [4:0] d;
        reg signed [19:0]  s;
        begin
            s = $signed({4'b0000, t}) + d * $signed(TRIG_STEP);
            if (s < 20'sd0)          trig_add = 16'd0;
            else if (s > 20'sd65535) trig_add = 16'hFFFF;
            else                     trig_add = s[15:0];
        end
    endfunction

    function [1:0] next_type;
        input [1:0] t;
        begin
            case (t)
                `OT_MKT: next_type = `OT_LMT;
                `OT_LMT: next_type = `OT_STP;
                default: next_type = `OT_MKT;
            endcase
        end
    endfunction

    // ------------------------------------------------------------ decode
    wire click = ui_click && ui_screen && ticket_active;

    wire hit_buy  = in_box(ui_x, ui_y, `TK_BUY_X0,   `TK_BUY_X1,   `TK_BTN_Y0, `TK_BTN_Y1);
    wire hit_sell = in_box(ui_x, ui_y, `TK_SELL_X0,  `TK_SELL_X1,  `TK_BTN_Y0, `TK_BTN_Y1);
    wire hit_type = in_box(ui_x, ui_y, `TK_TYPE_X0,  `TK_TYPE_X1,  `TK_BTN_Y0, `TK_BTN_Y1);
    wire hit_qm   = in_box(ui_x, ui_y, `TK_MINUS_X0, `TK_MINUS_X1, `TK_QTY_Y0, `TK_QTY_Y1);
    wire hit_qp   = in_box(ui_x, ui_y, `TK_PLUS_X0,  `TK_PLUS_X1,  `TK_QTY_Y0, `TK_QTY_Y1);
    wire hit_tm   = in_box(ui_x, ui_y, `TK_MINUS_X0, `TK_MINUS_X1, `TK_TRG_Y0, `TK_TRG_Y1);
    wire hit_tp   = in_box(ui_x, ui_y, `TK_PLUS_X0,  `TK_PLUS_X1,  `TK_TRG_Y0, `TK_TRG_Y1);
    wire hit_sub  = in_box(ui_x, ui_y, `TK_SUB_X0,   `TK_SUB_X1,   `TK_SUB_Y0, `TK_SUB_Y1);

    wire scroll = qty_delta_valid && ticket_active && !click;
    wire keys   = ticket_active && !click && !qty_delta_valid;

    wire signed [4:0] sdelta = {qty_delta[3], qty_delta};

    // only one key acts per clock: left > right > up > down > center
    wire k_left   = keys && key_left;
    wire k_right  = keys && !key_left && key_right;
    wire k_up     = keys && !key_left && !key_right && key_up;
    wire k_down   = keys && !key_left && !key_right && !key_up && key_down;
    wire k_center = keys && !key_left && !key_right && !key_up && !key_down && key_center;

    wire do_submit = (click && hit_sub) || (k_center && focus == F_SUB);

    // ------------------------------------------------------------ fields
    reg [1:0] prev_sel;
    reg       trig_loaded;

    always @(posedge clk) begin
        if (sys_reset) begin
            side        <= `SIDE_BUY;
            otype       <= `OT_MKT;
            qty         <= QTY_INIT;
            trig        <= 16'd0;
            focus       <= F_QTY;
            prev_sel    <= sel_stock;
            trig_loaded <= 1'b0;
        end else begin
            prev_sel <= sel_stock;

            if (click) begin
                if (hit_buy)       side  <= `SIDE_BUY;
                else if (hit_sell) side  <= `SIDE_SELL;
                else if (hit_type) otype <= next_type(otype);
                else if (hit_qm) begin qty  <= qty_add(qty, STEP_DOWN);   focus <= F_QTY; end
                else if (hit_qp) begin qty  <= qty_add(qty, STEP_UP);     focus <= F_QTY; end
                else if (hit_tm) begin trig <= trig_add(trig, STEP_DOWN); focus <= F_TRG; end
                else if (hit_tp) begin trig <= trig_add(trig, STEP_UP);   focus <= F_TRG; end
            end else if (scroll) begin
                if (focus == F_QTY)      qty  <= qty_add(qty, sdelta);
                else if (focus == F_TRG) trig <= trig_add(trig, sdelta);
            end else begin
                if (k_left)
                    focus <= (focus == F_QTY) ? F_SUB : focus - 2'd1;
                if (k_right)
                    focus <= (focus == F_SUB) ? F_QTY : focus + 2'd1;
                if (k_up || k_down) begin
                    if (focus == F_QTY)      qty  <= qty_add(qty,   k_up ? STEP_UP : STEP_DOWN);
                    else if (focus == F_TRG) trig <= trig_add(trig, k_up ? STEP_UP : STEP_DOWN);
                end
                if (k_center) begin
                    if (focus == F_QTY)      side  <= ~side;
                    else if (focus == F_TRG) otype <= next_type(otype);
                end
            end

            // re-centre the trigger on the market; wins over an edit this clock
            if (sel_stock != prev_sel || (!trig_loaded && sel_price != 16'd0)) begin
                trig        <= sel_price;
                trig_loaded <= (sel_price != 16'd0);
            end
        end
    end

    // ------------------------------------------------------------ submit
    always @(posedge clk) begin
        if (sys_reset) begin
            submit_req <= 1'b0;
            sub_stock  <= 2'd0;
            sub_side   <= 1'b0;
            sub_type   <= 2'd0;
            sub_qty    <= 8'd0;
            sub_trig   <= 16'd0;
        end else begin
            submit_req <= do_submit;
            if (do_submit) begin
                sub_stock <= sel_stock;
                sub_side  <= side;
                sub_type  <= otype;
                sub_qty   <= qty;
                sub_trig  <= trig;
            end
        end
    end
endmodule

`default_nettype wire
