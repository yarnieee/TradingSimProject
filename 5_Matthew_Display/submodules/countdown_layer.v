`timescale 1ns / 1ps

// Countdown label for the right OLED.  The timer is the number of simulated
// trading days remaining; it is visible on every active game screen except
// the title and terminal screens.
module countdown_layer (
    input  wire [12:0] pixel_index,
    input  wire [3:0]  screen_state,
    input  wire [31:0] time_remaining,
    output reg         pixel_active,
    output reg  [15:0] pixel_color
);
    localparam [3:0] TITLE = 4'd0;
    localparam [3:0] GAME_END = 4'd10;

    wire [6:0] pixel_x = pixel_index % 96;
    wire [5:0] pixel_y = pixel_index / 96;
    reg [7:0] char_code;
    reg [2:0] glyph_x, glyph_y;
    reg [2:0] char_position;
    reg [3:0] tens_digit, ones_digit;
    wire glyph_pixel;

    font_renderer font_renderer_inst (
        .char_code(char_code), .glyph_x(glyph_x), .glyph_y(glyph_y),
        .pixel_on(glyph_pixel)
    );

    always @(*) begin
        if      (time_remaining >= 32'd90) tens_digit = 4'd9;
        else if (time_remaining >= 32'd80) tens_digit = 4'd8;
        else if (time_remaining >= 32'd70) tens_digit = 4'd7;
        else if (time_remaining >= 32'd60) tens_digit = 4'd6;
        else if (time_remaining >= 32'd50) tens_digit = 4'd5;
        else if (time_remaining >= 32'd40) tens_digit = 4'd4;
        else if (time_remaining >= 32'd30) tens_digit = 4'd3;
        else if (time_remaining >= 32'd20) tens_digit = 4'd2;
        else if (time_remaining >= 32'd10) tens_digit = 4'd1;
        else tens_digit = 4'd0;

        case (tens_digit)
            4'd9: ones_digit = (time_remaining >= 90) ? time_remaining - 90 : 0;
            4'd8: ones_digit = (time_remaining >= 80) ? time_remaining - 80 : 0;
            4'd7: ones_digit = (time_remaining >= 70) ? time_remaining - 70 : 0;
            4'd6: ones_digit = (time_remaining >= 60) ? time_remaining - 60 : 0;
            4'd5: ones_digit = (time_remaining >= 50) ? time_remaining - 50 : 0;
            4'd4: ones_digit = (time_remaining >= 40) ? time_remaining - 40 : 0;
            4'd3: ones_digit = (time_remaining >= 30) ? time_remaining - 30 : 0;
            4'd2: ones_digit = (time_remaining >= 20) ? time_remaining - 20 : 0;
            4'd1: ones_digit = (time_remaining >= 10) ? time_remaining - 10 : 0;
            default: ones_digit = time_remaining[3:0];
        endcase

        if (time_remaining >= 32'd100) begin
            tens_digit = 4'd9;
            ones_digit = 4'd9;
        end

        char_code = 8'h20;
        char_position = 3'd0;
        glyph_x = 3'd0;
        glyph_y = 3'd0;
        pixel_active = 1'b0;
        pixel_color = 16'hFFFF;

        if ((screen_state != TITLE) && (screen_state != GAME_END) &&
            (pixel_y >= 6'd56) && (pixel_x >= 7'd62) &&
            (pixel_x < 7'd92)) begin
            if      (pixel_x < 7'd67) char_position = 3'd0;
            else if (pixel_x < 7'd72) char_position = 3'd1;
            else if (pixel_x < 7'd77) char_position = 3'd2;
            else if (pixel_x < 7'd82) char_position = 3'd3;
            else if (pixel_x < 7'd87) char_position = 3'd4;
            else char_position = 3'd5;

            glyph_x = pixel_x - 7'd62 - (char_position * 3'd5);
            glyph_y = pixel_y - 6'd56;
            case (char_position)
                3'd0: char_code = 8'h54; // T
                3'd1: char_code = 8'h49; // I
                3'd2: char_code = 8'h4D; // M
                3'd3: char_code = 8'h45; // E
                3'd4: char_code = 8'h30 + tens_digit;
                default: char_code = 8'h30 + ones_digit;
            endcase
            pixel_active = (glyph_x < 3'd5) && (glyph_y < 3'd7) && glyph_pixel;
            pixel_color = 16'hFFE0;
        end
    end
endmodule
