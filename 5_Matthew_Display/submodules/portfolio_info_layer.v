`timescale 1ns / 1ps

// Compact live financial information for the OLED.
// Cash and portfolio value are stored in cents and displayed in whole dollars.
// Portfolio lines use the compact forms "C10000 V10000" and "A0000 M0000".
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

    wire [6:0] pixel_x = pixel_index % 96;
    wire [5:0] pixel_y = pixel_index / 96;

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

    function [7:0] decimal_char;
        input [31:0] value;
        input [3:0]  index;
        reg [31:0] scaled_value;
        begin
            case (index)
                4'd0: scaled_value = value / 10000000;
                4'd1: scaled_value = value / 1000000;
                4'd2: scaled_value = value / 100000;
                4'd3: scaled_value = value / 10000;
                4'd4: scaled_value = value / 1000;
                4'd5: scaled_value = value / 100;
                4'd6: scaled_value = value / 10;
                default: scaled_value = value;
            endcase
            decimal_char = 8'h30 + (scaled_value % 10);
        end
    endfunction

    function [7:0] position_char;
        input [9:0] value;
        input [2:0] index;
        reg [31:0] extended_value;
        begin
            extended_value = value;
            case (index)
                3'd0: position_char = 8'h30 + ((extended_value / 1000) % 10);
                3'd1: position_char = 8'h30 + ((extended_value / 100) % 10);
                3'd2: position_char = 8'h30 + ((extended_value / 10) % 10);
                default: position_char = 8'h30 + (extended_value % 10);
            endcase
        end
    endfunction

    function [7:0] price_char;
        input [15:0] value;
        input [2:0]  index;
        begin
            case (index)
                3'd0: price_char = 8'h30 + ((value / 10000) % 10);
                3'd1: price_char = 8'h30 + ((value / 1000) % 10);
                3'd2: price_char = 8'h30 + ((value / 100) % 10);
                3'd3: price_char = 8'h30 + ((value / 10) % 10);
                default: price_char = 8'h30 + (value % 10);
            endcase
        end
    endfunction

    function [4:0] info_length;
        input [3:0] state;
        input [1:0] line;
        begin
            info_length = 0;
            if (state == PORTFOLIO) begin
                case (line)
                    2'd0: info_length = 13; // C + 5 digits + V + 5 digits
                    2'd1: info_length = 11; // A0000 M0000
                    default: info_length = 0;
                endcase
            end else if (state == SPECIFIC) begin
                if (line == 0) info_length = 4; // P + 3 whole-dollar digits
            end
        end
    endfunction

    function [7:0] info_char;
        input [3:0]  state;
        input [1:0]  line;
        input [4:0]  position;
        begin
            info_char = 8'h20;
            if (state == PORTFOLIO) begin
                case (line)
                    2'd0: begin
                        case (position)
                            0: info_char = 8'h43; // C
                            1: info_char = decimal_char(cash / 100, 3);
                            2: info_char = decimal_char(cash / 100, 4);
                            3: info_char = decimal_char(cash / 100, 5);
                            4: info_char = decimal_char(cash / 100, 6);
                            5: info_char = decimal_char(cash / 100, 7);
                            6: info_char = 8'h20;
                            7: info_char = 8'h56; // V
                            8: info_char = decimal_char(portfolio_value / 100, 3);
                            9: info_char = decimal_char(portfolio_value / 100, 4);
                            10: info_char = decimal_char(portfolio_value / 100, 5);
                            11: info_char = decimal_char(portfolio_value / 100, 6);
                            default: info_char = decimal_char(portfolio_value / 100, 7);
                        endcase
                    end
                    2'd1: begin
                        if (position == 0)
                            info_char = 8'h41; // A
                        else if ((position >= 1) && (position <= 4))
                            info_char = position_char(pos0, position-1);
                        else if (position == 5)
                            info_char = 8'h20;
                        else if (position == 6)
                            info_char = 8'h4D; // M
                        else
                            info_char = position_char(pos1, position-7);
                    end
                    default: info_char = 8'h20;
                endcase
            end else if (state == SPECIFIC) begin
                if (position == 0)
                    info_char = 8'h50; // P, whole-dollar price marker
                else
                    info_char = decimal_char({16'd0, selected_price} / 100,
                                             8-position);
            end
        end
    endfunction

    always @(*) begin
        char_code = 8'h20;
        char_position = 0;
        line_length = 0;
        line_y = 0;
        line_select = 0;
        line_active = 1'b0;
        glyph_x = 0;
        glyph_y = 0;
        line_start_x = 2;

        if (screen_state == PORTFOLIO) begin
            if ((pixel_y >= 44) && (pixel_y < 51)) begin
                line_select = 0;
                line_y = 44;
                line_active = 1'b1;
            end else if ((pixel_y >= 54) && (pixel_y < 61)) begin
                line_select = 1;
                line_y = 54;
                line_active = 1'b1;
            end
        end else if ((screen_state == SPECIFIC) &&
                     (pixel_y >= 24) && (pixel_y < 31)) begin
            line_select = 0;
            line_y = 24;
            line_start_x = 68;
            line_active = 1'b1;
        end

        if (line_active && (pixel_x >= line_start_x)) begin
            char_position = (pixel_x - line_start_x) / 6;
            glyph_x = (pixel_x - line_start_x) % 6;
            glyph_y = pixel_y - line_y;
            line_length = info_length(screen_state, line_select);
            char_code = info_char(screen_state, line_select, char_position);
        end

        text_pixel = line_active && (char_position < line_length) &&
                     (glyph_x < 5) && (glyph_y < 7) && glyph_pixel;
    end

endmodule
