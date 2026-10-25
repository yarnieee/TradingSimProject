`timescale 1ns / 1ps
`default_nettype none

// Two 96x64 indexed-color title images for the paired OLEDs.
// The left image omits the START/HIGH SCORES area; the right image contains
// the supplied START-button artwork. The 4-bit indexed memories keep the
// artwork small enough to fit the target FPGA; the shared 16-entry palette
// converts each pixel to the RGB565 format used by the OLEDs.
module title_art_renderer (
    input  wire [12:0] pixel_index_R,
    input  wire [12:0] pixel_index_L,
    output wire [15:0] pixel_data_R,
    output wire [15:0] pixel_data_L
);
    reg [3:0] title_art_left  [0:6143];
    reg [3:0] title_art_right [0:6143];

    function [15:0] palette_rgb565;
        input [3:0] color_index;
        begin
            case (color_index)
                4'h0: palette_rgb565 = 16'h0000;
                4'h1: palette_rgb565 = 16'h0085;
                4'h2: palette_rgb565 = 16'h08EA;
                4'h3: palette_rgb565 = 16'h21EF;
                4'h4: palette_rgb565 = 16'h94D5;
                4'h5: palette_rgb565 = 16'hF7BD;
                4'h6: palette_rgb565 = 16'hFE82;
                4'h7: palette_rgb565 = 16'hF321;
                4'h8: palette_rgb565 = 16'hC0C3;
                4'h9: palette_rgb565 = 16'h1D44;
                4'hA: palette_rgb565 = 16'h0AC3;
                4'hB: palette_rgb565 = 16'hE4AD;
                4'hC: palette_rgb565 = 16'h61A4;
                4'hD: palette_rgb565 = 16'h632D;
                4'hE: palette_rgb565 = 16'hCD50;
                4'hF: palette_rgb565 = 16'h2DB6;
            endcase
        end
    endfunction

    initial begin
        $readmemh("title_art_left.mem", title_art_left);
        $readmemh("title_art_right.mem", title_art_right);
    end

    assign pixel_data_R = palette_rgb565(title_art_right[pixel_index_R]);
    assign pixel_data_L = palette_rgb565(title_art_left[pixel_index_L]);
endmodule

`default_nettype wire
