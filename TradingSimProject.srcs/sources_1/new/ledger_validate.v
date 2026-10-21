//decides whether an incoming fill is allowed,
// and whether a sell closes the whole position (so no divide is needed).
module ledger_validate (
    input  wire        fill_side,    // 0 = buy, 1 = sell
    input  wire [7:0]  fill_qty,
    input  wire [31:0] cost_in,      // price * qty + fee (cents)
    input  wire [31:0] cash,
    input  wire [9:0]  pos_sel,      // current position in the fill's stock
    output wire        reject,       // 1 = do not apply this fill
    output wire        full_close    // 1 = sell of the entire position
);
    wire [10:0] newpos   = pos_sel + fill_qty;          // 11 bits so overflow is visible

    wire bad_qty  = (fill_qty == 8'd0);
    wire bad_buy  = ~fill_side & ((cost_in > cash) | (newpos > 11'd1023));
    wire bad_sell =  fill_side & (fill_qty > pos_sel);

    assign reject     = bad_qty | bad_buy | bad_sell;
    assign full_close = fill_side & (fill_qty == pos_sel);
endmodule
