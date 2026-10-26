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
    input  wire [9:0]  selected_position,
    input  wire [31:0] selected_value,
    input  wire signed [32:0] selected_pnl,
    input  wire        specific_metrics_enable,
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
    wire [32:0] pnl_magnitude = selected_pnl[32] ?
                                 (~selected_pnl + 33'd1) : selected_pnl;

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

        if ((screen_state == SPECIFIC) && specific_metrics_enable) begin
            if ((pixel_y >= 6'd14) && (pixel_y < 6'd21)) begin
                line_select = 2'd0;
                line_y = 6'd14;
                line_length = 5'd7; // POS plus three position nibbles
                line_active = 1'b1;
            end else if ((pixel_y >= 6'd22) && (pixel_y < 6'd29)) begin
                line_select = 2'd1;
                line_y = 6'd22;
                line_length = 5'd8; // VAL plus four value nibbles
                line_active = 1'b1;
            end else if ((pixel_y >= 6'd30) && (pixel_y < 6'd37)) begin
                line_select = 2'd2;
                line_y = 6'd30;
                line_length = 5'd8; // PNL plus sign and four nibbles
                line_active = 1'b1;
            end
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

            if ((screen_state == SPECIFIC) && specific_metrics_enable) begin
                case (line_select)
                    2'd0: begin
                        case (char_position)
                            5'd0: char_code = 8'h50; // P
                            5'd1: char_code = 8'h4F; // O
                            5'd2: char_code = 8'h53; // S
                            5'd3: char_code = 8'h20;
                            5'd4: char_code = hex_char({2'b00, selected_position[9:8]});
                            5'd5: char_code = hex_char(selected_position[7:4]);
                            default: char_code = hex_char(selected_position[3:0]);
                        endcase
                    end
                    2'd1: begin
                        case (char_position)
                            5'd0: char_code = 8'h56; // V
                            5'd1: char_code = 8'h41; // A
                            5'd2: char_code = 8'h4C; // L
                            5'd3: char_code = 8'h20;
                            5'd4: char_code = hex_char(selected_value[15:12]);
                            5'd5: char_code = hex_char(selected_value[11:8]);
                            5'd6: char_code = hex_char(selected_value[7:4]);
                            default: char_code = hex_char(selected_value[3:0]);
                        endcase
                    end
                    default: begin
                        case (char_position)
                            5'd0: char_code = 8'h50; // P
                            5'd1: char_code = 8'h4E; // N
                            5'd2: char_code = 8'h4C; // L
                            5'd3: char_code = selected_pnl[32] ? 8'h2D : 8'h2B;
                            5'd4: char_code = hex_char(pnl_magnitude[15:12]);
                            5'd5: char_code = hex_char(pnl_magnitude[11:8]);
                            5'd6: char_code = hex_char(pnl_magnitude[7:4]);
                            default: char_code = hex_char(pnl_magnitude[3:0]);
                        endcase
                    end
                endcase
            end
        end

        text_pixel = line_active && (char_position < line_length) &&
                     (glyph_x < 3'd5) && (glyph_y < 3'd7) && glyph_pixel;
    end

endmodule
