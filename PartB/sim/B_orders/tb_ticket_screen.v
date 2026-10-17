`timescale 1ns / 1ps
`include "trading_defs.vh"
`include "ticket_layout.vh"

// tb_ticket_screen: drives ticket_screen directly into three states, checks
// a few key pixels, and writes one frame dump per state (96x64 RGB565, one
// hex value per line, row-major). tools/hex2png.py turns them into PNGs.
//   ticket_frame.hex       MKT BUY, focus qty, after a fill
//   ticket_frame_lmt.hex   LMT SELL, focus trig, reject showing
//   ticket_frame_stp.hex   STP BUY, focus submit, pending order placed
module tb_ticket_screen;
    reg clk = 0;
    always #5 clk = ~clk;

    reg        sys_reset = 1;
    reg [6:0]  pix_x = 0;
    reg [5:0]  pix_y = 0;
    reg [1:0]  sel_stock = 1;            // TEK
    reg [15:0] bid = 12325, ask = 12335;
    reg        side = `SIDE_BUY;
    reg [1:0]  otype = `OT_MKT;
    reg [7:0]  qty = 10;
    reg [15:0] trig = 12330;
    reg [1:0]  focus = 0;
    reg [3:0]  pending_count = 3;
    reg        fill = 0, fill_side = 0;
    reg [7:0]  fill_qty = 0;
    reg [15:0] fill_price = 0;
    reg        placed = 0, placed_side = 0;
    reg [1:0]  placed_type = 0;
    reg [7:0]  placed_qty = 0;
    reg [15:0] placed_trig = 0;
    reg        reject = 0;
    reg [2:0]  reject_code = 0;
    wire [15:0] ticket_pix;

    ticket_screen #(.REJ_SHOW_CYCLES(100000)) dut (
        .clk(clk), .sys_reset(sys_reset), .pix_x(pix_x), .pix_y(pix_y),
        .sel_stock(sel_stock), .bid(bid), .ask(ask), .side(side), .otype(otype),
        .qty(qty), .trig(trig), .focus(focus), .pending_count(pending_count),
        .fill(fill), .fill_side(fill_side), .fill_qty(fill_qty), .fill_price(fill_price),
        .placed(placed), .placed_side(placed_side), .placed_type(placed_type),
        .placed_qty(placed_qty), .placed_trig(placed_trig),
        .reject(reject), .reject_code(reject_code), .ticket_pix(ticket_pix)
    );

    integer n_pass = 0, n_fail = 0;

    task check;
        input          cond;
        input [8*56:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("FAIL: %0s (t=%0t)", name, $time);
            end
        end
    endtask

    task step;
        input integer n;
        begin
            repeat (n) @(posedge clk);
            #1;
        end
    endtask

    // px: colour at one pixel; cnt: pixels of one colour in a rectangle
    reg [15:0] px;
    integer    cnt;

    task px_at;
        input [6:0] x;
        input [5:0] y;
        begin
            pix_x = x; pix_y = y; #1;
            px = ticket_pix;
        end
    endtask

    task count_col;
        input [6:0]  x0, x1;
        input [5:0]  y0, y1;
        input [15:0] col;
        integer x, y;
        begin
            cnt = 0;
            for (y = y0; y <= y1; y = y + 1)
                for (x = x0; x <= x1; x = x + 1) begin
                    pix_x = x; pix_y = y; #1;
                    if (ticket_pix == col) cnt = cnt + 1;
                end
        end
    endtask

    task dump;
        input [8*32:1] fname;
        integer f, x, y;
        begin
            f = $fopen(fname, "w");
            for (y = 0; y < 64; y = y + 1)
                for (x = 0; x < 96; x = x + 1) begin
                    pix_x = x; pix_y = y; #1;
                    $fdisplay(f, "%04h", ticket_pix);
                end
            $fclose(f);
        end
    endtask

    task pulse_fill;
        input        sd;
        input [7:0]  q;
        input [15:0] p;
        begin
            fill_side = sd; fill_qty = q; fill_price = p;
            fill = 1; step(1); fill = 0;
        end
    endtask

    initial begin
        step(3);
        sys_reset = 0;

        // ---------------------------------------------------- frame 1
        pulse_fill(`SIDE_BUY, 10, 12335);
        step(300);                                 // BCD refresh: ~6 x 18 clocks
        check(dut.bcd_bid == 20'h12325 && dut.bcd_ask == 20'h12335, "F1 bid/ask BCD");
        check(dut.bcd_qty == 20'h00010 && dut.bcd_mpx == 20'h12335, "F1 qty/fill BCD");
        count_col(0, 95, 0, 5, 16'hFFFF); check(cnt == 0, "F1 tab bar rows left black");
        px_at(3, 16); check(px == 16'h07E0, "F1 BUY selected -> green fill");
        px_at(`TK_SELL_X0, 20); check(px == 16'h4208, "F1 SELL unselected -> grey edge");
        px_at(40, 20); check(px == 16'h0000, "F1 SELL interior black");
        px_at(24, 44); check(px == 16'h001F, "F1 SUBMIT blue");
        count_col(0, 63, 55, 59, 16'h07E0); check(cnt > 20, "F1 fill message green");
        count_col(20, 31, 27, 31, 16'hFFE0); check(cnt > 5, "F1 focused qty yellow");
        count_col(0, 60, 35, 39, 16'hFFFF); check(cnt == 0, "F1 TRG line dimmed (MKT)");
        dump("ticket_frame.hex");

        // ---------------------------------------------------- frame 2
        side = `SIDE_SELL; otype = `OT_LMT; focus = 1; trig = 12000; qty = 25;
        sel_stock = 3; bid = 1225; ask = 1235;
        reject_code = `RJ_NO_CASH; reject = 1; step(1); reject = 0;
        step(300);
        px_at(40, 16); check(px == 16'hF800, "F2 SELL selected -> red fill");
        px_at(3, 16); check(px == 16'h0000, "F2 BUY interior black");
        count_col(0, 63, 55, 59, 16'hF800); check(cnt > 20, "F2 reject message red");
        count_col(20, 43, 35, 39, 16'hFFE0); check(cnt > 5, "F2 focused trig yellow");
        dump("ticket_frame_lmt.hex");

        // reject times out back to the last fill
        step(100000);
        count_col(0, 63, 55, 59, 16'hF800); check(cnt == 0,  "F2 reject clears after timeout");
        count_col(0, 63, 55, 59, 16'h07E0); check(cnt > 20,  "F2 status falls back to last fill");

        // ---------------------------------------------------- frame 3
        side = `SIDE_BUY; otype = `OT_STP; focus = 2; sel_stock = 0; bid = 9995; ask = 10005;
        trig = 10500; qty = 255; pending_count = 4;
        placed_side = `SIDE_BUY; placed_type = `OT_STP; placed_qty = 255; placed_trig = 10500;
        placed = 1; step(1); placed = 0;
        step(300);
        px_at(`TK_SUB_X0, `TK_SUB_Y0); check(px == 16'hFFE0, "F3 SUBMIT focused -> yellow edge");
        count_col(0, 63, 55, 59, 16'hFFFF); check(cnt > 20, "F3 placed message white");
        dump("ticket_frame_stp.hex");

        if (n_fail == 0) $display("PASS: tb_ticket_screen (%0d checks)", n_pass);
        else             $display("FAIL: tb_ticket_screen (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
