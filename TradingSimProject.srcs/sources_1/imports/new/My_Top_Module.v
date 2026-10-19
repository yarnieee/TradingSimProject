`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME: Li Yi An
//  STUDENT B NAME: Douglas
//  STUDENT C NAME: Tricia
//  STUDENT D NAME: Matthew
//////////////////////////////////////////////////////////////////////////////////

module MyTopModule (
    input clk,
    input rst,
    input btnU,
    input btnD,
    input btnL,
    input btnR,
    input btnC,
    output [7:0] JA,
    output [7:0] JB,
    output [15:0] led,
    output [3:0] an,
    output [7:0] seg
    );

    wire clk_6_25Hz;
    slower_clk #(32'd7) slow_clk_inst (clk, clk_6_25Hz);

    // Debounce each physical button before using it in the FSM.
    wire btnU_debounced;
    wire btnD_debounced;
    wire btnL_debounced;
    wire btnR_debounced;
    wire btnC_debounced;

    debouncer #(.DEBOUNCE_CTR(32'd1_999_999)) debounce_U (
        .clk(clk), .btn(btnU), .debounced(btnU_debounced)
    );
    debouncer #(.DEBOUNCE_CTR(32'd1_999_999)) debounce_D (
        .clk(clk), .btn(btnD), .debounced(btnD_debounced)
    );
    debouncer #(.DEBOUNCE_CTR(32'd1_999_999)) debounce_L (
        .clk(clk), .btn(btnL), .debounced(btnL_debounced)
    );
    debouncer #(.DEBOUNCE_CTR(32'd1_999_999)) debounce_R (
        .clk(clk), .btn(btnR), .debounced(btnR_debounced)
    );
    debouncer #(.DEBOUNCE_CTR(32'd1_999_999)) debounce_C (
        .clk(clk), .btn(btnC), .debounced(btnC_debounced)
    );

    // Convert each debounced button level into a one-clock pulse.
    reg btnU_previous;
    reg btnD_previous;
    reg btnL_previous;
    reg btnR_previous;
    reg btnC_previous;

    always @(posedge clk) begin
        if (rst) begin
            btnU_previous <= 1'b0;
            btnD_previous <= 1'b0;
            btnL_previous <= 1'b0;
            btnR_previous <= 1'b0;
            btnC_previous <= 1'b0;
        end else begin
            btnU_previous <= btnU_debounced;
            btnD_previous <= btnD_debounced;
            btnL_previous <= btnL_debounced;
            btnR_previous <= btnR_debounced;
            btnC_previous <= btnC_debounced;
        end
    end

    wire btnU_pulse = btnU_debounced & ~btnU_previous;
    wire btnD_pulse = btnD_debounced & ~btnD_previous;
    wire btnL_pulse = btnL_debounced & ~btnL_previous;
    wire btnR_pulse = btnR_debounced & ~btnR_previous;
    wire btnC_pulse = btnC_debounced & ~btnC_previous;

    wire [3:0] screen_state;
    wire [13:0] quantity;

    game_fsm game_fsm_inst (
        .clk(clk),
        .rst(rst),
        .btnU(btnU_pulse),
        .btnD(btnD_pulse),
        .btnL(btnL_pulse),
        .btnR(btnR_pulse),
        .btnC(btnC_pulse),
        .screen_state(screen_state),
        .quantity(quantity)
    );

    wire frame_begin;
    wire sending_pixels;
    wire sample_pixel;
    wire [12:0] pixel_index; // 0 to 6143 for a 96x64 display
    wire [15:0] pixel_data;

    wire frame_begin_ja;
    wire sending_pixels_ja;
    wire sample_pixel_ja;
    wire [12:0] pixel_index_ja;
    wire [15:0] pixel_data_ja;
    
    OLED_Renderer Oled_Renderer (
        .pixel_index(pixel_index),
        .screen_state(screen_state),
        .pixel_data(pixel_data)
    );

    OLED_Button_Renderer Oled_Button_Renderer (
        .pixel_index(pixel_index_ja),
        .screen_state(screen_state),
        .btnU(btnU_debounced),
        .btnD(btnD_debounced),
        .btnL(btnL_debounced),
        .btnR(btnR_debounced),
        .btnC(btnC_debounced),
        .pixel_data(pixel_data_ja)
    );
    
    // The project source list contains module oled_display, whose name is
    // case-sensitive in Verilog.
    oled_display Oled_Display_Inst (
        .clk(clk_6_25Hz), //inputs
        .reset(rst),
        .pixel_data(pixel_data),
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

    // Second OLED on JA. It uses the same current-state text as JB, while
    // OLED_Button_Renderer rotates the image for the upside-down mounting.
    oled_display Oled_Display_JA_Inst (
        .clk(clk_6_25Hz),
        .reset(rst),
        .pixel_data(pixel_data_ja),
        .frame_begin(frame_begin_ja),
        .sending_pixels(sending_pixels_ja),
        .sample_pixel(sample_pixel_ja),
        .pixel_index(pixel_index_ja),
        .cs(JA[0]),
        .sdin(JA[1]),
        .sclk(JA[3]),
        .d_cn(JA[4]),
        .resn(JA[5]),
        .vccen(JA[6]),
        .pmoden(JA[7])
    );

    quantity_7seg quantity_7seg_inst (
        .clk(clk),
        .rst(rst),
        .quantity(quantity),
        .an(an),
        .seg(seg)
    );

    // JB[2] is unused by the OLED PMOD connection.
    // JA[2] is unused by the second OLED PMOD connection.
    assign JA[2] = 1'b0;
    assign JB[2] = 1'b0;
    assign led = {8'b0, screen_state, 4'b0};

endmodule

// Compatibility wrapper for older project settings that still refer to
// My_Top_Module. The Vivado project now uses MyTopModule as its top module.
module My_Top_Module (
    input clk,
    input rst,
    input btnU,
    input btnD,
    input btnL,
    input btnR,
    input btnC,
    output [7:0] JA,
    output [7:0] JB,
    output [15:0] led,
    output [3:0] an,
    output [7:0] seg
    );

    MyTopModule implementation (
        .clk(clk),
        .rst(rst),
        .btnU(btnU),
        .btnD(btnD),
        .btnL(btnL),
        .btnR(btnR),
        .btnC(btnC),
        .JA(JA),
        .JB(JB),
        .led(led),
        .an(an),
        .seg(seg)
    );

endmodule
