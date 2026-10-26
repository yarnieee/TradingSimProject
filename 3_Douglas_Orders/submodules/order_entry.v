`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// order_entry: Order Ticket field state, driven by the five board buttons,
// or by a complete order from Matthew's confirm screen (ext_load).
// (The mouse was removed from the project on 17 Oct.)
//
// ext_load: copies the external order into the ticket fields (so the page
// shows what was sent) and submits it on the same clock, for Matthew's
// sel_stock, with its own SL/TP setting (ext_brk). It wins over a button press
// on the same clock. ext_qty 0 is passed through so the order engine
// rejects it as RJ_BAD_QTY; B_order_top maps out-of-range quantities to 0.
//
// Buttons are only acted on while the Ticket page is showing (ticket_active).
// One button acts per clock: left > right > up > down > center.
// [ASSUMPTION] mapping is a proposal. Fields, left to right (wrapping):
//   STK     up/down: next/previous stock
//   QTY     up/down: qty +/- 1             center: toggle BUY/SELL
//   TRG     up/down: trig +/- TRIG_STEP    center: cycle MKT/LMT/STP
//   SL/TP   up/down: OFF, 2%, 5%, 10%
//   SUBMIT                                 center: submit
//   ORDERS  up/down: move the cursor       center: cancel that pending order
//
// stock follows Matthew's sel_stock whenever that changes, and can then be
// changed on the ticket. trig is re-centred on the market when stock changes,
// and once after reset as soon as the stock's price is non-zero. [ASSUMPTION]
// qty is clamped to 1..255, trig to 0..65535 (0 is caught by RJ_BAD_TRIG).
module order_entry #(
    parameter QTY_INIT  = 1,     // [ASSUMPTION]
    parameter TRIG_STEP = 5      // cents per press [ASSUMPTION]
) (
    input  wire        clk,
    input  wire        sys_reset,
    input  wire        ticket_active,
    input  wire [1:0]  sel_stock,      // Matthew's selected stock
    input  wire [15:0] tk_price,       // mid price of the ticket's stock
    input  wire        key_up,
    input  wire        key_down,
    input  wire        key_left,
    input  wire        key_right,
    input  wire        key_center,
    // complete order from Matthew (confirm screen)
    input  wire        ext_load,
    input  wire        ext_side,
    input  wire [1:0]  ext_type,
    input  wire [7:0]  ext_qty,
    input  wire [15:0] ext_trig,
    input  wire [1:0]  ext_brk,
    // live fields (for ticket_screen)
    output reg  [1:0]  stock,
    output reg         side,
    output reg  [1:0]  otype,
    output reg  [7:0]  qty,
    output reg  [15:0] trig,
    output reg  [1:0]  brk,
    output reg  [2:0]  ord_sel,        // cursor in the ORDERS view (book slot)
    output reg  [2:0]  focus,
    // submit
    output reg         submit_req,
    output reg  [1:0]  sub_stock,
    output reg         sub_side,
    output reg  [1:0]  sub_type,
    output reg  [7:0]  sub_qty,
    output reg  [15:0] sub_trig,
    output reg  [1:0]  sub_brk,
    // cancel a pending order
    output reg         cancel_req,
    output reg  [2:0]  cancel_idx
);
    // focus codes (QTY, TRG and SUBMIT kept their old values)
    localparam F_QTY = 3'd0,
               F_TRG = 3'd1,
               F_SUB = 3'd2,
               F_BRK = 3'd3,
               F_ORD = 3'd4,
               F_STK = 3'd5;

    // ------------------------------------------------------------ helpers
    function [2:0] focus_next;         // STK > QTY > TRG > SL/TP > SUBMIT > ORDERS > STK
        input [2:0] f;
        begin
            case (f)
                F_STK:   focus_next = F_QTY;
                F_QTY:   focus_next = F_TRG;
                F_TRG:   focus_next = F_BRK;
                F_BRK:   focus_next = F_SUB;
                F_SUB:   focus_next = F_ORD;
                default: focus_next = F_STK;
            endcase
        end
    endfunction

    function [2:0] focus_prev;
        input [2:0] f;
        begin
            case (f)
                F_QTY:   focus_prev = F_STK;
                F_TRG:   focus_prev = F_QTY;
                F_BRK:   focus_prev = F_TRG;
                F_SUB:   focus_prev = F_BRK;
                F_ORD:   focus_prev = F_SUB;
                default: focus_prev = F_ORD;
            endcase
        end
    endfunction

    function [7:0] qty_step;           // +/- 1, clamped to 1..255
        input [7:0] q;
        input       up;
        begin
            if (up) qty_step = (q == 8'd255) ? 8'd255 : q + 8'd1;
            else    qty_step = (q <= 8'd1)   ? 8'd1   : q - 8'd1;
        end
    endfunction

    function [15:0] trig_step;         // +/- TRIG_STEP, clamped to 0..65535
        input [15:0] t;
        input        up;
        reg   [16:0] s;
        begin
            if (up) begin
                s = {1'b0, t} + TRIG_STEP;
                trig_step = s[16] ? 16'hFFFF : s[15:0];
            end else begin
                trig_step = (t > TRIG_STEP) ? t - TRIG_STEP : 16'd0;
            end
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
    wire k_left   = ticket_active && key_left;
    wire k_right  = ticket_active && !key_left && key_right;
    wire k_up     = ticket_active && !key_left && !key_right && key_up;
    wire k_down   = ticket_active && !key_left && !key_right && !key_up && key_down;
    wire k_center = ticket_active && !key_left && !key_right && !key_up && !key_down && key_center;

    wire key_submit = k_center && focus == F_SUB && !ext_load;
    wire do_submit  = key_submit || ext_load;
    wire do_cancel  = k_center && focus == F_ORD && !ext_load;

    // ------------------------------------------------------------ fields
    reg [1:0] prev_sel;
    reg [1:0] prev_stock;
    reg       trig_loaded;

    always @(posedge clk) begin
        if (sys_reset) begin
            stock       <= sel_stock;
            side        <= `SIDE_BUY;
            otype       <= `OT_MKT;
            qty         <= QTY_INIT;
            trig        <= 16'd0;
            brk         <= `BRK_OFF;
            ord_sel     <= 3'd0;
            focus       <= F_QTY;
            prev_sel    <= sel_stock;
            prev_stock  <= sel_stock;
            trig_loaded <= 1'b0;
        end else begin
            prev_sel   <= sel_stock;
            prev_stock <= stock;

            if (ext_load) begin
                stock <= sel_stock;
                side  <= ext_side;
                otype <= ext_type;
                qty   <= ext_qty;
                brk   <= ext_brk;
                if (ext_type != `OT_MKT) trig <= ext_trig;
            end else begin
                if (sel_stock != prev_sel)
                    stock <= sel_stock;            // Matthew picked a stock
                if (k_left)  focus <= focus_prev(focus);
                if (k_right) focus <= focus_next(focus);
                if (k_up || k_down) begin
                    case (focus)
                        F_STK: stock   <= k_up ? stock + 2'd1   : stock - 2'd1;
                        F_QTY: qty     <= qty_step(qty, k_up);
                        F_TRG: trig    <= trig_step(trig, k_up);
                        F_BRK: brk     <= k_up ? brk + 2'd1     : brk - 2'd1;
                        F_ORD: ord_sel <= k_up ? ord_sel - 3'd1 : ord_sel + 3'd1;   // up = towards slot 0
                        default: ;
                    endcase
                end
                if (k_center) begin
                    if (focus == F_QTY)      side  <= ~side;
                    else if (focus == F_TRG) otype <= next_type(otype);
                end
            end

            // re-centre the trigger on the market; wins over an edit this clock
            if (stock != prev_stock || (!trig_loaded && tk_price != 16'd0)) begin
                trig        <= tk_price;
                trig_loaded <= (tk_price != 16'd0);
            end
        end
    end

    // ------------------------------------------------------------ submit, cancel
    always @(posedge clk) begin
        if (sys_reset) begin
            submit_req <= 1'b0;
            sub_stock  <= 2'd0;
            sub_side   <= 1'b0;
            sub_type   <= 2'd0;
            sub_qty    <= 8'd0;
            sub_trig   <= 16'd0;
            sub_brk    <= `BRK_OFF;
            cancel_req <= 1'b0;
            cancel_idx <= 3'd0;
        end else begin
            submit_req <= do_submit;
            cancel_req <= do_cancel;
            if (do_cancel) cancel_idx <= ord_sel;
            if (ext_load) begin
                sub_stock <= sel_stock;
                sub_side  <= ext_side;
                sub_type  <= ext_type;
                sub_qty   <= ext_qty;
                sub_trig  <= ext_trig;
                sub_brk   <= ext_brk;
            end else if (do_submit) begin
                sub_stock <= stock;
                sub_side  <= side;
                sub_type  <= otype;
                sub_qty   <= qty;
                sub_trig  <= trig;
                sub_brk   <= brk;
            end
        end
    end
endmodule

`default_nettype wire
