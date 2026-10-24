`timescale 1ns / 1ps

// Compact live financial information for the OLED.
//
// The values remain live, but are rendered as hexadecimal nibbles.  This
// avoids synthesizing wide decimal dividers twice (once per OLED), which is
// too expensive for the Artix-7 35T used by the board.
module portfolio_info_layer (
    input  wire [12:0] pixel_index,
    input  wire [3:0]  screen_state,
    input  wire [31:0] cash,
    input  wire [9:0]  pos0,
    input  wire [9:0]  pos1,
    input  wire [31:0] portfolio_value,
    input  wire [15:0] selected_price,
    output reg         text_pixel
);

    localparam [3:0] PORTFOLIO = 4'd1;
    localparam [3:0] SPECIFIC  = 4'd3;

    wire [6:0] pixel_x = pixel_index[6:0];
    wire [5:0] pixel_y = pixel_index[12:7];
    reg [7:0] char_code;
    reg [4:0] char_position;
    reg [4:0] line_length;
    reg [5:0] line_y;
    reg [1:0] line_select;
    reg       line_active;
    reg [2:0] glyph_x;
    reg [2:0] glyph_y;
    reg [6:0] line_start_x;
    wire      glyph_pixel;

    font_renderer font_renderer_inst (
        .char_code(char_code),
        .glyph_x(glyph_x),
        .glyph_y(glyph_y),
        .pixel_on(glyph_pixel)
    );

    function [7:0] hex_char;
        input [3:0] nibble;
        begin
            if (nibble < 4'd10)
                hex_char = 8'h30 + nibble;
            else
                hex_char = 8'h41 + (nibble - 4'd10);
        end
    endfunction

    always @(*) begin
        char_code   = 8'h20;
        char_position = 5'd0;
        line_length = 5'd0;
        line_y      = 6'd0;
        line_select = 2'd0;
        line_active = 1'b0;
        glyph_x     = 3'd0;
        glyph_y     = 3'd0;
        line_start_x = 7'd2;

        if (screen_state == PORTFOLIO) begin
            if ((pixel_y >= 6'd44) && (pixel_y < 6'd51)) begin
                line_select = 2'd0;
                line_y = 6'd44;
                line_length = 5'd13; // C + 5 hex digits + V + 5 hex digits
                line_active = 1'b1;
            end else if ((pixel_y >= 6'd54) && (pixel_y < 6'd61)) begin
                line_select = 2'd1;
                line_y = 6'd54;
                line_length = 5'd11; // A0000 M0000
                line_active = 1'b1;
            end
        end else if ((screen_state == SPECIFIC) &&
                     (pixel_y >= 6'd24) && (pixel_y < 6'd31)) begin
            line_select = 2'd0;
            line_y = 6'd24;
            line_start_x = 7'd68;
            line_length = 5'd5; // P plus four price nibbles
            line_active = 1'b1;
        end

        if (line_active && (pixel_x >= line_start_x)) begin
            // Six-pixel character cells.  The small range checks synthesize
            // much more cheaply than a variable divide/modulo pair.
            if      (pixel_x < line_start_x + 7'd6)  char_position = 5'd0;
            else if (pixel_x < line_start_x + 7'd12) char_position = 5'd1;
            else if (pixel_x < line_start_x + 7'd18) char_position = 5'd2;
            else if (pixel_x < line_start_x + 7'd24) char_position = 5'd3;
            else if (pixel_x < line_start_x + 7'd30) char_position = 5'd4;
            else if (pixel_x < line_start_x + 7'd36) char_position = 5'd5;
            else if (pixel_x < line_start_x + 7'd42) char_position = 5'd6;
            else if (pixel_x < line_start_x + 7'd48) char_position = 5'd7;
            else if (pixel_x < line_start_x + 7'd54) char_position = 5'd8;
            else if (pixel_x < line_start_x + 7'd60) char_position = 5'd9;
            else if (pixel_x < line_start_x + 7'd66) char_position = 5'd10;
            else if (pixel_x < line_start_x + 7'd72) char_position = 5'd11;
            else char_position = 5'd12;

            glyph_x = pixel_x - line_start_x - (char_position * 3'd6);
            glyph_y = pixel_y - line_y;

            if (screen_state == PORTFOLIO) begin
                if (line_select == 2'd0) begin
                    case (char_position)
                        5'd0:  char_code = 8'h43; // C
                        5'd1:  char_code = hex_char(cash[19:16]);
                        5'd2:  char_code = hex_char(cash[15:12]);
                        5'd3:  char_code = hex_char(cash[11:8]);
                        5'd4:  char_code = hex_char(cash[7:4]);
                        5'd5:  char_code = hex_char(cash[3:0]);
                        5'd6:  char_code = 8'h20;
                        5'd7:  char_code = 8'h56; // V
                        5'd8:  char_code = hex_char(portfolio_value[19:16]);
                        5'd9:  char_code = hex_char(portfolio_value[15:12]);
                        5'd10: char_code = hex_char(portfolio_value[11:8]);
                        5'd11: char_code = hex_char(portfolio_value[7:4]);
                        default: char_code = hex_char(portfolio_value[3:0]);
                    endcase
                end else begin
                    case (char_position)
                        5'd0:  char_code = 8'h41; // A
                        5'd1:  char_code = hex_char({2'b00, pos0[9:8]});
                        5'd2:  char_code = hex_char(pos0[7:4]);
                        5'd3:  char_code = hex_char(pos0[3:0]);
                        5'd4:  char_code = 8'h20;
                        5'd5:  char_code = 8'h4D; // M
                        5'd6:  char_code = hex_char({2'b00, pos1[9:8]});
                        5'd7:  char_code = hex_char(pos1[7:4]);
                        5'd8:  char_code = hex_char(pos1[3:0]);
                        default: char_code = 8'h20;
                    endcase
                end
            end else if (screen_state == SPECIFIC) begin
                case (char_position)
                    5'd0: char_code = 8'h50; // P
                    5'd1: char_code = hex_char(selected_price[15:12]);
                    5'd2: char_code = hex_char(selected_price[11:8]);
                    5'd3: char_code = hex_char(selected_price[7:4]);
                    default: char_code = hex_char(selected_price[3:0]);
                endcase
            end
        end

        text_pixel = line_active && (char_position < line_length) &&
                     (glyph_x < 3'd5) && (glyph_y < 3'd7) && glyph_pixel;
    end

endmodule
