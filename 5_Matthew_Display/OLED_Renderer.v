`timescale 1ns / 1ps

// Shared OLED renderer for all game states.
module OLED_Renderer (
    input  [12:0] pixel_index,
    input  [3:0]  screen_state,
    input  [2:0]  selected_stock,
    input  [13:0] quantity,
    input  [3:0]  menu_selection,
    input  [479:0] stock_samples,
    input  [959:0] portfolio_samples,
    input  [31:0] portfolio_cash,
    input  [9:0]  portfolio_pos0,
    input  [9:0]  portfolio_pos1,
    input  [31:0] portfolio_value,
    input  [15:0] selected_price,
    output reg [15:0] pixel_data
);

    wire text_pixel;
    wire info_pixel;
    wire menu_text_pixel;
    wire menu_pixel_active;
    wire [15:0] menu_pixel_color;
    wire chart_pixel_active;
    wire [15:0] chart_pixel_color;
    wire [1:0] chart_mode = (screen_state == 4'd3) ? 2'b01 :
                             (screen_state == 4'd1) ? 2'b10 : 2'b00;

    text_layer text_layer_inst (
        .pixel_index(pixel_index),
        .screen_state(screen_state),
        .selected_stock(selected_stock),
        .quantity(quantity),
        .text_pixel(text_pixel)
    );

    portfolio_info_layer portfolio_info_layer_inst (
        .pixel_index(pixel_index),
        .screen_state(screen_state),
        .cash(portfolio_cash),
        .pos0(portfolio_pos0),
        .pos1(portfolio_pos1),
        .portfolio_value(portfolio_value),
        .selected_price(selected_price),
        .text_pixel(info_pixel)
    );

    chart_renderer chart_renderer_inst (
        .pixel_x(pixel_index % 96),
        .pixel_y(pixel_index / 96),
        .chart_mode(chart_mode),
        .stock_samples(stock_samples),
        .portfolio_samples(portfolio_samples),
        .pixel_active(chart_pixel_active),
        .pixel_color(chart_pixel_color)
    );

    menu_button_text menu_button_text_inst (
        .pixel_index(pixel_index),
        .screen_state(screen_state),
        .text_pixel(menu_text_pixel)
    );

    menu_buttons menu_buttons_inst (
        .pixel_x(pixel_index % 96),
        .pixel_y(pixel_index / 96),
        .screen_state(screen_state),
        .menu_selection(menu_selection),
        .pixel_active(menu_pixel_active),
        .pixel_color(menu_pixel_color)
    );

    always @(*) begin
        if (menu_text_pixel)
            pixel_data = 16'hFFFF;
        else if (info_pixel)
            pixel_data = 16'hFFE0;
        else if (menu_pixel_active)
            pixel_data = menu_pixel_color;
        else if (chart_pixel_active)
            pixel_data = chart_pixel_color;
        else if (text_pixel)
            pixel_data = 16'h07FF;
        else
            pixel_data = 16'h0000;
    end

endmodule
// Renderer for the second OLED connected to JA. The JA OLED is mounted
// upside down, so its incoming pixel coordinates are rotated 180 degrees
// before the shared text layer is evaluated.
//
// Directional button indicators are drawn only while the debounced button
// is held:
//   btnL = yellow left strip
//   btnR = red right strip
//   btnU = green top strip
//   btnD = blue bottom strip
//   btnC = white confirmation marker
// btnC remains a confirmation input only; it does not change the FSM here.
module OLED_Button_Renderer (
    input  [12:0] pixel_index,
    input  [3:0]  screen_state,
    input  [2:0]  selected_stock,
    input  [13:0] quantity,
    input  [3:0]  menu_selection,
    input  [479:0] stock_samples,
    input  [959:0] portfolio_samples,
    input  [31:0] portfolio_cash,
    input  [9:0]  portfolio_pos0,
    input  [9:0]  portfolio_pos1,
    input  [31:0] portfolio_value,
    input  [15:0] selected_price,
    input         btnU,
    input         btnD,
    input         btnL,
    input         btnR,
    input         btnC,
    output reg [15:0] pixel_data
);

    wire [6:0] memory_x = pixel_index % 96;
    wire [5:0] memory_y = pixel_index / 96;
    wire [6:0] display_x = 7'd95 - memory_x;
    wire [5:0] display_y = 6'd63 - memory_y;
    wire [12:0] flipped_pixel_index = (display_y * 13'd96) + display_x;
    wire text_pixel;
    wire info_pixel;
    wire menu_text_pixel;
    wire menu_pixel_active;
    wire [15:0] menu_pixel_color;
    wire chart_pixel_active;
    wire [15:0] chart_pixel_color;
    wire [1:0] chart_mode = (screen_state == 4'd3) ? 2'b01 :
                             (screen_state == 4'd1) ? 2'b10 : 2'b00;

    text_layer text_layer_inst (
        .pixel_index(flipped_pixel_index),
        .screen_state(screen_state),
        .selected_stock(selected_stock),
        .quantity(quantity),
        .text_pixel(text_pixel)
    );

    portfolio_info_layer portfolio_info_layer_inst (
        .pixel_index(flipped_pixel_index),
        .screen_state(screen_state),
        .cash(portfolio_cash),
        .pos0(portfolio_pos0),
        .pos1(portfolio_pos1),
        .portfolio_value(portfolio_value),
        .selected_price(selected_price),
        .text_pixel(info_pixel)
    );

    chart_renderer chart_renderer_inst (
        .pixel_x(display_x),
        .pixel_y(display_y),
        .chart_mode(chart_mode),
        .stock_samples(stock_samples),
        .portfolio_samples(portfolio_samples),
        .pixel_active(chart_pixel_active),
        .pixel_color(chart_pixel_color)
    );

    menu_button_text menu_button_text_inst (
        .pixel_index(flipped_pixel_index),
        .screen_state(screen_state),
        .text_pixel(menu_text_pixel)
    );

    menu_buttons menu_buttons_inst (
        .pixel_x(display_x),
        .pixel_y(display_y),
        .screen_state(screen_state),
        .menu_selection(menu_selection),
        .pixel_active(menu_pixel_active),
        .pixel_color(menu_pixel_color)
    );

    always @(*) begin
        // Menu buttons and their labels are drawn before the live button
        // indicators so the indicators remain visible while pressed.
        if (menu_text_pixel)
            pixel_data = 16'hFFFF;
        else if (info_pixel)
            pixel_data = 16'hFFE0;
        else if (menu_pixel_active)
            pixel_data = menu_pixel_color;
        else if (chart_pixel_active)
            pixel_data = chart_pixel_color;
        else if (text_pixel)
            pixel_data = 16'h07FF;
        else
            pixel_data = 16'h0000;

        // The physical screen coordinates are used after the 180-degree
        // transform, so the indicators stay on the expected sides.
        if (btnL && (display_x < 8)) begin
            pixel_data = 16'hFFE0; // yellow
        end else if (btnR && (display_x >= 88)) begin
            pixel_data = 16'hF800; // red
        end else if (btnU && (display_y < 8) &&
                     (display_x >= 8) && (display_x < 88)) begin
            pixel_data = 16'h07E0; // green
        end else if (btnD && (display_y >= 56) &&
                     (display_x >= 8) && (display_x < 88)) begin
            pixel_data = 16'h001F; // blue
        end else if (btnC && (display_x >= 44) && (display_x < 52) &&
                     (display_y >= 48) && (display_y < 56)) begin
            pixel_data = 16'hFFFF; // confirmation marker
        end else if (text_pixel) begin
            pixel_data = 16'hFFFF;
        end
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

    localparam TITLE     = 4'd0;
    localparam PORTFOLIO = 4'd1;
    localparam STOCKS    = 4'd2;
    localparam SPECIFIC  = 4'd3;
    localparam BUY_STOCK = 4'd4;
    localparam SELL_STOCK= 4'd5;
    localparam CONFIRM   = 4'd7;

    localparam NAV_PORTFOLIO = 4'd0;
    localparam NAV_STOCKS    = 4'd1;
    localparam STOCK_AMD     = 4'd2;
    localparam STOCK_MCD     = 4'd3;
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

        // Title and confirmation screens: the OK button is always selected.
        if ((screen_state == TITLE) || (screen_state == CONFIRM)) begin
            if ((pixel_x >= 7'd38) && (pixel_x <= 7'd57) &&
                (pixel_y >= 6'd44) && (pixel_y <= 6'd56)) begin
                button_kind = TITLE_OK;
                button_selected = 1'b1;
            end
        end

        if (screen_state == STOCKS) begin
            if ((pixel_x >= 7'd30) && (pixel_x <= 7'd65) &&
                (pixel_y >= 6'd24) && (pixel_y <= 6'd31)) begin
                button_kind = STOCK_AMD;
                button_selected = (menu_selection == STOCK_AMD);
            end else if ((pixel_x >= 7'd30) && (pixel_x <= 7'd65) &&
                         (pixel_y >= 6'd33) && (pixel_y <= 6'd40)) begin
                button_kind = STOCK_MCD;
                button_selected = (menu_selection == STOCK_MCD);
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
                    button_border = (pixel_x == 7'd30) || (pixel_x == 7'd65) ||
                                    (pixel_y == 6'd24) || (pixel_y == 6'd31);
                end
                STOCK_MCD: begin
                    button_border = (pixel_x == 7'd30) || (pixel_x == 7'd65) ||
                                    (pixel_y == 6'd33) || (pixel_y == 6'd40);
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

// Text labels for the visual menu buttons.
module menu_button_text_legacy (
    input  [12:0] pixel_index,
    input  [3:0]  screen_state,
    output reg    text_pixel
);

    localparam TITLE     = 4'd0;
    localparam PORTFOLIO = 4'd1;

    wire [6:0] pixel_x = pixel_index % 96;
    wire [5:0] pixel_y = pixel_index / 96;

    reg [7:0] char_code;
    reg [3:0] char_position;
    reg [6:0] text_start_x;
    reg [5:0] text_start_y;
    reg [3:0] text_length;
    reg       text_active;
    reg [2:0] glyph_x;
    reg [2:0] glyph_y;
    wire      glyph_pixel;

    font_renderer font_renderer_inst (
        .char_code(char_code),
        .glyph_x(glyph_x),
        .glyph_y(glyph_y),
        .pixel_on(glyph_pixel)
    );

    function [7:0] button_char;
        input [3:0] state;
        input [1:0] button;
        input [3:0] position;
        begin
            button_char = 8'h20;
            case (state)
                TITLE: begin
                    if (button == 2'd0) begin
                        case (position)
                            0: button_char = 8'h4F; // O
                            1: button_char = 8'h4B; // K
                            default: button_char = 8'h20;
                        endcase
                    end
                end
                PORTFOLIO: begin
                    case (button)
                        2'd0: begin
                            case (position)
                                0: button_char = 8'h50; // P
                                1: button_char = 8'h6F; // o
                                2: button_char = 8'h72; // r
                                3: button_char = 8'h74; // t
                                4: button_char = 8'h66; // f
                                5: button_char = 8'h6F; // o
                                6: button_char = 8'h6C; // l
                                7: button_char = 8'h69; // i
                                8: button_char = 8'h6F; // o
                                default: button_char = 8'h20;
                            endcase
                        end
                        2'd1: begin
                            case (position)
                                0: button_char = 8'h53; // S
                                1: button_char = 8'h74; // t
                                2: button_char = 8'h6F; // o
                                3: button_char = 8'h63; // c
                                4: button_char = 8'h6B; // k
                                5: button_char = 8'h73; // s
                                default: button_char = 8'h20;
                            endcase
                        end
                        default: button_char = 8'h20;
                    endcase
                end
                default: button_char = 8'h20;
            endcase
        end
    endfunction

    always @(*) begin
        char_code = 8'h20;
        char_position = 0;
        text_start_x = 0;
        text_start_y = 0;
        text_length = 0;
        text_active = 1'b0;
        glyph_x = 0;
        glyph_y = 0;

        if (screen_state == TITLE) begin
            // OK label centered inside the title button.
            text_start_x = 7'd43;
            text_start_y = 6'd47;
            text_length = 2;
            if ((pixel_x >= text_start_x) &&
                (pixel_x < text_start_x + 12) &&
                (pixel_y >= text_start_y) &&
                (pixel_y < text_start_y + 7)) begin
                text_active = 1'b1;
            end
        end else if (screen_state == PORTFOLIO) begin
            if ((pixel_x >= 7'd21) && (pixel_x < 7'd75) &&
                (pixel_y >= 6'd42) && (pixel_y < 6'd49)) begin
                // Portfolio label: 9 characters x 6 pixels.
                text_start_x = 7'd21;
                text_start_y = 6'd42;
                text_length = 9;
                text_active = 1'b1;
            end else if ((pixel_x >= 7'd30) && (pixel_x < 7'd66) &&
                         (pixel_y >= 6'd54) && (pixel_y < 6'd61)) begin
                // Stocks label: 6 characters x 6 pixels.
                text_start_x = 7'd30;
                text_start_y = 6'd54;
                text_length = 6;
                text_active = 1'b1;
            end
        end

        if (text_active) begin
            char_position = (pixel_x - text_start_x) / 6;
            glyph_x = (pixel_x - text_start_x) % 6;
            glyph_y = pixel_y - text_start_y;
            char_code = button_char(screen_state,
                                    (screen_state == TITLE) ? 2'd0 :
                                    ((pixel_y < 6'd50) ? 2'd0 : 2'd1),
                                    char_position);
        end

        text_pixel = text_active && (char_position < text_length) &&
                     (glyph_x < 5) && (glyph_y < 7) && glyph_pixel;
    end

endmodule

// Current menu-label renderer. Coordinates match menu_buttons above.
module menu_button_text (
    input  [12:0] pixel_index,
    input  [3:0]  screen_state,
    output reg    text_pixel
);

    localparam TITLE     = 4'd0;
    localparam PORTFOLIO = 4'd1;
    localparam STOCKS    = 4'd2;
    localparam SPECIFIC  = 4'd3;
    localparam BUY_STOCK = 4'd4;
    localparam SELL_STOCK= 4'd5;

    localparam NAV_PORTFOLIO = 4'd0;
    localparam NAV_STOCKS    = 4'd1;
    localparam STOCK_AMD     = 4'd2;
    localparam STOCK_MCD     = 4'd3;
    localparam ACTION_BUY    = 4'd6;
    localparam ACTION_SELL   = 4'd7;
    localparam ACTION_BACK   = 4'd8;
    localparam TITLE_OK      = 4'd9;
    localparam ACTION_CANCEL = 4'd10;
    localparam ACTION_QTY    = 4'd11;
    localparam ACTION_CONFIRM= 4'd12;
    localparam CONFIRM       = 4'd7;
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
                STOCK_MCD: begin
                    case (position)
                        0: label_char = 8'h4D; // M
                        1: label_char = 8'h43; // C
                        2: label_char = 8'h44; // D
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

        if ((screen_state == TITLE) || (screen_state == CONFIRM)) begin
            if ((pixel_x >= 7'd43) && (pixel_x < 7'd55) &&
                (pixel_y >= 6'd47) && (pixel_y < 6'd54)) begin
                label_kind = TITLE_OK;
                text_start_x = 7'd43;
                text_start_y = 6'd47;
                text_length = 2;
                label_active = 1'b1;
            end
        end else if (screen_state == STOCKS) begin
            if ((pixel_x >= 7'd39) && (pixel_x < 7'd57) &&
                (pixel_y >= 6'd25) && (pixel_y < 6'd32)) begin
                label_kind = STOCK_AMD;
                text_start_x = 7'd39;
                text_start_y = 6'd25;
                text_length = 3;
                label_active = 1'b1;
            end else if ((pixel_x >= 7'd39) && (pixel_x < 7'd57) &&
                         (pixel_y >= 6'd34) && (pixel_y < 6'd41)) begin
                label_kind = STOCK_MCD;
                text_start_x = 7'd39;
                text_start_y = 6'd34;
                text_length = 3;
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
