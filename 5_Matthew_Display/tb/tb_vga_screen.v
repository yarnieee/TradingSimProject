`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_vga_screen: vga_screen on its own, with the 74.25 MHz pixel clock driven
// here. Checks the 1280 x 720 @ 60 Hz timing (1650-pixel lines with a 40-pixel
// hsync, 750-line frames with a 5-line vsync, both high pulses), that nothing is
// driven outside the visible area, and a few pixels of a frame: the title bar,
// the progress bar, and text from the character RAM.
module tb_vga_screen;
    reg clk = 0;  always #5     clk  = ~clk;         // 100 MHz
    reg pclk = 0; always #6.734 pclk = ~pclk;        // 74.25 MHz
    reg rst = 1;
    wire [3:0] r, g, b;
    wire hs, vs;

    vga_screen dut (
        .clk(clk), .rst(rst), .pclk(pclk), .pix_rst(rst),
        .screen_state(`UI_PORTFOLIO), .menu_selection(4'd0), .selected_stock(3'd0),
        .trade_side(1'b0), .trade_result_success(1'b0), .trade_result_placed(1'b0),
        .trade_result_code(3'd0), .order_valid(1'b1), .validation_code(3'd0),
        .order_type(`OT_MKT), .order_brk(`BRK_OFF), .order_dist(2'd0), .oled_bot_view(1'b0),
        .stock_up(4'b0101), .bcd({(`DN_N*32){1'b0}}), .neg({`DN_N{1'b0}}),
        .book_valid(8'd0), .book_side(8'd0), .book_stock(16'd0), .book_type(16'd0), .book_leg(8'd0),
        .log_valid(5'd0), .log_side(5'd0), .log_stock(10'd0),
        .stock_samples({30{16'd10000}}), .sel_sl(16'd0), .sel_tp(16'd0),
        .progress_w(11'd621),                       // half of the 1242-pixel bar
        .vga_r(r), .vga_g(g), .vga_b(b), .hsync(hs), .vsync(vs)
    );

    integer n_pass = 0, n_fail = 0;
    task check;
        input          cond;
        input [8*60:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s (t=%0t)", name, $time); end
        end
    endtask

    // one sample per pixel: outputs change on the rising edge, read them on the falling one
    integer n, line_px, hhigh, vlines, frame_px, i, k;
    reg     black_ok;
    reg [11:0] px [0:1279];

    // grab visible line y (pixels 0..1279) of the frame that starts at the next vsync rise
    task grab_line;
        input integer y;
        begin
            @(posedge vs);
            for (n = 0; n <= (25 + y) * 1650; n = n + 1) @(negedge pclk);   // the first one is pixel 0
            for (i = 0; i < 1280; i = i + 1) begin
                px[i] = {r, g, b};
                @(negedge pclk);
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk); rst = 0;
        // let the writer fill the character RAM once (30 x 71 cells x 4 clocks)
        repeat (9000) @(posedge clk);

        // ---- line timing: two hsync rises, and how long it stays high
        @(posedge hs); @(negedge pclk);
        n = 0; while (hs) begin @(negedge pclk); n = n + 1; end
        hhigh = n;
        while (!hs) begin @(negedge pclk); n = n + 1; end
        line_px = n;
        check(line_px == 1650, "a line is 1650 pixels");
        check(hhigh == 40, "hsync is high for 40 pixels");

        // ---- frame timing
        @(posedge vs); @(negedge pclk);
        n = 0; while (vs) begin @(negedge pclk); n = n + 1; end
        vlines = n / 1650;
        check(n == 5 * 1650, "vsync is high for 5 lines");
        while (!vs) begin @(negedge pclk); n = n + 1; end
        frame_px = n;
        check(frame_px == 1650 * 750, "a frame is 750 lines");

        // ---- black outside the picture: during vsync and its back porch (25 lines)
        black_ok = 1'b1;
        for (n = 0; n < 1650 * 25; n = n + 1) begin
            if ({r, g, b} != 12'h000) black_ok = 1'b0;
            @(negedge pclk);
        end
        check(black_ok, "nothing is driven outside the visible area");

        // ---- visible line 6 (title bar, row 0) and line 35 (progress bar, row 1)
        grab_line(6);
        check(px[1270] == 12'h126, "title bar is navy at its right end");
        check(px[0] == 12'h126, "title bar starts at the left edge");
        k = 0; for (i = 18; i < 522; i = i + 1) if (px[i] == 12'hFFF) k = k + 1;
        check(k > 100, "title text drawn in white from the character RAM");

        grab_line(35);
        check(px[100] == 12'hFC0 && px[638] == 12'hFC0, "progress bar filled up to half (x 18..638)");
        check(px[639] == 12'h222 && px[1259] == 12'h222, "rest of the progress bar dark");
        check(px[5] == 12'h000 && px[1270] == 12'h000, "nothing either side of the progress bar");

        if (n_fail == 0) $display("PASS: tb_vga_screen (%0d checks)", n_pass);
        else             $display("FAIL: tb_vga_screen (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
