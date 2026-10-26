`timescale 1ns / 1ps

// Four-stock portfolio table for the right JB OLED.
//
// The table uses the live ledger positions/cost bases and the live market
// prices. Value is position*price and PNL is value-cost_basis. Values are
// rendered as compact hexadecimal cents to keep the display combinational
// logic small enough for the Basys3 Artix-7 device.
module portfolio_table_layer (
    input  wire [12:0] pixel_index,
    input  wire [3:0]  screen_state,
    input  wire [3:0]  menu_selection,
    input  wire [9:0]  pos0,
    input  wire [9:0]  pos1,
    input  wire [9:0]  pos2,
    input  wire [9:0]  pos3,
    input  wire [15:0] price0,
    input  wire [15:0] price1,
    input  wire [15:0] price2,
    input  wire [15:0] price3,
    input  wire [31:0] cb0,
    input  wire [31:0] cb1,
    input  wire [31:0] cb2,
    input  wire [31:0] cb3,
    input  wire [31:0] cash,
    output reg         pixel_active,
    output reg  [15:0] pixel_color
);
    localparam [3:0] PORTFOLIO = 4'd1;
    localparam [3:0] STOCKS    = 4'd2;

    localparam [1:0] FIELD_NAME = 2'd0;
    localparam [1:0] FIELD_POS  = 2'd1;
    localparam [1:0] FIELD_VAL  = 2'd2;
    localparam [1:0] FIELD_PNL  = 2'd3;

    wire [6:0] pixel_x = pixel_index % 96;
    wire [5:0] pixel_y = pixel_index / 96;
    reg [7:0] char_code;
    reg [3:0] char_position;
    reg [1:0] field_kind;
    reg [1:0] row_index;
    reg [6:0] field_start_x;
    reg [5:0] line_y;
    reg [3:0] line_length;
    reg       text_active;
    reg [9:0] row_position;
    reg [15:0] row_price;
    reg [31:0] row_cost_basis;
    reg [31:0] row_value;
    reg [32:0] row_pnl_signed;
    reg [15:0] row_pnl_abs;
    reg        row_pnl_negative;
    reg        capital_row;
    reg        row_selected;
    reg [2:0] glyph_x;
    reg [2:0] glyph_y;
    wire glyph_pixel;

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

    function [7:0] stock_char;
        input [1:0] stock;
        input [1:0] position;
        begin
            stock_char = 8'h20;
            case (stock)
                2'd0: case (position)
                    0: stock_char = 8'h41; 1: stock_char = 8'h4d;
                    default: stock_char = 8'h44;
                endcase
                2'd1: case (position)
                    0: stock_char = 8'h41; 1: stock_char = 8'h56;
                    2: stock_char = 8'h47; default: stock_char = 8'h4f;
                endcase
                2'd2: case (position)
                    0: stock_char = 8'h4e; 1: stock_char = 8'h56;
                    2: stock_char = 8'h44; default: stock_char = 8'h41;
                endcase
                default: case (position)
                    0: stock_char = 8'h47; 1: stock_char = 8'h4d;
                    default: stock_char = 8'h45;
                endcase
            endcase
        end
    endfunction

    function [7:0] position_char;
        input [9:0] value;
        input [1:0] position;
        begin
            case (position)
                // Positions are compact hexadecimal nibbles. Avoiding
                // decimal dividers keeps the table small enough for the
                // Basys3 while still showing the full live position bus.
                2'd0: position_char = hex_char({2'b00, value[9:8]});
                2'd1: position_char = hex_char(value[7:4]);
                default: position_char = hex_char(value[3:0]);
            endcase
        end
    endfunction

    function [3:0] value_nibble;
        input [15:0] value;
        input [1:0] position;
        begin
            case (position)
                2'd0: value_nibble = value[15:12];
                2'd1: value_nibble = value[11:8];
                2'd2: value_nibble = value[7:4];
                default: value_nibble = value[3:0];
            endcase
        end
    endfunction

    always @(*) begin
        char_code = 8'h20;
        char_position = 4'd0;
        field_kind = FIELD_NAME;
        row_index = 2'd0;
        field_start_x = 7'd0;
        line_y = 6'd0;
        line_length = 4'd0;
        text_active = 1'b0;
        row_position = 10'd0;
        row_price = 16'd0;
        row_cost_basis = 32'd0;
        row_value = 32'd0;
        row_pnl_signed = 33'd0;
        row_pnl_abs = 16'd0;
        row_pnl_negative = 1'b0;
        capital_row = 1'b0;
        row_selected = 1'b0;
        glyph_x = 3'd0;
        glyph_y = 3'd0;
        pixel_active = 1'b0;
        pixel_color = 16'h0000;

        if ((screen_state == PORTFOLIO) || (screen_state == STOCKS)) begin
            // Thin table grid; text below has priority over these lines.
            if ((pixel_x == 7'd0) || (pixel_x == 7'd95) ||
                (pixel_x == 7'd24) || (pixel_x == 7'd42) ||
                (pixel_x == 7'd68) ||
                 (pixel_y == 6'd11) || (pixel_y == 6'd18) ||
                 (pixel_y == 6'd26) || (pixel_y == 6'd34) ||
                 (pixel_y == 6'd42) || (pixel_y == 6'd50) ||
                 (pixel_y == 6'd57)) begin
                pixel_active = 1'b1;
                pixel_color = 16'h4208;
            end

            if ((pixel_y >= 6'd12) && (pixel_y < 6'd18)) begin
                line_y = 6'd12;
                text_active = 1'b1;
                if (pixel_x < 7'd24) begin
                    field_kind = FIELD_NAME; field_start_x = 7'd2; line_length = 4'd4;
                end else if (pixel_x < 7'd42) begin
                    field_kind = FIELD_POS; field_start_x = 7'd27; line_length = 4'd3;
                end else if (pixel_x < 7'd68) begin
                    field_kind = FIELD_VAL; field_start_x = 7'd44; line_length = 4'd4;
                end else begin
                    field_kind = FIELD_PNL; field_start_x = 7'd70; line_length = 4'd3;
                end
            end else if ((pixel_y >= 6'd19) && (pixel_y < 6'd26)) begin
                row_index = 2'd0; line_y = 6'd19; text_active = 1'b1;
            end else if ((pixel_y >= 6'd27) && (pixel_y < 6'd34)) begin
                row_index = 2'd1; line_y = 6'd27; text_active = 1'b1;
            end else if ((pixel_y >= 6'd35) && (pixel_y < 6'd42)) begin
                row_index = 2'd2; line_y = 6'd35; text_active = 1'b1;
            end else if ((pixel_y >= 6'd43) && (pixel_y < 6'd50)) begin
                row_index = 2'd3; line_y = 6'd43; text_active = 1'b1;
            end else if ((pixel_y >= 6'd51) && (pixel_y < 6'd58)) begin
                capital_row = 1'b1; line_y = 6'd51; text_active = 1'b1;
            end

            // The same columns are used by the heading and all four rows.
            if (text_active) begin
                if (pixel_x < 7'd24) begin
                    field_kind = FIELD_NAME; field_start_x = 7'd2; line_length = 4'd4;
                end else if (pixel_x < 7'd42) begin
                    field_kind = FIELD_POS; field_start_x = 7'd27; line_length = 4'd3;
                end else if (pixel_x < 7'd68) begin
                    field_kind = FIELD_VAL; field_start_x = 7'd44; line_length = 4'd4;
                end else begin
                    field_kind = FIELD_PNL; field_start_x = 7'd70; line_length = 4'd5;
                end
                if ((pixel_y < 6'd18) && (field_kind == FIELD_PNL))
                    line_length = 4'd3;
                if (capital_row) begin
                    if (pixel_x < 7'd24) begin
                        field_kind = FIELD_NAME; field_start_x = 7'd2; line_length = 4'd4;
                    end else if (pixel_x < 7'd42) begin
                        field_kind = FIELD_POS; field_start_x = 7'd27; line_length = 4'd0;
                    end else if (capital_row ? (pixel_x < 7'd69) :
                                               (pixel_x < 7'd68)) begin
                        field_kind = FIELD_VAL; field_start_x = 7'd44; line_length = 4'd5;
                    end else begin
                        field_kind = FIELD_PNL; field_start_x = 7'd70; line_length = 4'd0;
                    end
                end
            end

            if ((pixel_y >= 6'd19) && (pixel_y < 6'd50)) begin
                case (row_index)
                    2'd0: begin row_position = pos0; row_price = price0; row_cost_basis = cb0; end
                    2'd1: begin row_position = pos1; row_price = price1; row_cost_basis = cb1; end
                    2'd2: begin row_position = pos2; row_price = price2; row_cost_basis = cb2; end
                    default: begin row_position = pos3; row_price = price3; row_cost_basis = cb3; end
                endcase
                // Only the row currently being scanned needs arithmetic.
                // Sharing this product cuts the table from four multipliers
                // and four subtractors to one of each.
                row_value = row_position * row_price;
                row_pnl_signed = $signed({1'b0, row_value}) -
                                 $signed({1'b0, row_cost_basis});
                row_pnl_abs = row_pnl_signed[32] ?
                              -row_pnl_signed[15:0] : row_pnl_signed[15:0];
                // For stock rows 0..3, menu selections 2..5 encode
                // row = menu_selection - 2. Express this as bit relations
                // instead of a per-pixel four-bit adder/comparator.
                if ((screen_state == STOCKS) && !menu_selection[3] &&
                    (menu_selection[1] == ~menu_selection[2]) &&
                    (row_index[1] == menu_selection[2]) &&
                    (row_index[0] == menu_selection[0]))
                    row_selected = 1'b1;
            end

            if (capital_row)
                row_value = cash;

            if (row_selected && (pixel_y >= line_y) &&
                (pixel_y < line_y + 6'd7)) begin
                pixel_active = 1'b1;
                pixel_color = 16'h001F;
            end

            if (text_active && (pixel_y >= line_y) &&
                (pixel_y < line_y + 6'd7)) begin
                if ((pixel_x >= field_start_x) &&
                    (pixel_x < field_start_x + line_length * 5)) begin
                    if      (pixel_x < field_start_x + 7'd5)  begin char_position = 4'd0; glyph_x = pixel_x - field_start_x; end
                    else if (pixel_x < field_start_x + 7'd10) begin char_position = 4'd1; glyph_x = pixel_x - field_start_x - 7'd5; end
                    else if (pixel_x < field_start_x + 7'd15) begin char_position = 4'd2; glyph_x = pixel_x - field_start_x - 7'd10; end
                    else if (pixel_x < field_start_x + 7'd20) begin char_position = 4'd3; glyph_x = pixel_x - field_start_x - 7'd15; end
                    else begin char_position = 4'd4; glyph_x = pixel_x - field_start_x - 7'd20; end
                    glyph_y = pixel_y - line_y;
                    row_pnl_negative = row_pnl_signed[32];

                    case (field_kind)
                        FIELD_NAME: char_code = (pixel_y < 6'd20) ?
                                                ((char_position == 0) ? 8'h4e :
                                                 (char_position == 1) ? 8'h41 :
                                                 (char_position == 2) ? 8'h4d : 8'h45) :
                                                (capital_row ?
                                                 ((char_position == 0) ? 8'h43 :
                                                  (char_position == 1) ? 8'h41 :
                                                  (char_position == 2) ? 8'h50 : 8'h20) :
                                                 stock_char(row_index, char_position));
                        FIELD_POS: char_code = (pixel_y < 6'd20) ?
                                               ((char_position == 0) ? 8'h50 :
                                                (char_position == 1) ? 8'h4f : 8'h53) :
                                               position_char(row_position, char_position);
                        FIELD_VAL: char_code = (pixel_y < 6'd18) ?
                                               ((char_position == 0) ? 8'h56 :
                                                (char_position == 1) ? 8'h41 :
                                                (char_position == 2) ? 8'h4c : 8'h20) :
                                              (capital_row ?
                                               ((char_position == 0) ? hex_char(cash[19:16]) :
                                                (char_position == 1) ? hex_char(cash[15:12]) :
                                                (char_position == 2) ? hex_char(cash[11:8]) :
                                                (char_position == 3) ? hex_char(cash[7:4]) :
                                                hex_char(cash[3:0])) :
                                               hex_char(value_nibble(row_value[15:0], char_position)));
                        default: char_code = (pixel_y < 6'd20) ?
                                             ((char_position == 0) ? 8'h50 :
                                              (char_position == 1) ? 8'h4e : 8'h4c) :
                                             ((char_position == 0) ?
                                              (row_pnl_negative ? 8'h2d : 8'h2b) :
                                              hex_char(value_nibble(row_pnl_abs, char_position - 1'b1)));
                    endcase

                    if (glyph_pixel) begin
                        pixel_active = 1'b1;
                        if ((field_kind == FIELD_PNL) && (pixel_y >= 6'd21))
                            pixel_color = row_pnl_negative ? 16'hF800 : 16'h07E0;
                        else
                            pixel_color = 16'hFFFF;
                    end
                end
            end
        end
    end
endmodule
