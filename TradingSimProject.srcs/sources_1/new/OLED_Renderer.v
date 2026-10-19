`timescale 1ns / 1ps

// Shared OLED renderer for all game states.
module OLED_Renderer (
    input  [12:0] pixel_index,
    input  [3:0]  screen_state,
    output reg [15:0] pixel_data
);

    wire text_pixel;

    text_layer text_layer_inst (
        .pixel_index(pixel_index),
        .screen_state(screen_state),
        .text_pixel(text_pixel)
    );

    always @(*) begin
        if (text_pixel)
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

    text_layer text_layer_inst (
        .pixel_index(flipped_pixel_index),
        .screen_state(screen_state),
        .text_pixel(text_pixel)
    );

    always @(*) begin
        // Black background when no button indicator is active.
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
