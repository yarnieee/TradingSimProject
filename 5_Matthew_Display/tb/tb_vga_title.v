`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_vga_title: the VGA title screen. One 320 x 180 picture (title_art_vga.mem),
// each pixel 4 x 4, over the whole 1280 x 720 screen in its 16 colours: every
// visible pixel of a frame is checked, and the frame is written to
// title_frame_rgb.txt (one 12-bit colour per line, row by row) for a preview.
// Off the title screen (PORTFOLIO) the picture is gone.
module tb_vga_title;
    reg clk = 0;  always #5     clk  = ~clk;         // 100 MHz
    reg pclk = 0; always #6.734 pclk = ~pclk;        // 74.25 MHz
    reg rst = 1;
    reg [3:0] screen_state = `UI_TITLE;
    wire [3:0] r, g, b;
    wire hs, vs;

    vga_screen dut (
        .clk(clk), .rst(rst), .pclk(pclk), .pix_rst(rst),
        .screen_state(screen_state), .menu_selection(4'd0), .selected_stock(3'd0),
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

    // the picture and its colours
    reg [3:0] art [0:57599];
    initial $readmemh("title_art_vga.mem", art);
    function [11:0] rgb12;
        input [3:0] c;
        begin
            case (c)
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

    // one whole frame: every visible pixel against the picture (and written out)
    integer x, y, n, bad, first_bad, f, line_bad;
    reg [11:0] want;
    task frame;
        input dump;
        begin
            bad = 0; first_bad = -1;
            if (dump) f = $fopen("title_frame_rgb.txt", "w");
            @(posedge vs);
            for (n = 0; n <= 25 * 1650; n = n + 1) @(negedge pclk);  // vsync at line 725: 25 lines to line 0
            for (y = 0; y < 720; y = y + 1)
                for (x = 0; x < 1650; x = x + 1) begin
                    if (x < 1280) begin
                        want = rgb12(art[(y / 4) * 320 + x / 4]);
                        if ({r, g, b} !== want) begin
                            bad = bad + 1;
                            if (first_bad < 0) first_bad = y * 1280 + x;
                        end
                        if (dump) $fwrite(f, "%03h\n", {r, g, b});
                    end
                    @(negedge pclk);
                end
            if (dump) $fclose(f);
        end
    endtask

    // one screen line, against the picture
    task line_vs_art;
        input integer yy;
        begin
            line_bad = 0;
            @(posedge vs);
            for (n = 0; n <= (25 + yy) * 1650; n = n + 1) @(negedge pclk);
            for (x = 0; x < 1280; x = x + 1) begin
                if ({r, g, b} !== rgb12(art[(yy / 4) * 320 + x / 4])) line_bad = line_bad + 1;
                @(negedge pclk);
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk); rst = 0;
        repeat (9000) @(posedge clk);       // the writer fills the character RAM once

        frame(1'b1);
        check(bad == 0, "title: all 921,600 pixels are the picture, 4 x 4 each");
        if (bad) $display("     %0d wrong, first at pixel %0d (x %0d, y %0d)", bad, first_bad, first_bad % 1280, first_bad / 1280);
        else     $display("     frame: 1280 x 720, every pixel = palette[title_art_vga.mem[(y/4)*320 + x/4]]");
        // no text, progress bar or DAYS LEFT on top: rows 0, 1, 21, 28, 29 are the picture too
        line_vs_art(10);  check(line_bad == 0, "title bar row (DAYS LEFT) covered by the picture");
        line_vs_art(35);  check(line_bad == 0, "progress bar covered by the picture");
        line_vs_art(515); check(line_bad == 0, "old PRESS BTNC text row covered by the picture");
        line_vs_art(700); check(line_bad == 0, "NOW / switches rows covered by the picture");

        // off the title screen: the trading screen, not the picture
        screen_state = `UI_PORTFOLIO;
        repeat (9000) @(posedge clk);
        line_vs_art(35);
        check(line_bad > 640, "portfolio screen: the picture is gone (progress bar line)");
        line_vs_art(300);
        check(line_bad > 640, "portfolio screen: the picture is gone (middle line)");

        if (n_fail == 0) $display("PASS: tb_vga_title (%0d checks)", n_pass);
        else             $display("FAIL: tb_vga_title (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
