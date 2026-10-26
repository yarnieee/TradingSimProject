`timescale 1ns / 1ps

// Four live stock sparklines for the upside-down JA OLED.
//
// A single scan path is shared by all four quadrants. Each graph uses the
// oldest displayed sample and the current price as its two live endpoints;
// this keeps the overview small enough for the Artix-7 while still showing a
// changing graph as the market prices update.
module stocks_overview_layer (
    input  wire [12:0] pixel_index,
    input  wire [3:0]  screen_state,
    input  wire [479:0] stock0_samples,
    input  wire [479:0] stock1_samples,
    input  wire [479:0] stock2_samples,
    input  wire [479:0] stock3_samples,
    input  wire [15:0] price0,
    input  wire [15:0] price1,
    input  wire [15:0] price2,
    input  wire [15:0] price3,
    output reg         pixel_active,
    output reg  [15:0] pixel_color
);
    localparam [3:0] STOCKS = 4'd2;

    wire [6:0] pixel_x = pixel_index % 96;
    wire [5:0] pixel_y = pixel_index / 96;
    reg [1:0] quadrant;
    reg [5:0] quadrant_x;
    reg [5:0] quadrant_y;
    reg       sample0;
    reg       sample1;
    reg [5:0] point_y;
    reg [3:0] char_code;
    reg [3:0] char_position;
    reg [1:0] glyph_x;
    reg [2:0] glyph_y;
    reg       change_negative;
    reg [14:0] glyph_bits;
    wire glyph_pixel = (glyph_y < 3'd5) && (glyph_x < 2'd3) &&
                        glyph_bits[5'd14 - (glyph_y * 3 + glyph_x)];

    // Only the characters used by this compact overview are decoded here.
    // Keeping this local ROM small avoids pulling the full 63-character font
    // into the already tightly packed top-level design.
    function [14:0] overview_glyph;
        input [3:0] code;
        begin
            case (code)
                4'd0: overview_glyph = 15'b010_101_111_101_101; // A
                4'd1: overview_glyph = 15'b110_101_101_101_110; // D
                4'd2: overview_glyph = 15'b101_111_111_101_101; // M
                4'd3: overview_glyph = 15'b101_101_101_101_010; // V
                4'd4: overview_glyph = 15'b011_100_101_101_011; // G
                4'd5: overview_glyph = 15'b010_101_101_101_010; // O
                4'd6: overview_glyph = 15'b110_101_101_101_101; // N
                4'd7: overview_glyph = 15'b111_100_110_100_111; // E
                default: overview_glyph = 15'b000_000_000_000_000;
            endcase
        end
    endfunction

    function [3:0] stock_name_char;
        input [1:0] stock;
        input [1:0] position;
        begin
            stock_name_char = 4'd15;
            case (stock)
                2'd0: case (position)
                    0: stock_name_char = 4'd0; // A
                    1: stock_name_char = 4'd2; // M
                    2: stock_name_char = 4'd1; // D
                    default: stock_name_char = 4'd15;
                endcase
                2'd1: case (position)
                    0: stock_name_char = 4'd0; // A
                    1: stock_name_char = 4'd3; // V
                    2: stock_name_char = 4'd4; // G
                    default: stock_name_char = 4'd5; // O
                endcase
                2'd2: case (position)
                    0: stock_name_char = 4'd6; // N
                    1: stock_name_char = 4'd3; // V
                    2: stock_name_char = 4'd1; // D
                    default: stock_name_char = 4'd0; // A
                endcase
                default: case (position)
                    0: stock_name_char = 4'd4; // G
                    1: stock_name_char = 4'd2; // M
                    2: stock_name_char = 4'd7; // E
                    default: stock_name_char = 4'd15;
                endcase
            endcase
        end
    endfunction

    always @(*) begin
        quadrant = 2'd0;
        quadrant_x = pixel_x[5:0];
        quadrant_y = pixel_y;
        if (pixel_y < 6'd38) begin
            if (pixel_x >= 7'd48) begin
                quadrant = 2'd1;
                quadrant_x = pixel_x - 48;
            end
            quadrant_y = pixel_y - 12;
        end else begin
            if (pixel_x >= 7'd48) begin
                quadrant = 2'd3;
                quadrant_x = pixel_x - 48;
            end else begin
                quadrant = 2'd2;
            end
            quadrant_y = pixel_y - 38;
        end

        sample0 = 16'd0;
        sample1 = 16'd0;
        case (quadrant)
            2'd0: begin
                sample0 = stock0_samples[7];
                sample1 = price0[7];
            end
            2'd1: begin
                sample0 = stock1_samples[7];
                sample1 = price1[7];
            end
            2'd2: begin
                sample0 = stock2_samples[7];
                sample1 = price2[7];
            end
            default: begin
                sample0 = stock3_samples[7];
                sample1 = price3[7];
            end
        endcase

        // The left half represents the older endpoint and the right half the
        // live endpoint. The centered fixed-point scale avoids a divider.
        // Use one coarse price bit from each endpoint as its graph height.
        // This keeps the graph live without a subtract/scale network.
        point_y = (quadrant_x < 6'd24) ?
                  (sample0 ? 6'd12 : 6'd20) :
                  (sample1 ? 6'd12 : 6'd20);

        change_negative = (sample1 < sample0);
        char_code = 4'd15;
        char_position = 0;
        glyph_x = 0;
        glyph_y = 0;
        pixel_active = 1'b0;
        pixel_color = 16'h0000;

        if ((screen_state == STOCKS) && (pixel_y >= 6'd12)) begin
            // Name and signed change in the top row of each quadrant.
            if ((quadrant_y < 6'd7) &&
                (quadrant_x >= 6'd2) && (quadrant_x < 6'd46)) begin
                if (quadrant_x < 6'd18) begin
                    char_position = (quadrant_x - 2) >> 2;
                    glyph_x = quadrant_x - 2 - (char_position * 4);
                    glyph_y = quadrant_y - 1;
                    char_code = stock_name_char(quadrant, char_position[1:0]);
                    pixel_active = glyph_pixel;
                    pixel_color = 16'hFFE0;
                end else if ((quadrant_x == 6'd29) &&
                             (quadrant_y == 6'd3)) begin
                    // Compact signed-change indicator: green for an
                    // increase and red for a decrease.
                    pixel_active = 1'b1;
                    pixel_color = change_negative ? 16'hF800 : 16'h07E0;
                end
            end

            // Compact live sparkline body. The two endpoint levels form a
            // stepped live trace while avoiding a large normalization block.
            if ((quadrant_x >= 6'd3) && (quadrant_x <= 6'd44) &&
                (quadrant_y == point_y)) begin
                pixel_active = 1'b1;
                pixel_color = 16'h07E0;
            end
        end
        glyph_bits = overview_glyph(char_code);
    end
endmodule
