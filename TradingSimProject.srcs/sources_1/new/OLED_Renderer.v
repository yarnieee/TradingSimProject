`timescale 1ns / 1ps

module OLED_Renderer (
    input  wire [12:0] pixel_index,
    output reg  [15:0] pixel_data
);

    // The OLED resolution is 96 x 64 pixels.
    wire [6:0] pixel_x;
    wire [5:0] pixel_y;

    assign pixel_x = pixel_index % 96;
    assign pixel_y = pixel_index / 96;

    // Circle centre is (80, 32). Signed values prevent underflow when a pixel
    // lies to the left or above the centre.
    wire signed [7:0] circle_dx;
    wire signed [7:0] circle_dy;
    wire signed [15:0] circle_distance;

    assign circle_dx = $signed({1'b0, pixel_x}) - 8'sd80;
    assign circle_dy = $signed({2'b0, pixel_y}) - 8'sd32;
    assign circle_distance = (circle_dx * circle_dx) + (circle_dy * circle_dy);

    always @(*) begin
        // RGB565 black background.
        pixel_data = 16'h0000;

        // Cyan Box
        if (7'd20 <= pixel_x && pixel_x < 7'd40 && 6'd10 <= pixel_y && pixel_y < 6'd50)
            pixel_data = 16'h07FF;

        // Magenta circle centred at (80, 32), radius 10.
        if (circle_distance <= 16'sd100)
            pixel_data = 16'hF81F;
    end

endmodule
