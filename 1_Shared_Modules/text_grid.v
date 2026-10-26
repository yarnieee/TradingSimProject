`timescale 1ns / 1ps
`default_nettype none

// text_grid: the screen layout shared by both OLEDs (96 x 64).
//
//   row 0     y  0- 9   header bar        16 cells of 6 px, text at y 2-8
//   rows 1-6  y 10-63   body, 9 px each   16 cells of 6 px, text 1 px below the row top
//   big row   y 10-27   (big = 1)         replaces rows 1-2: 8 cells of 12 px, text drawn 2x (10 x 14)
//
// The page tells it, for the cell at (row, col), which character to draw (ASCII,
// Matthew's 5x7 font_renderer) and in which colours: fg for the letter, bg for
// the rest of the cell. A run of cells with one bg colour reads as a button or a bar.
// Every row has at least one blank pixel line above and below its text.
//
// Purely combinational: (x, y) -> (row, col) -> the page's cell -> colour.
module text_grid (
    input  wire [6:0]  x,
    input  wire [5:0]  y,
    input  wire        big,          // rows 1-2 are one big row (row = 1)
    output reg  [2:0]  row,          // 0 header, 1-6 body
    output reg  [3:0]  col,          // 0-15 (0-7 on the big row)
    output reg         is_big,       // this pixel is on the big row
    input  wire [7:0]  ch,           // the page's cell at (row, col)
    input  wire [15:0] fg,
    input  wire [15:0] bg,
    output wire [15:0] color
);
    reg [5:0] top;                   // first text line of this row
    reg [2:0] gx, gy;

    always @* begin
        // row and the y of its text
        is_big = 1'b0;
        if (y < 6'd10) begin
            row = 3'd0; top = 6'd2;
        end else if (big && y < 6'd28) begin
            row = 3'd1; top = 6'd12; is_big = 1'b1;
        end else if (y < 6'd19) begin row = 3'd1; top = 6'd11;
        end else if (y < 6'd28) begin row = 3'd2; top = 6'd20;
        end else if (y < 6'd37) begin row = 3'd3; top = 6'd29;
        end else if (y < 6'd46) begin row = 3'd4; top = 6'd38;
        end else if (y < 6'd55) begin row = 3'd5; top = 6'd47;
        end else begin                 row = 3'd6; top = 6'd56;
        end

        // column and the pixel inside the letter (7 = outside it)
        if (is_big) begin
            col = x / 12;
            gx  = (x % 12) >> 1;                       // 0-5, 5 is the gap
            gy  = (y >= top && y < top + 6'd14) ? (y - top) >> 1 : 3'd7;
        end else begin
            col = x / 6;
            gx  = x % 6;
            gy  = (y >= top && y < top + 6'd7) ? y - top : 3'd7;
        end
    end

    wire glyph;
    font_renderer font (.char_code(ch), .glyph_x(gx), .glyph_y(gy), .pixel_on(glyph));

    assign color = glyph ? fg : bg;
endmodule

`default_nettype wire
