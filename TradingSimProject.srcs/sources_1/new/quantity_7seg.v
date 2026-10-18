`timescale 1ns / 1ps

// Displays the binary quantity as four multiplexed decimal digits.
module quantity_7seg (
    input        clk,
    input        rst,
    input [13:0] quantity,
    output reg [3:0] an,
    output reg [7:0] seg
);

    wire [3:0] thousands;
    wire [3:0] hundreds;
    wire [3:0] tens;
    wire [3:0] ones;

    binary_to_bcd_14bit binary_to_bcd_inst (
        .bin(quantity),
        .thousands(thousands),
        .hundreds(hundreds),
        .tens(tens),
        .ones(ones)
    );

    reg [16:0] scan_counter;
    reg [1:0] digit_select;
    reg [3:0] selected_digit;

    always @(posedge clk) begin
        if (rst) begin
            scan_counter <= 0;
            digit_select <= 0;
        end else if (scan_counter == 17'd24999) begin
            scan_counter <= 0;
            digit_select <= digit_select + 1'b1;
        end else begin
            scan_counter <= scan_counter + 1'b1;
        end
    end

    always @(*) begin
        case (digit_select)
            2'd0: begin
                an = 4'b1110;
                selected_digit = ones;
            end
            2'd1: begin
                an = 4'b1101;
                selected_digit = tens;
            end
            2'd2: begin
                an = 4'b1011;
                selected_digit = hundreds;
            end
            default: begin
                an = 4'b0111;
                selected_digit = thousands;
            end
        endcase

        // Basys3 seven-segment display is active-low.
        case (selected_digit)
            4'd0: seg = 8'b11000000;
            4'd1: seg = 8'b11111001;
            4'd2: seg = 8'b10100100;
            4'd3: seg = 8'b10110000;
            4'd4: seg = 8'b10011001;
            4'd5: seg = 8'b10010010;
            4'd6: seg = 8'b10000010;
            4'd7: seg = 8'b11111000;
            4'd8: seg = 8'b10000000;
            4'd9: seg = 8'b10010000;
            default: seg = 8'b11111111;
        endcase
    end

endmodule
