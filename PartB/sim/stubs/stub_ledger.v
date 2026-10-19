`timescale 1ns / 1ps
`default_nettype none

// stub_ledger: behavioural model of C's ledger, for Part B testing only.
//
// On fill: raises ledger_busy on the next clock (the [TEAM] contract), holds
// it for BUSY_CYCLES clocks, then applies the fill and drops busy on the same
// clock, so cash/pos are already updated when B sees !ledger_busy.
//   BUY : cash -= qty*price + fee, pos += qty
//   SELL: cash += qty*price - fee, pos -= qty
//
// Simulation-only checks (stop with FAIL): a fill while busy, cash going
// negative, a position going below 0 or above POS_MAX.
module stub_ledger #(
    parameter START_CASH  = 1000000,
    parameter BUSY_CYCLES = 40,
    parameter POS_MAX     = 1023
) (
    input  wire        clk,
    input  wire        sys_reset,
    input  wire        fill,
    input  wire [1:0]  fill_stock,
    input  wire        fill_side,
    input  wire [7:0]  fill_qty,
    input  wire [15:0] fill_price,
    input  wire [15:0] fill_fee,
    output reg  [31:0] cash,
    output reg  [9:0]  pos0,
    output reg  [9:0]  pos1,
    output reg  [9:0]  pos2,
    output reg  [9:0]  pos3,
    output reg         ledger_busy
);
    reg [1:0]  l_stock;
    reg        l_side;
    reg [7:0]  l_qty;
    reg [15:0] l_price;
    reg [15:0] l_fee;
    reg [7:0]  cnt;

    wire [23:0] value = l_price * l_qty;

    reg [9:0] pos_sel;
    always @* begin
        case (l_stock)
            2'd0:    pos_sel = pos0;
            2'd1:    pos_sel = pos1;
            2'd2:    pos_sel = pos2;
            default: pos_sel = pos3;
        endcase
    end

    wire [9:0] pos_new = l_side ? pos_sel - l_qty : pos_sel + l_qty;

    always @(posedge clk) begin
        if (sys_reset) begin
            cash        <= START_CASH;
            pos0        <= 10'd0;
            pos1        <= 10'd0;
            pos2        <= 10'd0;
            pos3        <= 10'd0;
            ledger_busy <= 1'b0;
            cnt         <= 8'd0;
            l_stock     <= 2'd0;
            l_side      <= 1'b0;
            l_qty       <= 8'd0;
            l_price     <= 16'd0;
            l_fee       <= 16'd0;
        end else if (!ledger_busy) begin
            if (fill) begin
                l_stock     <= fill_stock;
                l_side      <= fill_side;
                l_qty       <= fill_qty;
                l_price     <= fill_price;
                l_fee       <= fill_fee;
                ledger_busy <= 1'b1;
                cnt         <= BUSY_CYCLES - 1;
            end
        end else if (cnt != 8'd0) begin
            cnt <= cnt - 8'd1;
        end else begin
            if (l_side)
                cash <= cash + value - l_fee;
            else
                cash <= cash - value - l_fee;
            case (l_stock)
                2'd0:    pos0 <= pos_new;
                2'd1:    pos1 <= pos_new;
                2'd2:    pos2 <= pos_new;
                default: pos3 <= pos_new;
            endcase
            ledger_busy <= 1'b0;
        end
    end

    // synthesis translate_off
    always @(posedge clk) begin
        if (!sys_reset) begin
            if (fill && ledger_busy) begin
                $display("FAIL: stub_ledger got a fill while ledger_busy (t=%0t)", $time);
                $finish;
            end
            if (ledger_busy && cnt == 8'd0) begin
                if (!l_side && ({8'd0, value} + l_fee > cash)) begin
                    $display("FAIL: stub_ledger cash would go negative: cash=%0d cost=%0d fee=%0d (t=%0t)",
                             cash, value, l_fee, $time);
                    $finish;
                end
                if (l_side && ({1'b0, cash} + value < l_fee)) begin
                    $display("FAIL: stub_ledger cash would go negative on a sell (t=%0t)", $time);
                    $finish;
                end
                if (l_side && l_qty > pos_sel) begin
                    $display("FAIL: stub_ledger position would go negative (t=%0t)", $time);
                    $finish;
                end
                if (!l_side && ({1'b0, pos_sel} + l_qty > POS_MAX)) begin
                    $display("FAIL: stub_ledger position would exceed %0d (t=%0t)", POS_MAX, $time);
                    $finish;
                end
            end
        end
    end
    // synthesis translate_on
endmodule

`default_nettype wire
