`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_vga_title: the VGA title screen. One 320 x 180 picture (title_art_vga.mem),
// each pixel 4 x 4 over the whole 1280 x 720 screen, in its 16 colours; PRESS
// BTNC TO START (picture rows 146 down) blinks: shown, then background. Here
// the blink changes every frame (TITLE_BLINK = 0).
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
        .book_valid(8'd0), .book_side(8'd0), .book_stock(16'd0), .book_type(16'd0), .book_leg(8'd0), .feed_valid(8'd0), .feed_bot(24'd0), .feed_side(8'd0), .feed_stock(16'd0),
        .stock_samples({30{16'd10000}}), .sel_sl(16'd0), .sel_tp(16'd0),
        .progress_w(11'd600), .bar_level(2'd0),
        .vga_r(r), .vga_g(g), .vga_b(b), .hsync(hs), .vsync(vs)
    );

    // the picture and its colours
    reg [3:0] pic [0:57599];
    initial $readmemh("title_art_vga.mem", pic);
    function [11:0] rgb12;
        input [3:0] c;
        input       on;                    // 0: the blink is off (PRESS START rows hidden)
        input       btn_row;               // the pixel is in the PRESS START rows
        reg   [3:0] k;
        begin
            k = (btn_row && !on) ? 4'h0 : c;
            case (k)
                4'h0: rgb12 = 12'h112; 4'h1: rgb12 = 12'h235; 4'h2: rgb12 = 12'h812; 4'h3: rgb12 = 12'h183;
                4'h4: rgb12 = 12'h862; 4'h5: rgb12 = 12'h358; 4'h6: rgb12 = 12'h1E4; 4'h7: rgb12 = 12'hE32;
                4'h8: rgb12 = 12'hD91; 4'h9: rgb12 = 12'h0CD; 4'hA: rgb12 = 12'h48D; 4'hB: rgb12 = 12'h998;
                4'hC: rgb12 = 12'hEE1; 4'hD: rgb12 = 12'hABD; 4'hE: rgb12 = 12'hED9; default: rgb12 = 12'hDEE;
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
                if (px[i] != rgb12(pic[a], 1'b1, yy / 4 >= 146)) bad_on  = bad_on + 1;
                if (px[i] != rgb12(pic[a], 1'b0, yy / 4 >= 146)) bad_off = bad_off + 1;
                if (yy / 4 >= 146 && pic[a] != 4'h0) blinkers = blinkers + 1;
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
        check(bad_on == 0 && bad_off == 0, "screen line 361: the bull, the bolt and the bear (no blink)");
        grab_line(530);  compare(530);
        check(bad_on == 0 || bad_off == 0, "screen line 530: the five bots");
        grab_line(719);  compare(719);
        check(bad_on == 0 || bad_off == 0, "screen line 719: the picture's last row");

        // the bots' shelf just above the button (picture row 141) never blinks:
        // two frames running, both exactly the picture
        grab_line(566);  compare(566);
        check(bad_on == 0 && bad_off == 0, "line 566 (the shelf above the button): the picture");
        grab_line(566);  compare(566);
        check(bad_on == 0 && bad_off == 0, "line 566 next frame: still the picture (only the button blinks)");

        // PRESS BTNC TO START: line 630 (picture row 157) crosses its letters; one
        // frame shown, the next hidden
        grab_line(630);  compare(630);
        check(blinkers > 100, "line 630 crosses the PRESS START letters");
        first_on = (bad_on == 0);
        check(bad_on == 0 || bad_off == 0, "line 630: every pixel, blink on or off");
        grab_line(630);  compare(630);
        check(first_on ? (bad_off == 0 && bad_on != 0) : (bad_on == 0 && bad_off != 0),
              "PRESS START blinks: the next frame has the other colour");

        if (n_fail == 0) $display("PASS: tb_vga_title (%0d checks)", n_pass);
        else             $display("FAIL: tb_vga_title (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
