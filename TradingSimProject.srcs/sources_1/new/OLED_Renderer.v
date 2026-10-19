`timescale 1ns / 1ps

// Shared OLED renderer for all game states.
module OLED_Renderer (
    input  [12:0] pixel_index,
    input  [3:0]  screen_state,
    input  [1:0]  menu_selection,
    output reg [15:0] pixel_data
);

    wire text_pixel;
    wire menu_text_pixel;
    wire menu_pixel_active;
    wire [15:0] menu_pixel_color;

    text_layer text_layer_inst (
        .pixel_index(pixel_index),
        .screen_state(screen_state),
        .text_pixel(text_pixel)
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
        else if (menu_pixel_active)
            pixel_data = menu_pixel_color;
        else if (text_pixel)
            pixel_data = 16'hFFFF;
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
    input  [1:0]  menu_selection,
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
    wire menu_text_pixel;
    wire menu_pixel_active;
    wire [15:0] menu_pixel_color;

    text_layer text_layer_inst (
        .pixel_index(flipped_pixel_index),
        .screen_state(screen_state),
        .text_pixel(text_pixel)
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
        else if (menu_pixel_active)
            pixel_data = menu_pixel_color;
        else if (text_pixel)
            pixel_data = 16'hFFFF;
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
    input  [1:0]  menu_selection,
    output reg    pixel_active,
    output reg [15:0] pixel_color
);

    localparam TITLE     = 4'd0;
    localparam PORTFOLIO = 4'd1;

    reg button_active;
    reg button_selected;
    reg button_border;

    always @(*) begin
        button_active = 1'b0;
        button_selected = 1'b0;

        // Title screen: the OK button is always the selected option.
        if (screen_state == TITLE) begin
            if ((pixel_x >= 7'd38) && (pixel_x <= 7'd57) &&
                (pixel_y >= 6'd44) && (pixel_y <= 6'd56)) begin
                button_active = 1'b1;
                button_selected = 1'b1;
            end
        end

        // Portfolio screen: Portfolio is button 0, Stocks is button 1.
        if (screen_state == PORTFOLIO) begin
            if ((pixel_x >= 7'd16) && (pixel_x <= 7'd79) &&
                (pixel_y >= 6'd40) && (pixel_y <= 6'd50)) begin
                button_active = 1'b1;
                button_selected = (menu_selection == 2'd0);
            end else if ((pixel_x >= 7'd28) && (pixel_x <= 7'd67) &&
                         (pixel_y >= 6'd52) && (pixel_y <= 6'd62)) begin
                button_active = 1'b1;
                button_selected = (menu_selection == 2'd1);
            end
        end

        // A one-pixel border surrounds each button. Selected buttons use a
        // blue fill and yellow border; unselected buttons are black with a
        // white border.
        if (button_active) begin
            if (screen_state == TITLE) begin
                button_border = (pixel_x == 7'd38) || (pixel_x == 7'd57) ||
                                (pixel_y == 6'd44) || (pixel_y == 6'd56);
            end else begin
                button_border =
                    ((pixel_x >= 7'd16) && (pixel_x <= 7'd79) &&
                     ((pixel_y == 6'd40) || (pixel_y == 6'd50))) ||
                    ((pixel_x >= 7'd28) && (pixel_x <= 7'd67) &&
                     ((pixel_y == 6'd52) || (pixel_y == 6'd62))) ||
                    (((pixel_x == 7'd16) || (pixel_x == 7'd79)) &&
                     (pixel_y >= 6'd40) && (pixel_y <= 6'd50)) ||
                    (((pixel_x == 7'd28) || (pixel_x == 7'd67)) &&
                     (pixel_y >= 6'd52) && (pixel_y <= 6'd62));
            end

            pixel_active = 1'b1;
            if (button_selected) begin
                if (button_border)
                    pixel_color = 16'hFFE0; // yellow border
                else
                    pixel_color = 16'h001F; // blue highlight
            end else begin
                if (button_border)
                    pixel_color = 16'hFFFF; // white outline
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
module menu_button_text (
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
