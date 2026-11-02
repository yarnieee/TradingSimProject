`timescale 1ns / 1ps
`include "trading_defs.vh"

// Right OLED (JB): every game screen.
//
// Layers, front to back (each owns its own area, so nothing overlaps):
//   menu_button_text  labels inside the tab bar, action buttons and OK box
//   text_layer        all other text, on a 16-column grid (see text_layer.v)
//   menu_buttons      tab bar, stock list, action buttons, OK box
//   chart_renderer    30-day chart of the selected stock (specific-stock screen)
// The title screen is drawn by title_art_renderer in D_display_top.
module OLED_Renderer (
    input  [12:0] pixel_index,
    input  [3:0]  screen_state,
    input  [2:0]  selected_stock,
    input  [3:0]  menu_selection,
    input  [1:0]  quantity_cursor,
    input         trade_side,
    input         trade_result_success,
    input  [2:0]  trade_result_code,
    input  [479:0] stock_samples,          // selected stock's 30-day history
    input  [`DN_N*32-1:0] numbers_bcd,     // from display_numbers
    input  [`DN_N-1:0]    numbers_neg,
    input  [3:0]  stock_up,                // stock k above its price 30 days ago
    output reg [15:0] pixel_data
);
    wire        text_active;
    wire [15:0] text_color;
    wire        menu_text_pixel;
    wire        menu_pixel_active;
    wire [15:0] menu_pixel_color;
    wire        chart_pixel_active;
    wire [15:0] chart_pixel_color;
    wire [6:0]  pixel_x = pixel_index % 96;
    wire [5:0]  pixel_y = pixel_index / 96;

    text_layer text_layer_inst (
        .pixel_index(pixel_index),
        .screen_state(screen_state),
        .selected_stock(selected_stock),
        .quantity_cursor(quantity_cursor),
        .trade_side(trade_side),
        .trade_result_success(trade_result_success),
        .trade_result_code(trade_result_code),
        .bcd(numbers_bcd),
        .neg(numbers_neg),
        .up(stock_up),
        .pixel_active(text_active),
        .pixel_color(text_color)
    );

    chart_renderer chart_renderer_inst (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .chart_mode((screen_state == `UI_SPECIFIC) ? 2'b01 : 2'b00),
        .stock_samples(stock_samples),
        .portfolio_samples(960'd0),
        .live_value(32'd0),
        .pixel_active(chart_pixel_active),
        .pixel_color(chart_pixel_color)
    );

    menu_button_text menu_button_text_inst (
        .pixel_index(pixel_index),
        .screen_state(screen_state),
        .text_pixel(menu_text_pixel)
    );

    menu_buttons menu_buttons_inst (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .screen_state(screen_state),
        .menu_selection(menu_selection),
        .pixel_active(menu_pixel_active),
        .pixel_color(menu_pixel_color)
    );

    always @(*) begin
        if (menu_text_pixel)
            pixel_data = 16'hFFFF;
        else if (text_active)
            pixel_data = text_color;
        else if (menu_pixel_active)
            pixel_data = menu_pixel_color;
        else if (chart_pixel_active)
            pixel_data = chart_pixel_color;
        else
            pixel_data = 16'h0000;
    end
endmodule

// Visual menu buttons shared by both OLEDs.
module menu_buttons (
    input  [6:0]  pixel_x,
    input  [5:0]  pixel_y,
    input  [3:0]  screen_state,
    input  [3:0]  menu_selection,
    output reg    pixel_active,
    output reg [15:0] pixel_color
);

    localparam TITLE     = `UI_TITLE;
    localparam PORTFOLIO = `UI_PORTFOLIO;
    localparam STOCKS    = `UI_STOCKS;
    localparam SPECIFIC  = `UI_SPECIFIC;
    localparam BUY_STOCK = `UI_BUY_STOCK;
    localparam SELL_STOCK= `UI_SELL_STOCK;
    localparam ORDER_REVIEW = `UI_ORDER_REVIEW;
    localparam ORDER_RESULT = `UI_ORDER_RESULT;
    localparam TRADE_RESULT = `UI_TRADE_RESULT;

    localparam NAV_PORTFOLIO = 4'd0;
    localparam NAV_STOCKS    = 4'd1;
    localparam STOCK_AMD     = 4'd2;
    localparam STOCK_MCD     = 4'd3;
    localparam STOCK_NVDA    = 4'd4;
    localparam STOCK_GME     = 4'd5;
    localparam ACTION_BUY    = 4'd6;
    localparam ACTION_SELL   = 4'd7;
    localparam ACTION_BACK   = 4'd8;
    localparam TITLE_OK      = 4'd9;
    localparam ACTION_CANCEL = 4'd10;
    localparam ACTION_QTY    = 4'd11;
    localparam ACTION_CONFIRM= 4'd12;
    localparam NO_BUTTON     = 4'hF;

    reg [3:0] button_kind;
    reg button_selected;
    reg button_border;

    always @(*) begin
        button_kind = NO_BUTTON;
        button_selected = 1'b0;

        // The top navigation row is shared by the portfolio, stocks, and
        // specific-stock screens.
        if ((screen_state == PORTFOLIO) ||
            (screen_state == STOCKS) || (screen_state == SPECIFIC)) begin
            if ((pixel_x >= 7'd2) && (pixel_x <= 7'd55) &&
                (pixel_y >= 6'd1) && (pixel_y <= 6'd10)) begin
                button_kind = NAV_PORTFOLIO;
                if (screen_state == PORTFOLIO)
                    button_selected = (menu_selection == NAV_PORTFOLIO);
                else if (screen_state == STOCKS)
                    button_selected = (menu_selection == NAV_PORTFOLIO);
                else
                    button_selected = (menu_selection == 4'd3);
            end else if ((pixel_x >= 7'd58) && (pixel_x <= 7'd93) &&
                         (pixel_y >= 6'd1) && (pixel_y <= 6'd10)) begin
                button_kind = NAV_STOCKS;
                if (screen_state == PORTFOLIO)
                    button_selected = (menu_selection == NAV_STOCKS);
                else if (screen_state == STOCKS)
                    button_selected = (menu_selection == NAV_STOCKS);
                else
                    button_selected = (menu_selection == 4'd4);
            end
        end

        // Title, order-review, and trade-result screens have an OK action.
        if ((screen_state == TITLE) || (screen_state == ORDER_REVIEW) ||
            (screen_state == TRADE_RESULT)) begin
            if ((pixel_x >= 7'd38) && (pixel_x <= 7'd57) &&
                (pixel_y >= 6'd44) && (pixel_y <= 6'd56)) begin
                button_kind = TITLE_OK;
                button_selected = 1'b1;
            end
        end

        // Stock list: one button per stock at x=2..33, y=12+9k..20+9k. The
        // ticker inside and the live price beside it come from text_layer.
        if (screen_state == STOCKS) begin
            if ((pixel_x >= 7'd2) && (pixel_x <= 7'd33) &&
                (pixel_y >= 6'd12) && (pixel_y <= 6'd20)) begin
                button_kind = STOCK_AMD;
                button_selected = (menu_selection == STOCK_AMD);
            end else if ((pixel_x >= 7'd2) && (pixel_x <= 7'd33) &&
                         (pixel_y >= 6'd21) && (pixel_y <= 6'd29)) begin
                button_kind = STOCK_MCD;
                button_selected = (menu_selection == STOCK_MCD);
            end else if ((pixel_x >= 7'd2) && (pixel_x <= 7'd33) &&
                         (pixel_y >= 6'd30) && (pixel_y <= 6'd38)) begin
                button_kind = STOCK_NVDA;
                button_selected = (menu_selection == STOCK_NVDA);
            end else if ((pixel_x >= 7'd2) && (pixel_x <= 7'd33) &&
                         (pixel_y >= 6'd39) && (pixel_y <= 6'd47)) begin
                button_kind = STOCK_GME;
                button_selected = (menu_selection == STOCK_GME);
            end
        end

        if (screen_state == SPECIFIC) begin
            if ((pixel_x >= 7'd4) && (pixel_x <= 7'd31) &&
                (pixel_y >= 6'd40) && (pixel_y <= 6'd50)) begin
                button_kind = ACTION_BUY;
                button_selected = (menu_selection == 4'd0);
            end else if ((pixel_x >= 7'd34) && (pixel_x <= 7'd61) &&
                         (pixel_y >= 6'd40) && (pixel_y <= 6'd50)) begin
                button_kind = ACTION_SELL;
                button_selected = (menu_selection == 4'd1);
            end else if ((pixel_x >= 7'd64) && (pixel_x <= 7'd91) &&
                         (pixel_y >= 6'd40) && (pixel_y <= 6'd50)) begin
                button_kind = ACTION_BACK;
                button_selected = (menu_selection == 4'd2);
            end
        end

        if ((screen_state == BUY_STOCK) || (screen_state == SELL_STOCK)) begin
            if ((pixel_x >= 7'd1) && (pixel_x <= 7'd31) &&
                (pixel_y >= 6'd40) && (pixel_y <= 6'd50)) begin
                button_kind = ACTION_CANCEL;
                button_selected = (menu_selection == 4'd0);
            end else if ((pixel_x >= 7'd34) && (pixel_x <= 7'd53) &&
                         (pixel_y >= 6'd40) && (pixel_y <= 6'd50)) begin
                button_kind = ACTION_QTY;
                button_selected = (menu_selection == 4'd1);
            end else if ((pixel_x >= 7'd56) && (pixel_x <= 7'd94) &&
                         (pixel_y >= 6'd40) && (pixel_y <= 6'd50)) begin
                button_kind = ACTION_CONFIRM;
                button_selected = (menu_selection == 4'd2);
            end
        end

        // A one-pixel border surrounds each button. Selected buttons use a
        // blue fill and yellow border; unselected buttons are black with a
        // white border.
        if (button_kind != NO_BUTTON) begin
            case (button_kind)
                NAV_PORTFOLIO: begin
                    button_border = (pixel_x == 7'd2) || (pixel_x == 7'd55) ||
                                    (pixel_y == 6'd1) || (pixel_y == 6'd10);
                end
                NAV_STOCKS: begin
                    button_border = (pixel_x == 7'd58) || (pixel_x == 7'd93) ||
                                    (pixel_y == 6'd1) || (pixel_y == 6'd10);
                end
                STOCK_AMD: begin
                    button_border = (pixel_x == 7'd2) || (pixel_x == 7'd33) ||
                                    (pixel_y == 6'd12) || (pixel_y == 6'd20);
                end
                STOCK_MCD: begin
                    button_border = (pixel_x == 7'd2) || (pixel_x == 7'd33) ||
                                    (pixel_y == 6'd21) || (pixel_y == 6'd29);
                end
                STOCK_NVDA: begin
                    button_border = (pixel_x == 7'd2) || (pixel_x == 7'd33) ||
                                    (pixel_y == 6'd30) || (pixel_y == 6'd38);
                end
                STOCK_GME: begin
                    button_border = (pixel_x == 7'd2) || (pixel_x == 7'd33) ||
                                    (pixel_y == 6'd39) || (pixel_y == 6'd47);
                end
                ACTION_BUY: begin
                    button_border = (pixel_x == 7'd4) || (pixel_x == 7'd31) ||
                                    (pixel_y == 6'd40) || (pixel_y == 6'd50);
                end
                TITLE_OK: begin
                    button_border = (pixel_x == 7'd38) || (pixel_x == 7'd57) ||
                                    (pixel_y == 6'd44) || (pixel_y == 6'd56);
                end
                ACTION_SELL: begin
                    button_border = (pixel_x == 7'd34) || (pixel_x == 7'd61) ||
                                    (pixel_y == 6'd40) || (pixel_y == 6'd50);
                end
                ACTION_BACK: begin
                    button_border = (pixel_x == 7'd64) || (pixel_x == 7'd91) ||
                                    (pixel_y == 6'd40) || (pixel_y == 6'd50);
                end
                ACTION_CANCEL: begin
                    button_border = (pixel_x == 7'd1) || (pixel_x == 7'd31) ||
                                    (pixel_y == 6'd40) || (pixel_y == 6'd50);
                end
                ACTION_QTY: begin
                    button_border = (pixel_x == 7'd34) || (pixel_x == 7'd53) ||
                                    (pixel_y == 6'd40) || (pixel_y == 6'd50);
                end
                ACTION_CONFIRM: begin
                    button_border = (pixel_x == 7'd56) || (pixel_x == 7'd94) ||
                                    (pixel_y == 6'd40) || (pixel_y == 6'd50);
                end
                default: button_border = 1'b0;
            endcase

            pixel_active = 1'b1;
            if (button_selected) begin
                if (button_border)
                    pixel_color = 16'hFFE0; // yellow border
                else
                    pixel_color = 16'hF81F; // neon magenta highlight
            end else begin
                if (button_border)
                    pixel_color = 16'h07FF; // neon cyan outline
                else
                    pixel_color = 16'h0000; // black interior
            end
        end else begin
            button_border = 1'b0;
            pixel_active = 1'b0;
            pixel_color = 16'h0000;
        end
    end

endmodule

// Current menu-label renderer. Coordinates match menu_buttons above.
module menu_button_text (
    input  [12:0] pixel_index,
    input  [3:0]  screen_state,
    output reg    text_pixel
);

    localparam TITLE     = `UI_TITLE;
    localparam PORTFOLIO = `UI_PORTFOLIO;
    localparam STOCKS    = `UI_STOCKS;
    localparam SPECIFIC  = `UI_SPECIFIC;
    localparam BUY_STOCK = `UI_BUY_STOCK;
    localparam SELL_STOCK= `UI_SELL_STOCK;

    localparam NAV_PORTFOLIO = 4'd0;
    localparam NAV_STOCKS    = 4'd1;
    localparam STOCK_AMD     = 4'd2;
    localparam STOCK_MCD     = 4'd3;
    localparam STOCK_NVDA    = 4'd4;
    localparam STOCK_GME     = 4'd5;
    localparam ACTION_BUY    = 4'd6;
    localparam ACTION_SELL   = 4'd7;
    localparam ACTION_BACK   = 4'd8;
    localparam TITLE_OK      = 4'd9;
    localparam ACTION_CANCEL = 4'd10;
    localparam ACTION_QTY    = 4'd11;
    localparam ACTION_CONFIRM= 4'd12;
    localparam ORDER_REVIEW  = `UI_ORDER_REVIEW;
    localparam ORDER_RESULT  = `UI_ORDER_RESULT;
    localparam TRADE_RESULT  = `UI_TRADE_RESULT;
    localparam NO_LABEL      = 4'hF;

    wire [6:0] pixel_x = pixel_index % 96;
    wire [5:0] pixel_y = pixel_index / 96;

    reg [7:0] char_code;
    reg [3:0] char_position;
    reg [3:0] label_kind;
    reg [6:0] text_start_x;
    reg [5:0] text_start_y;
    reg [3:0] text_length;
    reg [2:0] text_cell_width;
    reg       label_active;
    reg [2:0] glyph_x;
    reg [2:0] glyph_y;
    wire      glyph_pixel;

    font_renderer font_renderer_inst (
        .char_code(char_code),
        .glyph_x(glyph_x),
        .glyph_y(glyph_y),
        .pixel_on(glyph_pixel)
    );

    function [7:0] label_char;
        input [3:0] kind;
        input [3:0] position;
        begin
            label_char = 8'h20;
            case (kind)
                NAV_PORTFOLIO: begin
                    case (position)
                        0: label_char = 8'h50; // P
                        1: label_char = 8'h6F; // o
                        2: label_char = 8'h72; // r
                        3: label_char = 8'h74; // t
                        4: label_char = 8'h66; // f
                        5: label_char = 8'h6F; // o
                        6: label_char = 8'h6C; // l
                        7: label_char = 8'h69; // i
                        8: label_char = 8'h6F; // o
                        default: label_char = 8'h20;
                    endcase
                end
                NAV_STOCKS: begin
                    case (position)
                        0: label_char = 8'h53; // S
                        1: label_char = 8'h74; // t
                        2: label_char = 8'h6F; // o
                        3: label_char = 8'h63; // c
                        4: label_char = 8'h6B; // k
                        5: label_char = 8'h73; // s
                        default: label_char = 8'h20;
                    endcase
                end
                STOCK_AMD: begin
                    case (position)
                        0: label_char = 8'h41; // A
                        1: label_char = 8'h4D; // M
                        2: label_char = 8'h44; // D
                        default: label_char = 8'h20;
                    endcase
                end
                STOCK_NVDA: begin
                    case (position)
                        0: label_char = 8'h4E; // N
                        1: label_char = 8'h56; // V
                        2: label_char = 8'h44; // D
                        3: label_char = 8'h41; // A
                        default: label_char = 8'h20;
                    endcase
                end
                STOCK_GME: begin
                    case (position)
                        0: label_char = 8'h47; // G
                        1: label_char = 8'h4D; // M
                        2: label_char = 8'h45; // E
                        default: label_char = 8'h20;
                    endcase
                end
                ACTION_BUY: begin
                    case (position)
                        0: label_char = 8'h42; // B
                        1: label_char = 8'h75; // u
                        2: label_char = 8'h79; // y
                        default: label_char = 8'h20;
                    endcase
                end
                TITLE_OK: begin
                    case (position)
                        0: label_char = 8'h4F; // O
                        1: label_char = 8'h4B; // K
                        default: label_char = 8'h20;
                    endcase
                end
                ACTION_SELL: begin
                    case (position)
                        0: label_char = 8'h53; // S
                        1: label_char = 8'h65; // e
                        2: label_char = 8'h6C; // l
                        3: label_char = 8'h6C; // l
                        default: label_char = 8'h20;
                    endcase
                end
                ACTION_BACK: begin
                    case (position)
                        0: label_char = 8'h42; // B
                        1: label_char = 8'h61; // a
                        2: label_char = 8'h63; // c
                        3: label_char = 8'h6B; // k
                        default: label_char = 8'h20;
                    endcase
                end
                ACTION_CANCEL: begin
                    case (position)
                        0: label_char = 8'h43; // C
                        1: label_char = 8'h61; // a
                        2: label_char = 8'h6E; // n
                        3: label_char = 8'h63; // c
                        4: label_char = 8'h65; // e
                        5: label_char = 8'h6C; // l
                        default: label_char = 8'h20;
                    endcase
                end
                ACTION_QTY: begin
                    case (position)
                        0: label_char = 8'h51; // Q
                        1: label_char = 8'h74; // t
                        2: label_char = 8'h79; // y
                        default: label_char = 8'h20;
                    endcase
                end
                ACTION_CONFIRM: begin
                    case (position)
                        0: label_char = 8'h43; // C
                        1: label_char = 8'h6F; // o
                        2: label_char = 8'h6E; // n
                        3: label_char = 8'h66; // f
                        4: label_char = 8'h69; // i
                        5: label_char = 8'h72; // r
                        6: label_char = 8'h6D; // m
                        default: label_char = 8'h20;
                    endcase
                end
                default: label_char = 8'h20;
            endcase
        end
    endfunction

    always @(*) begin
        char_code = 8'h20;
        char_position = 0;
        label_kind = NO_LABEL;
        text_start_x = 0;
        text_start_y = 0;
        text_length = 0;
        text_cell_width = 6;
        label_active = 1'b0;
        glyph_x = 0;
        glyph_y = 0;

        if ((screen_state == PORTFOLIO) ||
            (screen_state == STOCKS) || (screen_state == SPECIFIC)) begin
            if ((pixel_x >= 7'd2) && (pixel_x < 7'd56) &&
                (pixel_y >= 6'd2) && (pixel_y < 6'd9)) begin
                label_kind = NAV_PORTFOLIO;
                text_start_x = 7'd2;
                text_start_y = 6'd2;
                text_length = 9;
                label_active = 1'b1;
            end else if ((pixel_x >= 7'd58) && (pixel_x < 7'd94) &&
                         (pixel_y >= 6'd2) && (pixel_y < 6'd9)) begin
                label_kind = NAV_STOCKS;
                text_start_x = 7'd58;
                text_start_y = 6'd2;
                text_length = 6;
                label_active = 1'b1;
            end
        end

        if ((screen_state == TITLE) || (screen_state == ORDER_REVIEW) ||
            (screen_state == TRADE_RESULT)) begin
            if ((pixel_x >= 7'd43) && (pixel_x < 7'd55) &&
                (pixel_y >= 6'd47) && (pixel_y < 6'd54)) begin
                label_kind = TITLE_OK;
                text_start_x = 7'd43;
                text_start_y = 6'd47;
                text_length = 2;
                label_active = 1'b1;
            end
        end else if (screen_state == SPECIFIC) begin
            if ((pixel_x >= 7'd9) && (pixel_x < 7'd27) &&
                (pixel_y >= 6'd42) && (pixel_y < 6'd49)) begin
                label_kind = ACTION_BUY;
                text_start_x = 7'd9;
                text_start_y = 6'd42;
                text_length = 3;
                label_active = 1'b1;
            end else if ((pixel_x >= 7'd36) && (pixel_x < 7'd60) &&
                         (pixel_y >= 6'd42) && (pixel_y < 6'd49)) begin
                label_kind = ACTION_SELL;
                text_start_x = 7'd36;
                text_start_y = 6'd42;
                text_length = 4;
                label_active = 1'b1;
            end else if ((pixel_x >= 7'd66) && (pixel_x < 7'd90) &&
                         (pixel_y >= 6'd42) && (pixel_y < 6'd49)) begin
                label_kind = ACTION_BACK;
                text_start_x = 7'd66;
                text_start_y = 6'd42;
                text_length = 4;
                label_active = 1'b1;
            end
        end else if ((screen_state == BUY_STOCK) ||
                     (screen_state == SELL_STOCK)) begin
            if ((pixel_x >= 7'd2) && (pixel_x < 7'd32) &&
                (pixel_y >= 6'd42) && (pixel_y < 6'd49)) begin
                label_kind = ACTION_CANCEL;
                text_start_x = 7'd2;
                text_start_y = 6'd42;
                text_length = 6;
                text_cell_width = 5;
                label_active = 1'b1;
            end else if ((pixel_x >= 7'd36) && (pixel_x < 7'd51) &&
                         (pixel_y >= 6'd42) && (pixel_y < 6'd49)) begin
                label_kind = ACTION_QTY;
                text_start_x = 7'd36;
                text_start_y = 6'd42;
                text_length = 3;
                text_cell_width = 5;
                label_active = 1'b1;
            end else if ((pixel_x >= 7'd58) && (pixel_x < 7'd93) &&
                         (pixel_y >= 6'd42) && (pixel_y < 6'd49)) begin
                label_kind = ACTION_CONFIRM;
                text_start_x = 7'd58;
                text_start_y = 6'd42;
                text_length = 7;
                text_cell_width = 5;
                label_active = 1'b1;
            end
        end

        if (label_active) begin
            char_position = (pixel_x - text_start_x) / text_cell_width;
            glyph_x = (pixel_x - text_start_x) % text_cell_width;
            glyph_y = pixel_y - text_start_y;
            char_code = label_char(label_kind, char_position);
        end

        text_pixel = label_active && (char_position < text_length) &&
                     (glyph_x < 5) && (glyph_y < 7) && glyph_pixel;
    end

endmodule
