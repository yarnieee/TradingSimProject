`timescale 1ns / 1ps

// Shared text layer. Characters use a five-pixel glyph and one-pixel gap.
// Long screen names are split across two lines so they fit on the 96x64 OLED.
module text_layer (
    input  [12:0] pixel_index,
    input  [3:0]  screen_state,
    output reg    text_pixel
);

    localparam TITLE       = 4'd0;
    localparam PORTFOLIO   = 4'd1;
    localparam STOCKS      = 4'd2;
    localparam SPECIFIC    = 4'd3;
    localparam BUY_STOCK   = 4'd4;
    localparam SELL_STOCK  = 4'd5;
    localparam QUANTITY    = 4'd6;
    localparam CONFIRM     = 4'd7;
    localparam GAME_END    = 4'd8;

    wire [6:0] pixel_x = pixel_index % 96;
    wire [5:0] pixel_y = pixel_index / 96;

    reg [7:0] char_code;
    reg [4:0] char_position;
    reg [4:0] line_length;
    reg [5:0] line_y;
    reg       line_select;
    reg       line_active;
    reg [2:0] glyph_x;
    reg [2:0] glyph_y;
    wire      glyph_pixel;

    font_renderer font_renderer_inst (
        .char_code(char_code),
        .glyph_x(glyph_x),
        .glyph_y(glyph_y),
        .pixel_on(glyph_pixel)
    );

    function [4:0] text_length;
        input [3:0] state;
        input       line;
        begin
            text_length = 0;
            case (state)
                TITLE: begin
                    if (line == 0) text_length = 12;
                end
                PORTFOLIO: begin
                    if (line == 0) text_length = 16;
                end
                STOCKS: begin
                    if (line == 0) text_length = 13;
                end
                SPECIFIC: begin
                    if (line == 0) text_length = 14;
                    else          text_length = 6;
                end
                BUY_STOCK: begin
                    if (line == 0) text_length = 12;
                    else          text_length = 12;
                end
                SELL_STOCK: begin
                    if (line == 0) text_length = 13;
                    else          text_length = 12;
                end
                QUANTITY: begin
                    if (line == 0) text_length = 8;
                    else          text_length = 6;
                end
                CONFIRM: begin
                    if (line == 0) text_length = 12;
                    else          text_length = 6;
                end
                GAME_END: begin
                    if (line == 0) text_length = 8;
                    else          text_length = 6;
                end
                default: text_length = 0;
            endcase
        end
    endfunction

    function [7:0] text_char;
        input [3:0] state;
        input       line;
        input [4:0] position;
        begin
            text_char = 8'h20;
            case (state)
                TITLE: begin
                    case (position)
                        0: text_char = 8'h74; 1: text_char = 8'h69;
                        2: text_char = 8'h74; 3: text_char = 8'h6c;
                        4: text_char = 8'h65; 5: text_char = 8'h20;
                        6: text_char = 8'h73; 7: text_char = 8'h63;
                        8: text_char = 8'h72; 9: text_char = 8'h65;
                        10: text_char = 8'h65; 11: text_char = 8'h6e;
                        default: text_char = 8'h20;
                    endcase
                end
                PORTFOLIO: begin
                    case (position)
                        0: text_char = 8'h70; 1: text_char = 8'h6f;
                        2: text_char = 8'h72; 3: text_char = 8'h74;
                        4: text_char = 8'h66; 5: text_char = 8'h6f;
                        6: text_char = 8'h6c; 7: text_char = 8'h69;
                        8: text_char = 8'h6f; 9: text_char = 8'h20;
                        10: text_char = 8'h73; 11: text_char = 8'h63;
                        12: text_char = 8'h72; 13: text_char = 8'h65;
                        14: text_char = 8'h65; 15: text_char = 8'h6e;
                        default: text_char = 8'h20;
                    endcase
                end
                STOCKS: begin
                    case (position)
                        0: text_char = 8'h73; 1: text_char = 8'h74;
                        2: text_char = 8'h6f; 3: text_char = 8'h63;
                        4: text_char = 8'h6b; 5: text_char = 8'h73;
                        6: text_char = 8'h20; 7: text_char = 8'h73;
                        8: text_char = 8'h63; 9: text_char = 8'h72;
                        10: text_char = 8'h65; 11: text_char = 8'h65;
                        12: text_char = 8'h6e;
                        default: text_char = 8'h20;
                    endcase
                end
                SPECIFIC: begin
                    if (line == 0) begin
                        case (position)
                            0: text_char = 8'h73; 1: text_char = 8'h70;
                            2: text_char = 8'h65; 3: text_char = 8'h63;
                            4: text_char = 8'h69; 5: text_char = 8'h66;
                            6: text_char = 8'h69; 7: text_char = 8'h63;
                            8: text_char = 8'h20; 9: text_char = 8'h73;
                            10: text_char = 8'h74; 11: text_char = 8'h6f;
                            12: text_char = 8'h63; 13: text_char = 8'h6b;
                            default: text_char = 8'h20;
                        endcase
                    end else begin
                        case (position)
                            0: text_char = 8'h73; 1: text_char = 8'h63;
                            2: text_char = 8'h72; 3: text_char = 8'h65;
                            4: text_char = 8'h65; 5: text_char = 8'h6e;
                            default: text_char = 8'h20;
                        endcase
                    end
                end
                BUY_STOCK: begin
                    if (line == 0) begin
                        case (position)
                            0: text_char = 8'h62; 1: text_char = 8'h75;
                            2: text_char = 8'h79; 3: text_char = 8'h20;
                            4: text_char = 8'h73; 5: text_char = 8'h70;
                            6: text_char = 8'h65; 7: text_char = 8'h63;
                            8: text_char = 8'h69; 9: text_char = 8'h66;
                            10: text_char = 8'h69; 11: text_char = 8'h63;
                            default: text_char = 8'h20;
                        endcase
                    end else begin
                        case (position)
                            0: text_char = 8'h73; 1: text_char = 8'h74;
                            2: text_char = 8'h6f; 3: text_char = 8'h63;
                            4: text_char = 8'h6b; 5: text_char = 8'h20;
                            6: text_char = 8'h73; 7: text_char = 8'h63;
                            8: text_char = 8'h72; 9: text_char = 8'h65;
                            10: text_char = 8'h65; 11: text_char = 8'h6e;
                            default: text_char = 8'h20;
                        endcase
                    end
                end
                SELL_STOCK: begin
                    if (line == 0) begin
                        case (position)
                            0: text_char = 8'h73; 1: text_char = 8'h65;
                            2: text_char = 8'h6c; 3: text_char = 8'h6c;
                            4: text_char = 8'h20; 5: text_char = 8'h73;
                            6: text_char = 8'h70; 7: text_char = 8'h65;
                            8: text_char = 8'h63; 9: text_char = 8'h69;
                            10: text_char = 8'h66; 11: text_char = 8'h69;
                            12: text_char = 8'h63;
                            default: text_char = 8'h20;
                        endcase
                    end else begin
                        case (position)
                            0: text_char = 8'h73; 1: text_char = 8'h74;
                            2: text_char = 8'h6f; 3: text_char = 8'h63;
                            4: text_char = 8'h6b; 5: text_char = 8'h20;
                            6: text_char = 8'h73; 7: text_char = 8'h63;
                            8: text_char = 8'h72; 9: text_char = 8'h65;
                            10: text_char = 8'h65; 11: text_char = 8'h6e;
                            default: text_char = 8'h20;
                        endcase
                    end
                end
                QUANTITY: begin
                    if (line == 0) begin
                        case (position)
                            0: text_char = 8'h71; 1: text_char = 8'h75;
                            2: text_char = 8'h61; 3: text_char = 8'h6e;
                            4: text_char = 8'h74; 5: text_char = 8'h69;
                            6: text_char = 8'h74; 7: text_char = 8'h79;
                            default: text_char = 8'h20;
                        endcase
                    end else begin
                        case (position)
                            0: text_char = 8'h73; 1: text_char = 8'h63;
                            2: text_char = 8'h72; 3: text_char = 8'h65;
                            4: text_char = 8'h65; 5: text_char = 8'h6e;
                            default: text_char = 8'h20;
                        endcase
                    end
                end
                CONFIRM: begin
                    if (line == 0) begin
                        case (position)
                            0: text_char = 8'h63; 1: text_char = 8'h6f;
                            2: text_char = 8'h6e; 3: text_char = 8'h66;
                            4: text_char = 8'h69; 5: text_char = 8'h72;
                            6: text_char = 8'h6d; 7: text_char = 8'h61;
                            8: text_char = 8'h74; 9: text_char = 8'h69;
                            10: text_char = 8'h6f; 11: text_char = 8'h6e;
                            default: text_char = 8'h20;
                        endcase
                    end else begin
                        case (position)
                            0: text_char = 8'h73; 1: text_char = 8'h63;
                            2: text_char = 8'h72; 3: text_char = 8'h65;
                            4: text_char = 8'h65; 5: text_char = 8'h6e;
                            default: text_char = 8'h20;
                        endcase
                    end
                end
                GAME_END: begin
                    if (line == 0) begin
                        case (position)
                            0: text_char = 8'h67; 1: text_char = 8'h61;
                            2: text_char = 8'h6d; 3: text_char = 8'h65;
                            4: text_char = 8'h20; 5: text_char = 8'h65;
                            6: text_char = 8'h6e; 7: text_char = 8'h64;
                            default: text_char = 8'h20;
                        endcase
                    end else begin
                        case (position)
                            0: text_char = 8'h73; 1: text_char = 8'h63;
                            2: text_char = 8'h72; 3: text_char = 8'h65;
                            4: text_char = 8'h65; 5: text_char = 8'h6e;
                            default: text_char = 8'h20;
                        endcase
                    end
                end
                default: text_char = 8'h20;
            endcase
        end
    endfunction

    always @(*) begin
        char_code = 8'h20;
        char_position = 0;
        line_length = 0;
        line_y = 0;
        line_select = 0;
        line_active = 0;
        glyph_x = 0;
        glyph_y = 0;

        // Two-line screens use rows 20..26 and 34..40. Single-line screens
        // use rows 28..34.
        if (text_length(screen_state, 1) != 0) begin
            if ((pixel_y >= 20) && (pixel_y < 27)) begin
                line_select = 0;
                line_y = 20;
                line_active = 1;
            end else if ((pixel_y >= 34) && (pixel_y < 41)) begin
                line_select = 1;
                line_y = 34;
                line_active = 1;
            end
        end else if ((pixel_y >= 28) && (pixel_y < 35)) begin
            line_select = 0;
            line_y = 28;
            line_active = 1;
        end

        if (line_active) begin
            char_position = pixel_x / 6;
            glyph_x = pixel_x % 6;
            glyph_y = pixel_y - line_y;
            line_length = text_length(screen_state, line_select);
            char_code = text_char(screen_state, line_select, char_position);
        end

        text_pixel = glyph_pixel &&
                     (char_position < line_length) &&
                     (glyph_x < 5) &&
                     (glyph_y < 7);
    end

endmodule
