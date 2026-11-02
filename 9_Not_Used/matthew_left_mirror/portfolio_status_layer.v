`timescale 1ns / 1ps

// Portfolio overview for the upside-down JA OLED.
//
// The chart renderer supplies the live portfolio history below this layer.
// This layer supplies the compact status header and timeframe labels from
// the same live cash/value buses. Values are shown as hexadecimal cents so
// the display remains resource-friendly on the Artix-7 target.
module portfolio_status_layer (
    input  wire [12:0] pixel_index,
    input  wire [3:0]  screen_state,
    input  wire [31:0] cash,
    input  wire [31:0] portfolio_value,
    output reg         pixel_active,
    output reg  [15:0] pixel_color
);
    localparam [3:0] PORTFOLIO = 4'd1;

    wire [6:0] pixel_x = pixel_index % 96;
    wire [5:0] pixel_y = pixel_index / 96;

    reg [7:0] char_code;
    reg [4:0] char_position;
    reg [4:0] line_length;
    reg [5:0] line_y;
    reg [1:0] line_select;
    reg [6:0] line_start_x;
    reg [2:0] cell_width;
    reg       line_active;
    reg [2:0] glyph_x;
    reg [2:0] glyph_y;
    reg [31:0] pnl_magnitude;
    reg        pnl_negative;
    wire       glyph_pixel;

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
        char_code    = 8'h20;
        char_position = 5'd0;
        line_length  = 5'd0;
        line_y       = 6'd0;
        line_select  = 2'd0;
        line_start_x = 7'd2;
        cell_width   = 3'd6;
        line_active  = 1'b0;
        glyph_x      = 3'd0;
        glyph_y      = 3'd0;
        pnl_negative = 1'b0;
        pnl_magnitude = 32'd0;

        if (portfolio_value < cash) begin
            pnl_negative  = 1'b1;
            pnl_magnitude = cash - portfolio_value;
        end else begin
            pnl_magnitude = portfolio_value - cash;
        end

        if (screen_state == PORTFOLIO) begin
            if ((pixel_y >= 6'd12) && (pixel_y < 6'd19)) begin
                line_select = 2'd0;
                line_y = 6'd12;
                line_length = 5'd9; // portfolio
                line_active = 1'b1;
                line_start_x = 7'd2;
                cell_width = 3'd6;
            end else if ((pixel_y >= 6'd21) && (pixel_y < 6'd28)) begin
                line_select = 2'd1;
                line_y = 6'd21;
                line_length = 5'd15; // $hhhhhh +/-hhhhhh
                line_active = 1'b1;
                line_start_x = 7'd2;
                cell_width = 3'd5;
            end else if ((pixel_y >= 6'd54) && (pixel_y < 6'd61)) begin
                line_select = 2'd2;
                line_y = 6'd54;
                line_length = 5'd11; // 1M 6M 2y 5y
                line_active = 1'b1;
                line_start_x = 7'd18;
                cell_width = 3'd5;
            end
        end

        if (line_active && (pixel_x >= line_start_x)) begin
            if (cell_width == 3'd6) begin
                if      (pixel_x < line_start_x + 7'd6)  char_position = 5'd0;
                else if (pixel_x < line_start_x + 7'd12) char_position = 5'd1;
                else if (pixel_x < line_start_x + 7'd18) char_position = 5'd2;
                else if (pixel_x < line_start_x + 7'd24) char_position = 5'd3;
                else if (pixel_x < line_start_x + 7'd30) char_position = 5'd4;
                else if (pixel_x < line_start_x + 7'd36) char_position = 5'd5;
                else if (pixel_x < line_start_x + 7'd42) char_position = 5'd6;
                else if (pixel_x < line_start_x + 7'd48) char_position = 5'd7;
                else char_position = 5'd8;
            end else begin
                if      (pixel_x < line_start_x + 7'd5)  char_position = 5'd0;
                else if (pixel_x < line_start_x + 7'd10) char_position = 5'd1;
                else if (pixel_x < line_start_x + 7'd15) char_position = 5'd2;
                else if (pixel_x < line_start_x + 7'd20) char_position = 5'd3;
                else if (pixel_x < line_start_x + 7'd25) char_position = 5'd4;
                else if (pixel_x < line_start_x + 7'd30) char_position = 5'd5;
                else if (pixel_x < line_start_x + 7'd35) char_position = 5'd6;
                else if (pixel_x < line_start_x + 7'd40) char_position = 5'd7;
                else if (pixel_x < line_start_x + 7'd45) char_position = 5'd8;
                else if (pixel_x < line_start_x + 7'd50) char_position = 5'd9;
                else if (pixel_x < line_start_x + 7'd55) char_position = 5'd10;
                else if (pixel_x < line_start_x + 7'd60) char_position = 5'd11;
                else if (pixel_x < line_start_x + 7'd65) char_position = 5'd12;
                else if (pixel_x < line_start_x + 7'd70) char_position = 5'd13;
                else char_position = 5'd14;
            end

            glyph_x = pixel_x - line_start_x - (char_position * cell_width);
            glyph_y = pixel_y - line_y;

            case (line_select)
                2'd0: begin
                    case (char_position)
                        0: char_code = 8'h70; // p
                        1: char_code = 8'h6f; // o
                        2: char_code = 8'h72; // r
                        3: char_code = 8'h74; // t
                        4: char_code = 8'h66; // f
                        5: char_code = 8'h6f; // o
                        6: char_code = 8'h6c; // l
                        7: char_code = 8'h69; // i
                        default: char_code = 8'h6f; // o
                    endcase
                end
                2'd1: begin
                    case (char_position)
                        0: char_code = 8'h24; // $
                        1: char_code = hex_char(cash[23:20]);
                        2: char_code = hex_char(cash[19:16]);
                        3: char_code = hex_char(cash[15:12]);
                        4: char_code = hex_char(cash[11:8]);
                        5: char_code = hex_char(cash[7:4]);
                        6: char_code = hex_char(cash[3:0]);
                        7: char_code = 8'h20;
                        8: char_code = pnl_negative ? 8'h2d : 8'h2b;
                        9: char_code = hex_char(pnl_magnitude[23:20]);
                        10: char_code = hex_char(pnl_magnitude[19:16]);
                        11: char_code = hex_char(pnl_magnitude[15:12]);
                        12: char_code = hex_char(pnl_magnitude[11:8]);
                        13: char_code = hex_char(pnl_magnitude[7:4]);
                        default: char_code = hex_char(pnl_magnitude[3:0]);
                    endcase
                end
                default: begin
                    case (char_position)
                        0: char_code = 8'h31; // 1
                        1: char_code = 8'h4d; // M
                        2: char_code = 8'h20;
                        3: char_code = 8'h36; // 6
                        4: char_code = 8'h4d; // M
                        5: char_code = 8'h20;
                        6: char_code = 8'h32; // 2
                        7: char_code = 8'h79; // y
                        8: char_code = 8'h20;
                        9: char_code = 8'h35; // 5
                        default: char_code = 8'h79; // y
                    endcase
                end
            endcase
        end

        pixel_active = line_active && (char_position < line_length) &&
                       (glyph_x < 3'd5) && (glyph_y < 3'd7) && glyph_pixel;
        if (line_select == 2'd0)
            pixel_color = 16'hFFE0;
        else if ((line_select == 2'd1) && (char_position >= 5'd8))
            pixel_color = pnl_negative ? 16'hF800 : 16'h07E0;
        else
            pixel_color = 16'hFFFF;
    end
endmodule
