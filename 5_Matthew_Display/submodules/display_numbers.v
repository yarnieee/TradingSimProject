`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// display_numbers: every number the OLEDs show, as decimal digits.
//
// One field at a time (list in trading_defs.vh, DN_*): work out the value,
// then convert it to 8 BCD digits with a shift-and-add-3 converter (32 clocks).
// All fields refresh about every 1,500 clocks (15 us), so the screens always
// read finished digits from registers: no dividers in the pixel logic.
// Values above 99,999,999 show as 99999999.
//
// bcd[32*f +: 32] is field f, digit 0 (ones) in bits [3:0].
// neg[f] is 1 when field f is negative (P/L and price change only).
module display_numbers #(
    parameter [31:0] START_CASH = 32'd1_000_000,   // cents
    parameter [15:0] SPREAD     = 16'd5,           // cents, as in B_order_top
    parameter [15:0] FEE        = 16'd100          // cents, as in B_order_top
) (
    input  wire        clk,
    input  wire        rst,
    // player
    input  wire [31:0] cash,
    input  wire [31:0] portfolio_value,
    input  wire [15:0] price0,
    input  wire [15:0] price1,
    input  wire [15:0] price2,
    input  wire [15:0] price3,
    input  wire [9:0]  pos0,
    input  wire [9:0]  pos1,
    input  wire [9:0]  pos2,
    input  wire [9:0]  pos3,
    input  wire signed [31:0] upnl0,      // profit/loss per stock (Tricia's risk_metrics), cents
    input  wire signed [31:0] upnl1,
    input  wire signed [31:0] upnl2,
    input  wire signed [31:0] upnl3,
    // the order on screen
    input  wire [1:0]  sel_stock,
    input  wire [15:0] sel_ref_price,     // selected stock's price 30 days ago
    input  wire [13:0] quantity,
    input  wire [31:0] days_left,
    input  wire        sell,              // 0 buy, 1 sell
    input  wire [1:0]  order_type,        // trigger price used for LMT / STP buys and sells
    input  wire [15:0] order_trig,
    input  wire [15:0] sel_sl,            // selected stock's SL / TP levels in the book
    input  wire [15:0] sel_tp,
    // bot
    input  wire [31:0] bot_cash,
    input  wire [31:0] bot_value,
    input  wire [9:0]  bot_pos0,
    input  wire [9:0]  bot_pos1,
    input  wire [9:0]  bot_pos2,
    input  wire [9:0]  bot_pos3,
    input  wire signed [31:0] bot_upnl0,
    input  wire signed [31:0] bot_upnl1,
    input  wire signed [31:0] bot_upnl2,
    input  wire signed [31:0] bot_upnl3,
    input  wire [79:0] log_price,         // bot log, newest first
    input  wire [39:0] log_day,
    // order book (VGA order list) and Tricia's risk figures
    input  wire [63:0]  book_qty,
    input  wire [127:0] book_trig,
    input  wire signed [31:0] ret_bp,
    input  wire [31:0]  max_dd_bp,
    input  wire signed [31:0] bot_ret_bp,
    output reg  [`DN_N*32-1:0] bcd,
    output reg  [`DN_N-1:0]    neg
);
    localparam [31:0] MAX_SHOWN = 32'd99_999_999;

    reg  [5:0] idx;

    // ------------------------------------------------------------ which stock / log entry
    reg [2:0] k;               // stock 0-3 or log entry 0-4 of this field
    always @* begin
        if      (idx >= `DN_RET)     k = 3'd0;
        else if (idx >= `DN_SLT0)    k = idx - `DN_SLT0;
        else if (idx >= `DN_SLQ0)    k = idx - `DN_SLQ0;
        else if (idx >= `DN_LOGDAY0) k = idx - `DN_LOGDAY0;
        else if (idx >= `DN_LOGPX0)  k = idx - `DN_LOGPX0;
        else if (idx >= `DN_BPNL0)   k = idx - `DN_BPNL0;
        else if (idx >= `DN_BPOS0)   k = idx - `DN_BPOS0;
        else if (idx >= `DN_PNL0)    k = idx - `DN_PNL0;
        else if (idx >= `DN_POS0)    k = idx - `DN_POS0;
        else                         k = idx - `DN_PX0;
    end
    wire bot = (idx >= `DN_BPOS0) && (idx < `DN_LOGPX0);

    reg [15:0] px_k;
    reg [9:0]  pos_k;
    reg signed [31:0] upnl_k;
    always @* begin
        case (k[1:0])
            2'd0:    begin px_k = price0; pos_k = bot ? bot_pos0 : pos0; upnl_k = bot ? bot_upnl0 : upnl0; end
            2'd1:    begin px_k = price1; pos_k = bot ? bot_pos1 : pos1; upnl_k = bot ? bot_upnl1 : upnl1; end
            2'd2:    begin px_k = price2; pos_k = bot ? bot_pos2 : pos2; upnl_k = bot ? bot_upnl2 : upnl2; end
            default: begin px_k = price3; pos_k = bot ? bot_pos3 : pos3; upnl_k = bot ? bot_upnl3 : upnl3; end
        endcase
    end

    reg [15:0] sel_px;
    always @* begin
        case (sel_stock)
            2'd0:    sel_px = price0;
            2'd1:    sel_px = price1;
            2'd2:    sel_px = price2;
            default: sel_px = price3;
        endcase
    end

    wire [16:0] ask_full = {1'b0, sel_px} + {1'b0, SPREAD};
    wire [15:0] ask      = ask_full[16] ? 16'hFFFF : ask_full[15:0];
    wire [15:0] bid      = (sel_px > SPREAD) ? sel_px - SPREAD : 16'd0;
    // market orders fill at the ask / bid; limit and stop orders at their trigger
    wire [15:0] ord_px   = (order_type != `OT_MKT) ? order_trig : sell ? bid : ask;

    // order total: quantity x price
    wire [29:0] prod    = ord_px * quantity;

    reg [31:0] val;
    reg        val_neg;
    always @* begin
        val_neg = 1'b0;
        val     = 32'd0;
        case (idx)
            `DN_CASH:   val = cash;
            `DN_NET:    val = portfolio_value;
            `DN_CHG: begin
                val_neg = sel_px < sel_ref_price;
                val     = val_neg ? sel_ref_price - sel_px : sel_px - sel_ref_price;
            end
            `DN_QTY:    val = {18'd0, quantity};
            `DN_DAYS:   val = days_left;
            `DN_ORDPX:  val = {16'd0, ord_px};
            `DN_ORDTOT: begin
                if (!sell)               val = {2'd0, prod} + FEE;
                else if (prod >= FEE)    val = {2'd0, prod} - FEE;
                else begin val_neg = 1'b1; val = FEE - prod; end
            end
            `DN_NETPNL: begin
                val_neg = portfolio_value < START_CASH;
                val     = val_neg ? START_CASH - portfolio_value : portfolio_value - START_CASH;
            end
            `DN_TRIG:   val = {16'd0, order_trig};
            `DN_SL:     val = {16'd0, sel_sl};
            `DN_TP:     val = {16'd0, sel_tp};
            `DN_BCASH:  val = bot_cash;
            `DN_BNET:   val = bot_value;
            `DN_BNETPNL: begin
                val_neg = bot_value < START_CASH;
                val     = val_neg ? START_CASH - bot_value : bot_value - START_CASH;
            end
            `DN_RET: begin
                val_neg = ret_bp < 0;
                val     = val_neg ? -ret_bp : ret_bp;
            end
            `DN_MAXDD:  val = max_dd_bp;
            `DN_BRET: begin
                val_neg = bot_ret_bp < 0;
                val     = val_neg ? -bot_ret_bp : bot_ret_bp;
            end
            default: begin
                if (idx >= `DN_SLT0)         val = {16'd0, book_trig[16*k +: 16]};
                else if (idx >= `DN_SLQ0)    val = {24'd0, book_qty[8*k +: 8]};
                else if (idx >= `DN_LOGDAY0) val = {24'd0, log_day[8*k +: 8]};
                else if (idx >= `DN_LOGPX0)  val = {16'd0, log_price[16*k +: 16]};
                else if ((idx >= `DN_BPNL0) || (idx >= `DN_PNL0 && idx < `DN_CHG)) begin   // P/L of stock k
                    val_neg = upnl_k < 0;
                    val     = val_neg ? -upnl_k : upnl_k;
                end else if ((idx >= `DN_BPOS0) || (idx >= `DN_POS0 && idx < `DN_PNL0))  // shares of stock k
                    val = {22'd0, pos_k};
                else                                                                     // price of stock k
                    val = {16'd0, px_k};
            end
        endcase
    end

    // ------------------------------------------------------------ binary to BCD, one field at a time
    reg [31:0] bin;
    reg [31:0] acc;          // 8 BCD digits being built
    reg [5:0]  step;         // 0..32
    reg        cur_neg;
    reg        busy;

    // add 3 to every digit that is 5 or more (before each shift)
    function [31:0] add3;
        input [31:0] d;
        integer i;
        begin
            add3 = d;
            for (i = 0; i < 8; i = i + 1)
                if (d[4*i +: 4] >= 4'd5) add3[4*i +: 4] = d[4*i +: 4] + 4'd3;
        end
    endfunction

    wire [31:0] acc_adj = add3(acc);

    always @(posedge clk) begin
        if (rst) begin
            idx     <= 6'd0;
            bin     <= 32'd0;
            acc     <= 32'd0;
            step    <= 6'd0;
            cur_neg <= 1'b0;
            busy    <= 1'b0;
            bcd     <= {(`DN_N*32){1'b0}};
            neg     <= {`DN_N{1'b0}};
        end else if (!busy) begin
            bin     <= (val > MAX_SHOWN) ? MAX_SHOWN : val;
            cur_neg <= val_neg;
            acc     <= 32'd0;
            step    <= 6'd0;
            busy    <= 1'b1;
        end else if (step != 6'd32) begin
            {acc, bin} <= {acc_adj, bin} << 1;
            step       <= step + 6'd1;
        end else begin
            bcd[32*idx +: 32] <= acc;
            neg[idx]          <= cur_neg && (acc != 32'd0);
            idx               <= (idx == `DN_N - 1) ? 6'd0 : idx + 6'd1;
            busy              <= 1'b0;
        end
    end
endmodule

`default_nettype wire
