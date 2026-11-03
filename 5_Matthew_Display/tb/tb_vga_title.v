`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_vga_title: the VGA title screen. One 320 x 180 picture (title_screen.mem),
// each pixel 4 x 4 over the whole 1280 x 720 screen, in its 16 colours; colour
// 15 (PRESS START) blinks between bright and the button's colour. Here the
// blink changes every frame (TITLE_BLINK = 0).
module tb_vga_title;
    reg clk = 0;  always #5     clk  = ~clk;         // 100 MHz
    reg pclk = 0; always #6.734 pclk = ~pclk;        // 74.25 MHz
    reg rst = 1;
    wire [3:0] r, g, b;
    wire hs, vs;

    vga_screen #(.TITLE_BLINK(0)) dut (
        .clk(clk), .rst(rst), .pclk(pclk), .pix_rst(rst),
        .screen_state(`UI_TITLE), .menu_selection(4'd0), .selected_stock(3'd0),
        .trade_side(1'b0), .trade_result_success(1'b0), .trade_result_placed(1'b0),
        .trade_result_code(3'd0), .order_valid(1'b1), .validation_code(3'd0),
        .order_type(`OT_MKT), .order_brk(`BRK_OFF), .order_dist(2'd0), .oled_bot_view(1'b0),
        .orders_view(1'b0), .stock_up(4'b0101), .num_f(), .num_rd(33'd0), .zero({`DN_N{1'b1}}),
        .bot_sel(3'd0), .order({3'd5, 3'd4, 3'd3, 3'd2, 3'd1, 3'd0}),
        .book_valid(8'd0), .book_side(8'd0), .book_stock(16'd0), .book_type(16'd0), .book_leg(8'd0),
        .stock_samples({30{16'd10000}}), .sel_sl(16'd0), .sel_tp(16'd0),
        .progress_w(11'd600), .bar_level(2'd0),
        .vga_r(r), .vga_g(g), .vga_b(b), .hsync(hs), .vsync(vs)
    );

    // the picture and its colours, as make_title_screen.py draws them
    reg [3:0] pic [0:57599];
    initial $readmemh("title_screen.mem", pic);
    function [11:0] rgb12;
        input [3:0] c;
        input       on;                    // the blinking colour is bright
        begin
            case (c)
                4'h0: rgb12 = 12'h112; 4'h1: rgb12 = 12'h224; 4'h2: rgb12 = 12'h349; 4'h3: rgb12 = 12'hFFF;
                4'h4: rgb12 = 12'hAAB; 4'h5: rgb12 = 12'h000; 4'h6: rgb12 = 12'hFD2; 4'h7: rgb12 = 12'hF82;
                4'h8: rgb12 = 12'h3D4; 4'h9: rgb12 = 12'h173; 4'hA: rgb12 = 12'hE33; 4'hB: rgb12 = 12'h812;
                4'hC: rgb12 = 12'hEDA; 4'hD: rgb12 = 12'h5DF; 4'hE: rgb12 = 12'h226;
                default: rgb12 = on ? 12'hFF6 : 12'h226;
            endcase
        end
    endfunction

    integer n_pass = 0, n_fail = 0;
    task check;
        input          cond;
        input [8*60:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s (t=%0t)", name, $time); end
        end
    endtask

    integer n, i, bad_on, bad_off, blinkers;
    reg [11:0] px [0:1279];
    task grab_line;                         // visible line yy of the next frame
        input integer yy;
        begin
            @(posedge vs);
            for (n = 0; n <= (25 + yy) * 1650; n = n + 1) @(negedge pclk);
            for (i = 0; i < 1280; i = i + 1) begin
                px[i] = {r, g, b};
                @(negedge pclk);
            end
        end
    endtask
    // every pixel of screen line yy against the picture, with the blink on and off
    task compare;
        input integer yy;
        integer a;
        begin
            bad_on = 0; bad_off = 0; blinkers = 0;
            for (i = 0; i < 1280; i = i + 1) begin
                a = (yy / 4) * 320 + i / 4;
                if (px[i] != rgb12(pic[a], 1'b1)) bad_on  = bad_on + 1;
                if (px[i] != rgb12(pic[a], 1'b0)) bad_off = bad_off + 1;
                if (pic[a] == 4'hF) blinkers = blinkers + 1;
            end
        end
    endtask

    reg first_on;
    initial begin
        repeat (5) @(posedge clk); rst = 0;
        repeat (9000) @(posedge clk);

        grab_line(0);    compare(0);
        check(bad_on == 0 || bad_off == 0, "screen line 0: the picture's top row, every pixel");
        grab_line(361);  compare(361);
        check(bad_on == 0 || bad_off == 0, "screen line 361: the bull, VS and the bear");
        grab_line(530);  compare(530);
        check(bad_on == 0 || bad_off == 0, "screen line 530: the five bots");
        grab_line(719);  compare(719);
        check(bad_on == 0 || bad_off == 0, "screen line 719: the picture's last row");

        // PRESS START: line 670 crosses its letters; one frame bright, the next not
        grab_line(670);  compare(670);
        check(blinkers > 100, "line 670 crosses the PRESS START letters");
        first_on = (bad_on == 0);
        check(bad_on == 0 || bad_off == 0, "line 670: every pixel, blink on or off");
        grab_line(670);  compare(670);
        check(first_on ? (bad_off == 0 && bad_on != 0) : (bad_on == 0 && bad_off != 0),
              "PRESS START blinks: the next frame has the other colour");

        if (n_fail == 0) $display("PASS: tb_vga_title (%0d checks)", n_pass);
        else             $display("FAIL: tb_vga_title (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
