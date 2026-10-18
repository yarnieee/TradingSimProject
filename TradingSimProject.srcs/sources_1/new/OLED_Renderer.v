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
