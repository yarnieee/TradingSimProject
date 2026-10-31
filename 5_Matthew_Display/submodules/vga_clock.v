`timescale 1ns / 1ps
`default_nettype none

// vga_clock: the 74.25 MHz pixel clock for 1280 x 720 at 60 Hz, made from the
// 100 MHz board clock by one MMCM (Xilinx primitive, no IP needed):
//   100 MHz / 5 = 20 MHz, x 37.125 = 742.5 MHz (VCO), / 10 = 74.25 MHz.
// pix_rst holds the VGA side in reset until the clock is locked (and while rst).
module vga_clock (
    input  wire clk,          // 100 MHz
    input  wire rst,
    output wire pclk,         // 74.25 MHz
    output reg  pix_rst
);
    wire fb, clk_out, locked;

    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.0),
        .DIVCLK_DIVIDE(5),
        .CLKFBOUT_MULT_F(37.125),
        .CLKOUT0_DIVIDE_F(10.0)
    ) mmcm (
        .CLKIN1(clk), .CLKFBIN(fb), .CLKFBOUT(fb),
        .CLKOUT0(clk_out), .LOCKED(locked),
        .RST(1'b0), .PWRDWN(1'b0),
        .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
    );

    BUFG pclk_buf (.I(clk_out), .O(pclk));

    // reset into the pixel clock: two flip-flops
    reg r1;
    always @(posedge pclk or posedge rst) begin
        if (rst) begin r1 <= 1'b1; pix_rst <= 1'b1; end
        else     begin r1 <= !locked; pix_rst <= r1; end
    end
endmodule

`default_nettype wire
