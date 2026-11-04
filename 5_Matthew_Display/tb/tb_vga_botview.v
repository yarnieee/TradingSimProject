`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_vga_botview: the monitor's two notification rows (28-29: the bots' latest
// trades, newest on top) on every screen, and the bot view (sw15 up): LATEST
// TRADES in place of the chart, the chosen bot in place of PENDING ORDERS, the
// rest unchanged, purple bars and rows. Feed here: MOMENTUM buys NVDA at $451.41
// on day 45 (newest), AVG DOWN sells GME at $12.34 on day 44.
module tb_vga_botview;
    reg  [4:0]  row = 5'd0;
    reg  [6:0]  col = 7'd0;
    reg         bv = 1'b0;
    reg  [7:0]  fv = 8'b0000_0011;
    wire [6:0]  num_f;
    wire [7:0]  ch;
    wire [3:0]  fg, bg;
    // the fields these rows read
    wire [32:0] num_rd = (num_f == `DN_FDAY0)     ? {1'b0, 32'h00000045} :
                         (num_f == `DN_FDAY0 + 1) ? {1'b0, 32'h00000044} :
                         (num_f == `DN_FPX0)      ? {1'b0, 32'h00045141} :
                         (num_f == `DN_FPX0 + 1)  ? {1'b0, 32'h00001234} :
                         (num_f == `DN_BNET)      ? {1'b0, 32'h01234567} :
                         (num_f == `DN_BNETPNL)   ? {1'b0, 32'h00234567} :
                         (num_f == `DN_BPOS0 + 2) ? {1'b0, 32'h00000020} : 33'd0;
    wire [`DN_N-1:0] zero = ~((`DN_N'd1 << (`DN_BPOS0 + 2)) | (`DN_N'd1 << `DN_BNET) | (`DN_N'd1 << `DN_BNETPNL));

    vga_cells dut (
        .row(row), .col(col),
        .screen_state(`UI_PORTFOLIO), .menu_selection(4'd0), .selected_stock(3'd1),
        .trade_side(1'b0), .trade_result_success(1'b0), .trade_result_placed(1'b0),
        .trade_result_code(3'd0), .order_valid(1'b1), .validation_code(3'd0),
        .order_type(`OT_MKT), .order_brk(`BRK_OFF), .order_dist(2'd0),
        .oled_bot_view(bv), .orders_view(1'b0), .bot_sel(3'd2), .order(18'o543210),
        .go_blink(1'b0), .go_results(1'b0), .up(4'd0),
        .num_f(num_f), .num_rd(num_rd), .zero(zero),
        .book_valid(8'd0), .book_side(8'd0), .book_stock(16'd0), .book_type(16'd0), .book_leg(8'd0),
        .feed_valid(fv), .feed_bot({18'd0, 3'd3, 3'd2}), .feed_side(8'b0000_0010), .feed_stock({12'd0, 2'd3, 2'd2}), .quantity_cursor(2'd0), .orders_sel(3'd0),
        .ch(ch), .fg(fg), .bg(bg)
    );

    localparam [3:0] K_GREEN = 4'd4, K_RED = 4'd5, K_NAVY = 4'd7, K_PANEL = 4'd11, K_ROW = 4'd12,
                     K_PURPLE = 4'd13, K_PROW = 4'd14;

    integer n_pass = 0, n_fail = 0;
    reg [8*69:1] txt;
    integer c;
    task check;
        input cond; input [8*72:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s  [%0s]", name, txt); end
        end
    endtask

    // the text of cells first..last on one row (at most 69)
    task text;
        input [4:0] r; input integer first, last;
        begin
            txt = 0;
            for (c = first; c <= last; c = c + 1) begin
                row = r; col = c; #1;
                txt = {txt[8*68:1], ch};
            end
        end
    endtask
    task at; input [4:0] r; input [6:0] cc; begin row = r; col = cc; #1; end endtask

    initial begin
        // ---------------- normal view: the notifications, the chart and the pending orders as before
        text(5'd28, 1, 64);
        check(txt[8*64:1] == "NEW DAY  45  MOMENTUM    BUYS  NVDA AT $451.41  RIDING THE RALLY",
              "row 28: the newest trade");
        at(5'd28, 7'd26); check(fg == K_GREEN && bg == K_NAVY, "row 28: BUYS green, the newest on a highlighted bar");
        text(5'd29, 1, 66);
        check(txt[8*66:1] == "    DAY  44  AVG DOWN    SELLS GME  AT  $12.34  TOOK ITS 5% PROFIT",
              "row 29: the one before");
        at(5'd29, 7'd26); check(fg == K_RED && bg == K_ROW, "row 29: SELLS red, a darker bar");
        text(5'd27, 1, 69); check(txt == {69{8'h20}}, "row 27: an empty gap above them");
        text(5'd9, 1, 18); check(txt[8*18:1] == " MCD  LAST 30 DAYS", "normal view: the chart header");
        text(5'd16, 36, 51); check(txt[8*16:1] == " PENDING ORDERS ", "normal view: PENDING ORDERS");
        at(5'd9, 7'd5); check(bg == K_PANEL, "normal view: no purple");
        text(5'd0, 32, 39); check(txt[8*8:1] != "BOT VIEW", "normal view: no BOT VIEW in the title");

        // ---------------- bot view
        bv = 1'b1;
        text(5'd0, 32, 39); check(txt[8*8:1] == "BOT VIEW", "bot view: BOT VIEW in the title bar");
        at(5'd0, 7'd5);  check(bg == K_PURPLE, "bot view: the title bar is purple");
        at(5'd2, 7'd5);  check(bg == K_PURPLE, "bot view: the panel bars are purple");
        at(5'd28, 7'd5); check(bg == K_PURPLE, "bot view: the newest notification is purple");
        at(5'd5, 7'd5);  check(bg == K_PROW, "bot view: the selected stock row is dark purple");
        text(5'd9, 1, 34);
        check(txt[8*34:1] == " LATEST TRADES            ALL BOTS", "bot view: LATEST TRADES instead of the chart");
        text(5'd11, 1, 34);
        check(txt[8*34:1] == "  45 MOMENTUM    BUY  NVDA $451.41", "bot view: the newest trade on top");
        at(5'd11, 7'd18); check(fg == K_GREEN && bg == K_PROW, "bot view: BUY green, the newest row highlighted");
        text(5'd12, 1, 34);
        check(txt[8*34:1] == "  44 AVG DOWN    SELL GME   $12.34", "bot view: then the one before");
        text(5'd13, 1, 34); check(txt[8*34:1] == {34{8'h20}}, "bot view: no more trades, empty rows");
        text(5'd16, 36, 69);
        check(txt[8*34:1] == " MOMENTUM              BTNL / BTNR", "bot view: the chosen bot instead of PENDING ORDERS");
        text(5'd17, 36, 69);
        check(txt[8*34:1] == "            WORTH        $12345.67", "bot view: its net worth (its picture at the left)");
        text(5'd20, 36, 69);
        check(txt[8*34:1] == "            RETURN         +23.45%", "bot view: its return");
        text(5'd21, 36, 69);
        check(txt[8*34:1] == "            BUYS AFTER 2 UP DAYS, ", "bot view: its strategy, line 1");
        text(5'd22, 36, 69);
        check(txt[8*34:1] == "            SELLS ON A DOWN DAY   ", "bot view: its strategy, line 2");
        text(5'd25, 36, 69);
        check(txt[8*34:1] == " NVDA            20          $0.00", "bot view: its holdings");
        text(5'd2, 36, 51); check(txt[8*16:1] == " YOUR PORTFOLIO ", "bot view: your portfolio stays");
        text(5'd20, 1, 14); check(txt[8*14:1] == " # LEADERBOARD", "bot view: the leaderboard stays");
        text(5'd28, 1, 12); check(txt[8*12:1] == "NEW DAY  45 ", "bot view: the notifications stay");

        // ---------------- no trades yet
        fv = 8'd0; bv = 1'b0;
        text(5'd28, 5, 21); check(txt[8*17:1] == "NO BOT TRADES YET", "no trades yet: says so");
        text(5'd29, 1, 69); check(txt == {69{8'h20}}, "no trades yet: the second row empty");

        if (n_fail == 0) $display("PASS: tb_vga_botview (%0d checks)", n_pass);
        else             $display("FAIL: tb_vga_botview (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
