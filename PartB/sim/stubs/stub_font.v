`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// stub_font: 3x5 font standing in for D's font ROM.
// Character codes follow trading_defs.vh. Synthesisable (a case ROM), so it
// can go on the board for Part B bring-up until D's ROM is integrated.
// [TEAM] D's ROM needs a 3x5 port with this behaviour, or B swaps this out.
//
// Glyph bits are rows top to bottom, 3 bits per row, MSB = leftmost pixel.
// col 3 is the gap between characters and is always off.
// Not included: the 5x7 set from the spec. Part B does not use it.
module stub_font (
    input  wire [5:0] ch,
    input  wire [2:0] row,     // 0..4
    input  wire [1:0] col,     // 0..3
    output wire       pix
);
    reg [14:0] g;
    always @* begin
        case (ch)
            6'd0:  g = 15'b111_101_101_101_111;   // 0
            6'd1:  g = 15'b010_110_010_010_111;   // 1
            6'd2:  g = 15'b111_001_111_100_111;   // 2
            6'd3:  g = 15'b111_001_111_001_111;   // 3
            6'd4:  g = 15'b101_101_111_001_001;   // 4
            6'd5:  g = 15'b111_100_111_001_111;   // 5
            6'd6:  g = 15'b111_100_111_101_111;   // 6
            6'd7:  g = 15'b111_001_010_010_010;   // 7
            6'd8:  g = 15'b111_101_111_101_111;   // 8
            6'd9:  g = 15'b111_101_111_001_111;   // 9
            6'd10: g = 15'b010_101_111_101_101;   // A
            6'd11: g = 15'b110_101_110_101_110;   // B
            6'd12: g = 15'b011_100_100_100_011;   // C
            6'd13: g = 15'b110_101_101_101_110;   // D
            6'd14: g = 15'b111_100_110_100_111;   // E
            6'd15: g = 15'b111_100_110_100_100;   // F
            6'd16: g = 15'b011_100_101_101_011;   // G
            6'd17: g = 15'b101_101_111_101_101;   // H
            6'd18: g = 15'b111_010_010_010_111;   // I
            6'd19: g = 15'b001_001_001_101_010;   // J
            6'd20: g = 15'b101_101_110_101_101;   // K
            6'd21: g = 15'b100_100_100_100_111;   // L
            6'd22: g = 15'b101_111_111_101_101;   // M
            6'd23: g = 15'b110_101_101_101_101;   // N
            6'd24: g = 15'b010_101_101_101_010;   // O
            6'd25: g = 15'b110_101_110_100_100;   // P
            6'd26: g = 15'b010_101_101_110_011;   // Q
            6'd27: g = 15'b110_101_110_101_101;   // R
            6'd28: g = 15'b011_100_010_001_110;   // S
            6'd29: g = 15'b111_010_010_010_010;   // T
            6'd30: g = 15'b101_101_101_101_111;   // U
            6'd31: g = 15'b101_101_101_101_010;   // V
            6'd32: g = 15'b101_101_111_111_101;   // W
            6'd33: g = 15'b101_101_010_101_101;   // X
            6'd34: g = 15'b101_101_010_010_010;   // Y
            6'd35: g = 15'b111_001_010_100_111;   // Z
            6'd36: g = 15'b000_000_000_000_000;   // space
            6'd37: g = 15'b000_000_000_000_010;   // .
            6'd38: g = 15'b000_010_111_010_000;   // +
            6'd39: g = 15'b000_000_111_000_000;   // -
            6'd40: g = 15'b101_001_010_100_101;   // %
            6'd41: g = 15'b011_110_010_011_110;   // $
            6'd42: g = 15'b000_010_000_010_000;   // :
            6'd43: g = 15'b001_001_010_100_100;   // /
            6'd44: g = 15'b010_101_111_100_011;   // @
            6'd45: g = 15'b110_100_100_100_110;   // [
            6'd46: g = 15'b011_001_001_001_011;   // ]
            6'd47: g = 15'b100_010_001_010_100;   // >
            default: g = 15'b000_000_000_000_000;
        endcase
    end

    wire [4:0] bitpos = row * 3 + col;     // 0..14 when row < 5 and col < 3
    assign pix = (row < 3'd5) && (col < 2'd3) && g[5'd14 - bitpos];
endmodule

`default_nettype wire
