`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME: Li Yi An
//  STUDENT B NAME: Douglas
//  STUDENT C NAME: Tricia
//  STUDENT D NAME: Matthew
//////////////////////////////////////////////////////////////////////////////////

module My_Top_Module (
    input clk,
    input rst, //currently, reset is the centre button
    output [7:0] JB
    );

    wire clk_6_25Hz; //
    slower_clk #(32'd7) slow_clk_inst (clk, clk_6_25Hz);
    reg [15:0] oled_data = 16'h07E0;
    
    wire rst;
    wire frame_begin;
    wire sending_pixels;
    wire sample_pixel;
    wire [12:0] pixel_index; // 0 to 6143 for a 96x64 display
    
    Oled_Display Oled_Display_Inst (
        .clk(clk_6_25Hz), //inputs
        .reset(rst),
        .pixel_data(oled_data),
        .frame_begin(frame_begin), //outputs
        .sending_pixels(sending_pixels),
        .sample_pixel(sample_pixel),
        .pixel_index(pixel_index),
        .cs(JB[0]),
        .sdin(JB[1]),
        .sclk(JB[3]),
        .d_cn(JB[4]),
        .resn(JB[5]),
        .vccen(JB[6]),
        .pmoden(JB[7])
    );
    
//    wire [6:0] x_coor = pixel_index % 96;
//    wire [5:0] y_coor = pixel_index / 96;

    // --- DRAWING LOGIC ---
    // Color definitions in 16-bit RGB565 format:
    // Red:   16'hF800 
    // Green: 16'h07E0
    // Blue:  16'h001F
//    always @* begin
//        if (x_coor < 32) begin
//            oled_data = 16'hF800; // Left third: Red
//        end else if (x_coor < 64) begin
//            oled_data = 16'h07E0; // Middle third: Green
//        end else begin
//            oled_data = 16'h001F; // Right third: Blue
//        end
//    end

endmodule