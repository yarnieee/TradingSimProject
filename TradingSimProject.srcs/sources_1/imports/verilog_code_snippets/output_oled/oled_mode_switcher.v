`timescale 1ns / 1ps

/////////////
// instantiate via:
//
// wire [2:0] mode;
// wire [12:0] pixel_index;
// oled_mode_switcher oled_mode_switcher_inst (
//     .clk(clk),
//     .mode(mode),
//     .pixel_index(pixel_index),
//     .step_tick(step_tick),
//     .rst(rst),
//     .pixel_data(pixel_data)
//     );
/////////////

// Shape parameters are kept here so adding a shape does not require another
// drawing submodule.  The packed layout is:
// {width, height, x, y, x_offset, y_offset}
//
// For a rectangle, x/y is the top-left corner.  For a circle, x/y is the
// centre and width/height are the horizontal/vertical radii.  Offsets are
// signed two's-complement pixel offsets.
module oled_mode_switcher (
    input wire clk,
    input wire [2:0] mode,
    input wire [12:0] pixel_index,
    input wire rst,
    output reg [15:0] pixel_data
);

    localparam RED = 16'hF800;
    localparam BLUE = 16'h001F;
    localparam GREEN = 16'h07E0;
    localparam WHITE = 16'hFFFF;
    localparam BLACK = 16'h0000;
    localparam YELLOW = 16'hFFE0;
    localparam MAGENTA = 16'hF81F;
    localparam CYAN = 16'h07FF;

    wire [6:0] pixel_x = pixel_index % 96;
    wire [5:0] pixel_y = pixel_index / 96;

    // Extend every coordinate to 9-bit signed values before applying the
    // signed offsets.  This also makes negative offsets behave naturally at
    // the display boundary.
    wire signed [8:0] pixel_x_signed = {2'b00, pixel_x};
    wire signed [8:0] pixel_y_signed = {3'b000, pixel_y};

    wire signed [7:0] x_offset;
    wire signed [7:0] y_offset;

    always @(*) begin
        pixel_data = BLACK;

        case (mode)
            3'd1: begin
                pixel_data = BLUE;
            end

            default: begin
                pixel_data = BLACK;
            end
        endcase
    end

endmodule
