`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_ticket_screen: drives ticket_screen directly into five states, checks
// key pixels of the text_grid layout (header bar, rows 1-6 at y 10, 19, 28,
// 37, 46, 55), and writes one frame dump per state (96x64 RGB565, one
// hex value per line, row-major). hex2png.py turns them into PNGs.
//   ticket_frame.hex         MKT BUY, focus qty, after a fill
//   ticket_frame_lmt.hex     LMT SELL, focus trig, reject showing
//   ticket_frame_stp.hex     STP BUY, focus submit, pending order placed
//   ticket_frame_sltp.hex    SL/TP 10% focused, then the stock field focused
//   ticket_frame_orders.hex  ORDERS view: an order, an SL/TP pair, empty slots
// Every state is also checked against the FLIP_180 version, pixel for pixel.
module tb_ticket_screen;
    reg clk = 0;
    always #5 clk = ~clk;

    reg        sys_reset = 1;
    reg [6:0]  pix_x = 0;
    reg [5:0]  pix_y = 0;
    reg [1:0]  stock = 1;                // MCD
    reg [15:0] bid = 12325, ask = 12335;
    reg        side = `SIDE_BUY;
    reg [1:0]  otype = `OT_MKT;
    reg [7:0]  qty = 10;
    reg [15:0] trig = 12330;
    reg [2:0]  focus = 0;
    reg [1:0]  brk = `BRK_OFF;
    reg [2:0]  ord_sel = 0;
    reg [3:0]  pending_count = 3;
    reg [7:0]   bk_valid = 0, bk_side = 0, bk_leg = 0;
    reg [15:0]  bk_stock = 0, bk_type = 0;
    reg [63:0]  bk_qty = 0;
    reg [127:0] bk_trig = 0;
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
    wire [15:0] ticket_pix_flip;

    ticket_screen #(.REJ_SHOW_CYCLES(100000)) dut (
        .clk(clk), .sys_reset(sys_reset), .pix_x(pix_x), .pix_y(pix_y),
        .stock(stock), .bid(bid), .ask(ask), .side(side), .otype(otype),
        .qty(qty), .trig(trig), .brk(brk), .ord_sel(ord_sel), .focus(focus),
        .pending_count(pending_count),
        .bk_valid(bk_valid), .bk_side(bk_side), .bk_stock(bk_stock), .bk_type(bk_type),
        .bk_qty(bk_qty), .bk_trig(bk_trig), .bk_leg(bk_leg),
        .fill(fill), .fill_side(fill_side), .fill_qty(fill_qty), .fill_price(fill_price),
        .placed(placed), .placed_side(placed_side), .placed_type(placed_type),
        .placed_qty(placed_qty), .placed_trig(placed_trig),
        .reject(reject), .reject_code(reject_code), .ticket_pix(ticket_pix)
    );

    // Same page with FLIP_180 = 1. Its OLED pixel (95 - x, 63 - y) must show
    // exactly what the normal one shows at (x, y).
    ticket_screen #(.REJ_SHOW_CYCLES(100000), .FLIP_180(1)) dut_flip (
        .clk(clk), .sys_reset(sys_reset), .pix_x(7'd95 - pix_x), .pix_y(6'd63 - pix_y),
        .stock(stock), .bid(bid), .ask(ask), .side(side), .otype(otype),
        .qty(qty), .trig(trig), .brk(brk), .ord_sel(ord_sel), .focus(focus),
        .pending_count(pending_count),
        .bk_valid(bk_valid), .bk_side(bk_side), .bk_stock(bk_stock), .bk_type(bk_type),
        .bk_qty(bk_qty), .bk_trig(bk_trig), .bk_leg(bk_leg),
        .fill(fill), .fill_side(fill_side), .fill_qty(fill_qty), .fill_price(fill_price),
        .placed(placed), .placed_side(placed_side), .placed_type(placed_type),
        .placed_qty(placed_qty), .placed_trig(placed_trig),
        .reject(reject), .reject_code(reject_code), .ticket_pix(ticket_pix_flip)
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

    task flip_check;
        input [8*56:1] name;
        integer x, y, bad;
        begin
            bad = 0;
            for (y = 0; y < 64; y = y + 1)
                for (x = 0; x < 96; x = x + 1) begin
                    pix_x = x; pix_y = y; #1;
                    if (ticket_pix_flip !== ticket_pix) bad = bad + 1;
                end
            check(bad == 0, name);
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

    localparam [15:0] HDR = 16'h0012, YEL = 16'hFFE0, GRN = 16'h07E0, RED = 16'hF8A2,
                      WHT = 16'hFFFF, BTN = 16'h3186, GRY = 16'h8C51;

    initial begin
        step(3);
        sys_reset = 0;

        // ---------------------------------------------------- frame 1: MKT BUY, focus QTY, after a fill
        pulse_fill(`SIDE_BUY, 10, 12335);
        step(400);                                 // BCD refresh: 14 values x ~18 clocks
        check(dut.bcd_bid == 20'h12325 && dut.bcd_ask == 20'h12335, "F1 bid/ask BCD");
        check(dut.bcd_qty == 20'h00010 && dut.bcd_mpx == 20'h12335, "F1 qty/fill BCD");
        px_at(95, 0);  check(px == HDR, "F1 header bar");
        count_col(42, 95, 2, 8, GRN);  check(cnt > 20, "F1 header shows FILLED in green");
        px_at(2, 28);  check(px == GRN, "F1 BUY cell green");
        px_at(90, 28); check(px == YEL, "F1 focused QTY row yellow");
        count_col(30, 95, 38, 44, WHT); check(cnt == 0, "F1 trigger grey for MKT");
        count_col(30, 95, 38, 44, GRY); check(cnt > 20, "F1 trigger shown in grey");
        px_at(1, 55);  check(px == BTN, "F1 SUBMIT button not focused");
        count_col(36, 53, 46, 54, GRY); check(cnt > 5, "F1 SL/TP OFF shown in grey");
        dump("ticket_frame.hex");
        flip_check("F1 FLIP_180: whole page rotated 180 degrees");

        // ---------------------------------------------------- frame 2: LMT SELL, focus TRG, reject
        side = `SIDE_SELL; otype = `OT_LMT; focus = 1; trig = 12000; qty = 25;
        stock = 3; bid = 1225; ask = 1235;
        reject_code = `RJ_NO_CASH; reject = 1; step(1); reject = 0;
        step(400);
        px_at(2, 28);  check(px == RED, "F2 SELL cell red");
        count_col(42, 95, 2, 8, RED);  check(cnt > 20, "F2 header shows the reject in red");
        px_at(40, 37); check(px == YEL, "F2 focused TRG row yellow");
        px_at(90, 28); check(px == 16'h0000, "F2 QTY no longer highlighted");
        dump("ticket_frame_lmt.hex");
        flip_check("F2 FLIP_180: whole page rotated 180 degrees");

        // reject times out back to the last fill
        step(100000);
        count_col(42, 95, 2, 8, RED); check(cnt == 0,  "F2 reject clears after timeout");
        count_col(42, 95, 2, 8, GRN); check(cnt > 20,  "F2 header falls back to the last fill");

        // ---------------------------------------------------- frame 3: STP BUY, focus SUBMIT, order placed
        side = `SIDE_BUY; otype = `OT_STP; focus = 2; stock = 0; bid = 9995; ask = 10005;
        trig = 10500; qty = 255; pending_count = 4;
        placed_side = `SIDE_BUY; placed_type = `OT_STP; placed_qty = 255; placed_trig = 10500;
        placed = 1; step(1); placed = 0;
        step(400);
        px_at(1, 55);  check(px == YEL, "F3 SUBMIT focused -> yellow");
        count_col(42, 95, 2, 8, WHT); check(cnt > 20, "F3 header shows PLACED in white");
        count_col(30, 95, 38, 44, WHT); check(cnt > 20, "F3 trigger white for a stop order");
        dump("ticket_frame_stp.hex");
        flip_check("F3 FLIP_180: whole page rotated 180 degrees");

        // ---------------------------------------------------- frame 4: SL/TP field, stock field
        focus = 3; brk = `BRK_10;
        step(10);
        px_at(1, 46);  check(px == YEL, "F4 SL/TP field focused -> yellow");
        dump("ticket_frame_sltp.hex");
        flip_check("F4 FLIP_180: whole page rotated 180 degrees");
        focus = 5;
        px_at(1, 10);  check(px == YEL, "F4 stock field focused -> yellow");
        px_at(1, 46);  check(px == 16'h0000, "F4 SL/TP no longer highlighted");

        // ---------------------------------------------------- frame 5: ORDERS view
        // slot 0: LMT BUY AMD 10 @ 120.00
        // slots 1, 2: SL/TP pair on MCD, 5 shares, SL 116.90 / TP 129.20
        bk_valid = 8'b0000_0111; bk_leg = 8'b0000_0110;
        bk_side  = 8'b0000_0110;
        bk_stock = {10'd0, 2'd1, 2'd1, 2'd0};
        bk_type  = {10'd0, `OT_LMT, `OT_STP, `OT_LMT};
        bk_qty   = {40'd0, 8'd5, 8'd5, 8'd10};
        bk_trig  = {80'd0, 16'd12920, 16'd11690, 16'd12000};
        pending_count = 3; ord_sel = 1; focus = 4;
        step(400);
        check(dut.bcd_st[0] == 20'h12000 && dut.bcd_st[1] == 20'h11690 && dut.bcd_st[2] == 20'h12920, "F5 slot price BCD");
        count_col(0, 35, 2, 8, WHT);    check(cnt > 30, "F5 header ORDERS");
        px_at(95, 19);                  check(px == YEL, "F5 cursor row (slot 2) yellow");
        px_at(95, 10);                  check(px == 16'h0000, "F5 other rows not highlighted");
        count_col(42, 53, 29, 35, GRN); check(cnt > 5,  "F5 take-profit code green (slot 3)");
        count_col(42, 53, 11, 17, GRN); check(cnt > 5,  "F5 buy limit code green (slot 1)");
        count_col(12, 17, 38, 44, GRY); check(cnt > 0,  "F5 empty slot shows a grey dash");
        count_col(18, 95, 38, 54, WHT); check(cnt == 0, "F5 empty slots have no text");
        count_col(0, 95, 55, 63, GRY);  check(cnt > 20, "F5 cancel hint on row 6");
        dump("ticket_frame_orders.hex");
        flip_check("F5 FLIP_180: whole page rotated 180 degrees");
        ord_sel = 6;                                  // scrolls: rows show slots 3-7
        #1;
        check(dut.first == 3'd2, "F5 list scrolls to keep the cursor visible");

        if (n_fail == 0) $display("PASS: tb_ticket_screen (%0d checks)", n_pass);
        else             $display("FAIL: tb_ticket_screen (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
