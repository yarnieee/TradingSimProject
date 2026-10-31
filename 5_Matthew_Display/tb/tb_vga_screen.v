`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_vga_screen: vga_screen on its own. Checks the 640 x 480 @ 60 Hz timing
// (800-pixel lines with a 96-pixel hsync, 525-line frames with a 2-line vsync),
// that nothing is driven outside the visible area, and a few pixels of the
// first frame: the title bar, the progress bar, and text from the character RAM.
module tb_vga_screen;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1;
    wire [3:0] r, g, b;
    wire hs, vs;

    vga_screen dut (
        .clk(clk), .rst(rst),
        .screen_state(`UI_PORTFOLIO), .menu_selection(4'd0), .selected_stock(3'd0),
        .trade_side(1'b0), .trade_result_success(1'b0), .trade_result_placed(1'b0),
        .trade_result_code(3'd0), .order_valid(1'b1), .validation_code(3'd0),
        .order_type(`OT_MKT), .order_brk(`BRK_OFF), .order_dist(2'd0), .oled_bot_view(1'b0),
        .stock_up(4'b0101), .bcd({(`DN_N*32){1'b0}}), .neg({`DN_N{1'b0}}),
        .book_valid(8'd0), .book_side(8'd0), .book_stock(16'd0), .book_type(16'd0), .book_leg(8'd0),
        .log_valid(5'd0), .log_side(5'd0), .log_stock(10'd0),
        .stock_samples({30{16'd10000}}), .sel_sl(16'd0), .sel_tp(16'd0),
        .progress_w(10'd308),                       // half of the 616-pixel bar
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

    // one sample per pixel, in the middle of it
    function sample_now; input dummy; sample_now = (dut.div4 == 2'd1); endfunction

    integer t_hfall, t_prev_hfall, hlow, vlines, i, line_px, frame_px, k;
    reg     hs_d, vs_d, black_ok;
    reg [11:0] px [0:639];
    initial begin
        repeat (5) @(posedge clk); rst = 0;
        // let the writer fill the character RAM once (30 x 53 cells x 4 clocks)
        repeat (8000) @(posedge clk);

        // ---- line timing: measure two hsync falls
        @(negedge hs); t_prev_hfall = $time;
        @(negedge hs); t_hfall = $time;
        line_px = (t_hfall - t_prev_hfall) / 40;           // 40 ns per pixel
        check(line_px == 800, "a line is 800 pixels");
        @(posedge hs); hlow = ($time - t_hfall) / 40;
        check(hlow == 96, "hsync is low for 96 pixels");

        // ---- frame timing
        @(negedge vs); t_prev_hfall = $time;
        @(posedge vs); vlines = ($time - t_prev_hfall) / 40 / 800;
        check(vlines == 2, "vsync is low for 2 lines");
        @(negedge vs); frame_px = ($time - t_prev_hfall) / 40;
        check(frame_px == 800 * 525, "a frame is 525 lines");

        // ---- black outside the picture: during vsync and its back porch
        black_ok = 1'b1;
        for (i = 0; i < 800 * 30; i = i + 1) begin
            @(posedge clk); while (!sample_now(0)) @(posedge clk);
            if ({r, g, b} != 12'h000) black_ok = 1'b0;
        end
        check(black_ok, "nothing is driven outside the visible area");

        // ---- visible line 4 (title bar, row 0) and line 23 (progress bar)
        // the frame's line 0 starts 35 lines after the vsync fall
        @(negedge vs);
        for (k = 0; k < 35 + 4; k = k + 1) @(negedge hs);
        repeat (144 - 0) begin @(posedge clk); while (!sample_now(0)) @(posedge clk); end   // 96 sync + 48 back porch
        for (i = 0; i < 640; i = i + 1) begin
            @(posedge clk); while (!sample_now(0)) @(posedge clk);
            px[i] = {r, g, b};
        end
        check(px[630] == 12'h126, "title bar is navy at its right end");
        check(px[0] == 12'h126 || px[0] == 12'hFFF, "title bar starts at the left edge");
        k = 0; for (i = 12; i < 348; i = i + 1) if (px[i] == 12'hFFF) k = k + 1;
        check(k > 50, "title text drawn in white from the character RAM");

        for (k = 0; k < 23 - 4; k = k + 1) @(negedge hs);
        repeat (144) begin @(posedge clk); while (!sample_now(0)) @(posedge clk); end
        for (i = 0; i < 640; i = i + 1) begin
            @(posedge clk); while (!sample_now(0)) @(posedge clk);
            px[i] = {r, g, b};
        end
        check(px[100] == 12'hFC0 && px[319] == 12'hFC0, "progress bar filled up to half (x 12..319)");
        check(px[320] == 12'h222 && px[600] == 12'h222, "rest of the progress bar dark");
        check(px[5] == 12'h000, "nothing left of the progress bar");

        if (n_fail == 0) $display("PASS: tb_vga_screen (%0d checks)", n_pass);
        else             $display("FAIL: tb_vga_screen (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
