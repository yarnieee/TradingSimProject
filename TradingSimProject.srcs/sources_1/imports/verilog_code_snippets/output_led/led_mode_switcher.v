`timescale 1ns / 1ps

module led_mode_switcher(
    input clk,
    input [2:0] mode,
    input rst,
    output reg [15:0] led
    );

    // ======================= STATE MACHINE =========================
    always @(*) begin
        case(mode)
            3'd0: begin
                led = 16'b0;
            end

            default: begin
                led = 16'b1111_1111_1111_1111;
            end
        endcase
    end
        
endmodule
