`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_vga_leaderboard: the VGA leaderboard rows (21-26) list you and the bots in
// place order, 1st at the top: each row shows its place, the right net worth
// field and name, and your row keeps its highlight wherever it is.
module tb_vga_leaderboard;
    reg  [4:0]  row = 5'd0;
    reg  [6:0]  col = 7'd0;
    reg  [17:0] order;
    reg  [7:0]  c1;                      // the second letter of a name
    wire [6:0]  num_f;
    wire [7:0]  ch;
    wire [3:0]  fg, bg;

    vga_cells dut (
        .row(row), .col(col),
        .screen_state(`UI_PORTFOLIO), .menu_selection(4'd0), .selected_stock(3'd0),
        .trade_side(1'b0), .trade_result_success(1'b0), .trade_result_placed(1'b0),
        .trade_result_code(3'd0), .order_valid(1'b1), .validation_code(3'd0),
        .order_type(`OT_MKT), .order_brk(`BRK_OFF), .order_dist(2'd0),
        .oled_bot_view(1'b0), .orders_view(1'b0), .bot_sel(3'd0), .order(order),
        .go_blink(1'b0), .go_results(1'b0), .up(4'd0),
        .num_f(num_f), .num_rd(33'd0), .zero({`DN_N{1'b1}}),
        .book_valid(8'd0), .book_side(8'd0), .book_stock(16'd0), .book_type(16'd0), .book_leg(8'd0),
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

    initial begin
        board({3'd5, 3'd4, 3'd3, 3'd2, 3'd1, 3'd0});   // you 1st, then bots 0..4
        board({3'd0, 3'd3, 3'd1, 3'd4, 3'd2, 3'd5});   // bot 4 1st ... you 6th
        board({3'd3, 3'd1, 3'd5, 3'd0, 3'd4, 3'd2});   // bot 1 1st, you 3rd
        if (n_fail == 0) $display("PASS: tb_vga_leaderboard (%0d checks)", n_pass);
        else             $display("FAIL: tb_vga_leaderboard (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
