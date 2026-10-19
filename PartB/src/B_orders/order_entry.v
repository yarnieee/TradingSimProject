`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// order_entry: Order Ticket field state, driven by the five board buttons,
// or by a complete order from D's confirm screen (ext_load).
// (The mouse was removed from the project on 17 Oct.)
//
// ext_load: copies the external order into the ticket fields (so the page
// shows what was sent) and submits it on the same clock. It wins over a button
// press on the same clock. ext_qty 0 is passed through so B rejects it as
// RJ_BAD_QTY; B_order_top maps out-of-range quantities to 0.
//
// Buttons are only acted on while the Ticket page is showing (ticket_active).
// One button acts per clock: left > right > up > down > center.
// [ASSUMPTION] mapping is a proposal:
//   left/right  move focus (qty -> trig -> submit, wrapping)
//   up/down     qty +/- 1, or trig +/- TRIG_STEP cents
//   center      qty: toggle BUY/SELL, trig: cycle MKT/LMT/STP, submit: submit
//
// trig is re-centred on the market when sel_stock changes, and once after
// reset as soon as the selected price is non-zero. [ASSUMPTION]
// qty is clamped to 1..255, trig to 0..65535 (0 is caught by RJ_BAD_TRIG).
module order_entry #(
    parameter QTY_INIT  = 1,     // [ASSUMPTION]
    parameter TRIG_STEP = 5      // cents per press [ASSUMPTION]
) (
    input  wire        clk,
    input  wire        sys_reset,
    input  wire        ticket_active,
    input  wire [1:0]  sel_stock,
    input  wire [15:0] sel_price,      // mid price of sel_stock
    input  wire        key_up,
    input  wire        key_down,
    input  wire        key_left,
    input  wire        key_right,
    input  wire        key_center,
    // complete order from D (confirm screen)
    input  wire        ext_load,
    input  wire        ext_side,
    input  wire [1:0]  ext_type,
    input  wire [7:0]  ext_qty,
    input  wire [15:0] ext_trig,
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

    // ------------------------------------------------------------ helpers
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

            if (ext_load) begin
                side  <= ext_side;
                otype <= ext_type;
                qty   <= ext_qty;
                if (ext_type != `OT_MKT) trig <= ext_trig;
            end else begin
            if (k_left)
                focus <= (focus == F_QTY) ? F_SUB : focus - 2'd1;
            if (k_right)
                focus <= (focus == F_SUB) ? F_QTY : focus + 2'd1;
            if (k_up || k_down) begin
                if (focus == F_QTY)      qty  <= qty_step(qty, k_up);
                else if (focus == F_TRG) trig <= trig_step(trig, k_up);
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
            if (ext_load) begin
                sub_stock <= sel_stock;
                sub_side  <= ext_side;
                sub_type  <= ext_type;
                sub_qty   <= ext_qty;
                sub_trig  <= ext_trig;
            end else if (do_submit) begin
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
