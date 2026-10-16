`timescale 1ns / 1ps
`default_nettype none

// spread_calc: mid price -> bid and ask.
//   bid = price - SPREAD, clamped so it never drops below 1 cent
//   ask = price + SPREAD, saturating at $655.35
// [ASSUMPTION] SPREAD = 5 cents per side is a proposal.
module spread_calc #(
    parameter SPREAD = 5
) (
    input  wire [15:0] price,
    output wire [15:0] bid,
    output wire [15:0] ask
);
    wire [16:0] ask_full = {1'b0, price} + SPREAD;

    assign ask = ask_full[16] ? 16'hFFFF : ask_full[15:0];
    assign bid = (price > SPREAD) ? price - SPREAD : 16'd1;
endmodule

`default_nettype wire
