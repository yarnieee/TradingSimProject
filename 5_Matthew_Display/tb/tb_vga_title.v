`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_vga_title: the VGA title screen. The two OLED title pictures side by side,
// each pixel 6 x 6 (x 64..639 left, 640..1215 right, y 72..455), in the
// OLEDs' 16 colours, and black around them.
module tb_vga_title;
    reg clk = 0;  always #5     clk  = ~clk;         // 100 MHz
    reg pclk = 0; always #6.734 pclk = ~pclk;        // 74.25 MHz
    reg rst = 1;
    wire [3:0] r, g, b;
    wire hs, vs;

    vga_screen dut (
        .clk(clk), .rst(rst), .pclk(pclk), .pix_rst(rst),
        .screen_state(`UI_TITLE), .menu_selection(4'd0), .selected_stock(3'd0),
        .trade_side(1'b0), .trade_result_success(1'b0), .trade_result_placed(1'b0),
        .trade_result_code(3'd0), .order_valid(1'b1), .validation_code(3'd0),
        .order_type(`OT_MKT), .order_brk(`BRK_OFF), .order_dist(2'd0), .oled_bot_view(1'b0),
        .orders_view(1'b0), .stock_up(4'b0101), .num_f(), .num_rd(33'd0), .zero({`DN_N{1'b1}}),
        .bot_sel(3'd0), .order({3'd5, 3'd4, 3'd3, 3'd2, 3'd1, 3'd0}),
        .book_valid(8'd0), .book_side(8'd0), .book_stock(16'd0), .book_type(16'd0), .book_leg(8'd0),
        .stock_samples({30{16'd10000}}), .sel_sl(16'd0), .sel_tp(16'd0),
        .progress_w(11'd0), .bar_level(2'd0),
        .vga_r(r), .vga_g(g), .vga_b(b), .hsync(hs), .vsync(vs)
    );

    // the pictures and their colours, as the OLEDs show them
    reg [3:0] art_l [0:6143];
    reg [3:0] art_r [0:6143];
    initial begin
        $readmemh("title_art_left.mem", art_l);
        $readmemh("title_art_right.mem", art_r);
    end
    function [11:0] rgb12;                 // RGB565 palette entry -> 4 bits each
        input [3:0] c;
        reg [15:0] p;
        begin
            case (c)
                4'h0: p = 16'h0000; 4'h1: p = 16'h0085; 4'h2: p = 16'h08EA; 4'h3: p = 16'h21EF;
                4'h4: p = 16'h94D5; 4'h5: p = 16'hF7BD; 4'h6: p = 16'hFE82; 4'h7: p = 16'hF321;
                4'h8: p = 16'hC0C3; 4'h9: p = 16'h1D44; 4'hA: p = 16'h0AC3; 4'hB: p = 16'hE4AD;
                4'hC: p = 16'h61A4; 4'hD: p = 16'h632D; 4'hE: p = 16'hCD50; default: p = 16'h2DB6;
            endcase
            rgb12 = {p[15:12], p[10:7], p[4:1]};
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

    integer n, i, bad_l, bad_r, y;
    reg [11:0] px [0:1279];
    task grab_line;
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

    // one picture row: every one of its 576 pixels on screen line yy
    task picture_line;
        input integer yy;
        integer row;
        begin
            grab_line(yy);
            row = (yy - 72) / 6;
            bad_l = 0; bad_r = 0;
            for (i = 0; i < 576; i = i + 1) begin
                if (px[64 + i]  != rgb12(art_l[row * 96 + i / 6])) bad_l = bad_l + 1;
                if (px[640 + i] != rgb12(art_r[row * 96 + i / 6])) bad_r = bad_r + 1;
            end
            check(bad_l == 0, "left picture, one row, every pixel");
            check(bad_r == 0, "right picture, one row, every pixel");
            if (bad_l || bad_r) $display("     line %0d: %0d / %0d wrong", yy, bad_l, bad_r);
            check(px[63] == 12'h000 && px[1216] == 12'h000, "black either side of the pictures");
        end
    endtask

    initial begin
        repeat (5) @(posedge clk); rst = 0;
        repeat (9000) @(posedge clk);       // the writer fills the character RAM once

        picture_line(72);                   // first row of the pictures
        picture_line(72 + 6 * 31 + 5);      // the last line of row 31
        picture_line(72 + 6 * 63 + 2);      // last row
        grab_line(71);
        check(px[64] == 12'h000 && px[700] == 12'h000, "nothing above the pictures");
        grab_line(456);
        check(px[64] == 12'h000 && px[700] == 12'h000, "nothing below the pictures");

        if (n_fail == 0) $display("PASS: tb_vga_title (%0d checks)", n_pass);
        else             $display("FAIL: tb_vga_title (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
