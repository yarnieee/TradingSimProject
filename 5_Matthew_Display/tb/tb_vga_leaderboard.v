`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_vga_leaderboard: the VGA leaderboard rows (21-26) list you and the bots in
// place order, 1st at the top: each row shows its place, the right net worth
// field and name, and your row keeps its highlight wherever it is.
// Also the market rows (3-7): price, 30-day change in $ and in %.
module tb_vga_leaderboard;
    reg  [4:0]  row = 5'd0;
    reg  [6:0]  col = 7'd0;
    reg  [17:0] order;
    reg  [3:0]  scr = `UI_PORTFOLIO;
    reg  [7:0]  c1;                      // the second letter of a name
    wire [6:0]  num_f;
    wire [7:0]  ch;
    wire [3:0]  fg, bg;
    // the fields the market row reads: AMD $207.02, -$12.34, -5.63%
    wire [32:0] num_rd = (num_f == `DN_PX0)  ? {1'b0, 32'h00020702} :
                         (num_f == `DN_CHG0) ? {1'b1, 32'h00001234} :
                         (num_f == `DN_PCT0) ? {1'b1, 32'h00000563} : 33'd0;
    wire [`DN_N-1:0] zero = ~((`DN_N'd1 << `DN_PX0) | (`DN_N'd1 << `DN_CHG0) | (`DN_N'd1 << `DN_PCT0));

    vga_cells dut (
        .row(row), .col(col),
        .screen_state(scr), .menu_selection(4'd0), .selected_stock(3'd0),
        .trade_side(1'b0), .trade_result_success(1'b0), .trade_result_placed(1'b0),
        .trade_result_code(3'd0), .order_valid(1'b1), .validation_code(3'd0),
        .order_type(`OT_MKT), .order_brk(`BRK_OFF), .order_dist(2'd0),
        .oled_bot_view(1'b0), .orders_view(1'b0), .bot_sel(3'd0), .order(order),
        .go_blink(1'b0), .go_results(1'b0), .up(4'd0),
        .num_f(num_f), .num_rd(num_rd), .zero(zero),
        .book_valid(8'd0), .book_side(8'd0), .book_stock(16'd0), .book_type(16'd0), .book_leg(8'd0), .feed_valid(8'd0), .feed_bot(24'd0), .feed_side(8'd0), .feed_stock(16'd0),
        .ch(ch), .fg(fg), .bg(bg)
    );

    integer n_pass = 0, n_fail = 0, p, e;
    task check;
        input          cond;
        input [8*64:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s (place %0d)", name, p + 1); end
        end
    endtask

    // every row of the board for one standing
    task board;
        input [17:0] o;
        begin
            order = o;
            for (p = 0; p < 6; p = p + 1) begin
                e = o[3*p +: 3];
                row = 5'd21 + p;
                col = 7'd2; #1;                                      // place digit
                check(ch == "0" + p + 1, "rows go 1st to 6th");
                col = 7'd15; #1;                                     // net worth
                check(num_f == ((e == 0) ? `DN_NET : `DN_LBNET0 + e - 1), "row shows that entry's net worth");
                col = 7'd27; #1;                                     // return
                check(num_f == ((e == 0) ? `DN_NETPNL : `DN_LBPNL0 + e - 1), "row shows that entry's return");
                col = 7'd5; #1; c1 = ch;                             // name, first two letters
                col = 7'd4; #1;
                check({ch, c1} == ((e == 0) ? "YO" : (e == 1) ? "MA" : (e == 2) ? "OV" :
                                   (e == 3) ? "MO" : (e == 4) ? "AV" : "SL"), "row shows that entry's name");
                check((bg == 4'd12) == (e == 0), "only your row is highlighted");
            end
        end
    endtask

    // the text of cells first..last of the left panel on one row
    reg [8*34:1] txt;
    integer c;
    task left_text;
        input [4:0] r; input integer first, last;
        begin
            txt = 0;
            for (c = first; c <= last; c = c + 1) begin
                row = r; col = c + 1; #1;
                txt = {txt[8*33:1], ch};
            end
        end
    endtask

    initial begin
        p = 0;
        left_text(5'd3, 0, 33);
        check(txt == "  STOCK   PRICE    30-DAY CHANGE  ", "market header");
        left_text(5'd4, 7, 14);  check(txt[64:1] == " $207.02", "market: price");
        left_text(5'd4, 16, 23); check(txt[64:1] == " -$12.34", "market: 30-day change in $");
        left_text(5'd4, 26, 33); check(txt[64:1] == "  -5.63%", "market: 30-day change in %");
        row = 5'd4; col = 7'd26; #1; check(ch == 8'h81, "market: down arrow");
        row = 5'd4; col = 7'd30; #1; check(ch == "5" && fg == 4'd5, "market: a fall in % shown red");
        board({3'd5, 3'd4, 3'd3, 3'd2, 3'd1, 3'd0});   // you 1st, then bots 0..4
        board({3'd0, 3'd3, 3'd1, 3'd4, 3'd2, 3'd5});   // bot 4 1st ... you 6th
        board({3'd3, 3'd1, 3'd5, 3'd0, 3'd4, 3'd2});   // bot 1 1st, you 3rd
        if (n_fail == 0) $display("PASS: tb_vga_leaderboard (%0d checks)", n_pass);
        else             $display("FAIL: tb_vga_leaderboard (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
