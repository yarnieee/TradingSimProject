`timescale 1ns / 1ps

// Shared text layer. Characters use a five-pixel glyph and one-pixel gap.
// Long screen names are split across two lines so they fit on the 96x64 OLED.
module text_layer (
    input  [12:0] pixel_index,
    input  [3:0]  screen_state,
    input  [2:0]  selected_stock,
    input  [13:0] quantity,
    output reg    text_pixel
);

    localparam TITLE       = 4'd0;
    localparam PORTFOLIO   = 4'd1;
    localparam STOCKS      = 4'd2;
    localparam SPECIFIC    = 4'd3;
    localparam BUY_STOCK   = 4'd4;
    localparam SELL_STOCK  = 4'd5;
    localparam QUANTITY    = 4'd6;
    localparam ORDER_REVIEW = 4'd7;
    localparam ORDER_RESULT = 4'd8;
    localparam TRADE_RESULT = 4'd9;
    localparam GAME_END     = 4'd10;

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

    function [3:0] stock_name_length;
        input [2:0] stock;
        begin
            case (stock)
                3'd0: stock_name_length = 3;
                3'd1: stock_name_length = 4;
                3'd2: stock_name_length = 4;
                3'd3: stock_name_length = 3;
                default: stock_name_length = 3;
            endcase
        end
    endfunction

    function [7:0] stock_name_char;
        input [2:0] stock;
        input [2:0] position;
        begin
            stock_name_char = 8'h20;
            case (stock)
                3'd0: begin
                    case (position)
                        0: stock_name_char = 8'h41; // A
                        1: stock_name_char = 8'h4D; // M
                        2: stock_name_char = 8'h44; // D
                        default: stock_name_char = 8'h20;
                    endcase
                end
                3'd1: begin
                    case (position)
                        0: stock_name_char = 8'h41; // A
                        1: stock_name_char = 8'h56; // V
                        2: stock_name_char = 8'h47; // G
                        3: stock_name_char = 8'h4F; // O
                        default: stock_name_char = 8'h20;
                    endcase
                end
                3'd2: begin
                    case (position)
                        0: stock_name_char = 8'h4E; // N
                        1: stock_name_char = 8'h56; // V
                        2: stock_name_char = 8'h44; // D
                        3: stock_name_char = 8'h41; // A
                        default: stock_name_char = 8'h20;
                    endcase
                end
                3'd3: begin
                    case (position)
                        0: stock_name_char = 8'h47; // G
                        1: stock_name_char = 8'h4D; // M
                        2: stock_name_char = 8'h45; // E
                        default: stock_name_char = 8'h20;
                    endcase
                end
                default: stock_name_char = 8'h20;
            endcase
        end
    endfunction

    function [3:0] quantity_digit;
        input [13:0] value;
        input [1:0] index;
        begin
            case (index)
                2'd0: quantity_digit = value / 1000;
                2'd1: quantity_digit = (value / 100) % 10;
                2'd2: quantity_digit = (value / 10) % 10;
                default: quantity_digit = value % 10;
            endcase
        end
    endfunction

    function [4:0] text_length;
        input [3:0] state;
        input [2:0] stock;
        input [13:0] value;
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
                    if (line == 0) begin
                        text_length = stock_name_length(stock) + 6;
                    end else begin
                        text_length = 0;
                    end
                end
                BUY_STOCK: begin
                    if (line == 0)
                        text_length = 10 + stock_name_length(stock);
                    else
                        text_length = 10; // buy screen
                end
                SELL_STOCK: begin
                    if (line == 0)
                        text_length = 11 + stock_name_length(stock);
                    else
                        text_length = 11; // sell screen
                end
                QUANTITY: begin
                    if (line == 0)
                        text_length = 4 + stock_name_length(stock);
                    else
                        text_length = 8; // quantity
                end
                ORDER_REVIEW: begin
                    if (line == 0)
                        text_length = 9 + stock_name_length(stock);
                    else
                        text_length = 12; // order review
                end
                ORDER_RESULT: begin
                    if (line == 0) text_length = 12; // order result
                    else          text_length = 10; // processing
                end
                TRADE_RESULT: begin
                    if (line == 0) text_length = 12; // trade result
                    else          text_length = 7; // success
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
        input [2:0] stock;
        input [13:0] value;
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
                    if (position < stock_name_length(stock))
                        text_char = stock_name_char(stock, position);
                    else if (position == stock_name_length(stock))
                        text_char = 8'h20;
                    else begin
                        case (position - stock_name_length(stock) - 1)
                            0: text_char = 8'h73; // s
                            1: text_char = 8'h74; // t
                            2: text_char = 8'h6F; // o
                            3: text_char = 8'h63; // c
                            4: text_char = 8'h6B; // k
                            default: text_char = 8'h20;
                        endcase
                    end
                end
                BUY_STOCK: begin
                    if (line == 0) begin
                        if (position == 0)
                            text_char = 8'h62; // b
                        else if (position == 1)
                            text_char = 8'h75; // u
                        else if (position == 2)
                            text_char = 8'h79; // y
                        else if (position == 3)
                            text_char = 8'h20;
                        else if ((position >= 4) &&
                                 (position < 4 + stock_name_length(stock)))
                            text_char = stock_name_char(stock, position - 4);
                        else if (position == 4 + stock_name_length(stock))
                            text_char = 8'h20;
                        else begin
                            case (position - (5 + stock_name_length(stock)))
                                0: text_char = 8'h73; // s
                                1: text_char = 8'h74; // t
                                2: text_char = 8'h6F; // o
                                3: text_char = 8'h63; // c
                                4: text_char = 8'h6B; // k
                                default: text_char = 8'h20;
                            endcase
                        end
                    end else begin
                        case (position)
                            0: text_char = 8'h62; 1: text_char = 8'h75;
                            2: text_char = 8'h79; 3: text_char = 8'h20;
                            4: text_char = 8'h73; 5: text_char = 8'h63;
                            6: text_char = 8'h72; 7: text_char = 8'h65;
                            8: text_char = 8'h65; 9: text_char = 8'h6E;
                            default: text_char = 8'h20;
                        endcase
                    end
                end
                SELL_STOCK: begin
                    if (line == 0) begin
                        if (position == 0)
                            text_char = 8'h73; // s
                        else if (position == 1)
                            text_char = 8'h65; // e
                        else if (position == 2)
                            text_char = 8'h6C; // l
                        else if (position == 3)
                            text_char = 8'h6C; // l
                        else if (position == 4)
                            text_char = 8'h20;
                        else if ((position >= 5) &&
                                 (position < 5 + stock_name_length(stock)))
                            text_char = stock_name_char(stock, position - 5);
                        else if (position == 5 + stock_name_length(stock))
                            text_char = 8'h20;
                        else begin
                            case (position - (6 + stock_name_length(stock)))
                                0: text_char = 8'h73; // s
                                1: text_char = 8'h74; // t
                                2: text_char = 8'h6F; // o
                                3: text_char = 8'h63; // c
                                4: text_char = 8'h6B; // k
                                default: text_char = 8'h20;
                            endcase
                        end
                    end else begin
                        case (position)
                            0: text_char = 8'h73; 1: text_char = 8'h65;
                            2: text_char = 8'h6C; 3: text_char = 8'h6C;
                            4: text_char = 8'h20; 5: text_char = 8'h73;
                            6: text_char = 8'h63; 7: text_char = 8'h72;
                            8: text_char = 8'h65; 9: text_char = 8'h65;
                            10: text_char = 8'h6E;
                            default: text_char = 8'h20;
                        endcase
                    end
                end
                QUANTITY: begin
                    if (line == 0) begin
                        if (position == 0)
                            text_char = 8'h71; // q
                        else if (position == 1)
                            text_char = 8'h74; // t
                        else if (position == 2)
                            text_char = 8'h79; // y
                        else if (position == 3)
                            text_char = 8'h20;
                        else
                            text_char = stock_name_char(stock, position - 4);
                    end else begin
                        case (position)
                            0: text_char = 8'h71; 1: text_char = 8'h75;
                            2: text_char = 8'h61; 3: text_char = 8'h6E;
                            4: text_char = 8'h74; 5: text_char = 8'h69;
                            6: text_char = 8'h74; 7: text_char = 8'h79;
                            default: text_char = 8'h20;
                        endcase
                    end
                end
                ORDER_REVIEW: begin
                    if (line == 0) begin
                        if (position < stock_name_length(stock))
                            text_char = stock_name_char(stock, position);
                        else if (position == stock_name_length(stock))
                            text_char = 8'h20;
                        else if (position == stock_name_length(stock) + 1)
                            text_char = 8'h71; // q
                        else if (position == stock_name_length(stock) + 2)
                            text_char = 8'h74; // t
                        else if (position == stock_name_length(stock) + 3)
                            text_char = 8'h79; // y
                        else if (position == stock_name_length(stock) + 4)
                            text_char = 8'h20;
                        else if (position < stock_name_length(stock) + 9)
                            text_char = 8'h30 + quantity_digit(
                                value, position - stock_name_length(stock) - 5);
                        else
                            text_char = 8'h20;
                    end else begin
                        case (position)
                            0: text_char = 8'h63; 1: text_char = 8'h6F;
                            2: text_char = 8'h6E; 3: text_char = 8'h66;
                            4: text_char = 8'h69; 5: text_char = 8'h72;
                            6: text_char = 8'h6D; 7: text_char = 8'h61;
                            8: text_char = 8'h74; 9: text_char = 8'h69;
                            10: text_char = 8'h6F; 11: text_char = 8'h6E;
                            default: text_char = 8'h20;
                        endcase
                    end
                end
                ORDER_RESULT: begin
                    if (line == 0) begin
                        case (position)
                            0: text_char = 8'h6F; 1: text_char = 8'h72;
                            2: text_char = 8'h64; 3: text_char = 8'h65;
                            4: text_char = 8'h72; 5: text_char = 8'h20;
                            6: text_char = 8'h72; 7: text_char = 8'h65;
                            8: text_char = 8'h73; 9: text_char = 8'h75;
                            10: text_char = 8'h6C; 11: text_char = 8'h74;
                            default: text_char = 8'h20;
                        endcase
                    end else begin
                        case (position)
                            0: text_char = 8'h70; 1: text_char = 8'h72;
                            2: text_char = 8'h6F; 3: text_char = 8'h63;
                            4: text_char = 8'h65; 5: text_char = 8'h73;
                            6: text_char = 8'h73; 7: text_char = 8'h69;
                            8: text_char = 8'h6E; 9: text_char = 8'h67;
                            default: text_char = 8'h20;
                        endcase
                    end
                end
                TRADE_RESULT: begin
                    if (line == 0) begin
                        case (position)
                            0: text_char = 8'h74; 1: text_char = 8'h72;
                            2: text_char = 8'h61; 3: text_char = 8'h64;
                            4: text_char = 8'h65; 5: text_char = 8'h20;
                            6: text_char = 8'h72; 7: text_char = 8'h65;
                            8: text_char = 8'h73; 9: text_char = 8'h75;
                            10: text_char = 8'h6C; 11: text_char = 8'h74;
                            default: text_char = 8'h20;
                        endcase
                    end else begin
                        case (position)
                            0: text_char = 8'h73; 1: text_char = 8'h75;
                            2: text_char = 8'h63; 3: text_char = 8'h63;
                            4: text_char = 8'h65; 5: text_char = 8'h73;
                            6: text_char = 8'h73;
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

        // Two-line screens use rows 14..20 and 24..30. Single-line screens
        // use rows 14..20 so the screen description stays at the top.
        if (text_length(screen_state, selected_stock, quantity, 1) != 0) begin
            if ((pixel_y >= 14) && (pixel_y < 21)) begin
                line_select = 0;
                line_y = 14;
                line_active = 1;
            end else if ((pixel_y >= 24) && (pixel_y < 31)) begin
                line_select = 1;
                line_y = 24;
                line_active = 1;
            end
        end else if ((pixel_y >= 14) && (pixel_y < 21)) begin
            line_select = 0;
            line_y = 14;
            line_active = 1;
        end

        if (line_active) begin
            char_position = pixel_x / 6;
            glyph_x = pixel_x % 6;
            glyph_y = pixel_y - line_y;
            line_length = text_length(screen_state, selected_stock,
                                      quantity, line_select);
            char_code = text_char(screen_state, selected_stock, quantity,
                                  line_select, char_position);
        end

        text_pixel = glyph_pixel &&
                     (char_position < line_length) &&
                     (glyph_x < 5) &&
                     (glyph_y < 7);
    end

endmodule
