`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_vga_gameover: the VGA GAME OVER screen. First a big GAME OVER that flashes
// (and nothing else), then GAME OVER at the top and the final results: 1st to
// 6th with place, name, net worth, profit / loss and return, and where you
// finished.
module tb_vga_gameover;
    reg  [4:0]  row = 5'd0;
    reg  [6:0]  col = 7'd0;
    reg  [17:0] order;
    reg         blink = 1'b1, results = 1'b0;
    reg  [32:0] num_rd = 33'd0;
    wire [6:0]  num_f;
    wire [7:0]  ch;
    wire [3:0]  fg, bg;

    vga_cells dut (
        .row(row), .col(col),
        .screen_state(`UI_GAME_END), .menu_selection(4'd0), .selected_stock(3'd0),
        .trade_side(1'b0), .trade_result_success(1'b0), .trade_result_placed(1'b0),
        .trade_result_code(3'd0), .order_valid(1'b1), .validation_code(3'd0),
        .order_type(`OT_MKT), .order_brk(`BRK_OFF), .order_dist(2'd0),
        .oled_bot_view(1'b0), .orders_view(1'b0), .bot_sel(3'd0), .order(order),
        .go_blink(blink), .go_results(results), .up(4'd0),
        .num_f(num_f), .num_rd(num_rd), .zero({`DN_N{1'b0}}),
        .book_valid(8'd0), .book_side(8'd0), .book_stock(16'd0), .book_type(16'd0), .book_leg(8'd0),
        .ch(ch), .fg(fg), .bg(bg)
    );

    localparam [3:0] K_BLACK = 4'd0, K_RED = 4'd5, K_ROW = 4'd12;

    integer n_pass = 0, n_fail = 0, p, e;
    task check;
        input          cond;
        input [8*64:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s (row %0d col %0d)", name, row, col); end
        end
    endtask

    task at;
        input [4:0] r; input [6:0] c;
        begin row = r; col = c; #1; end
    endtask

    // first two letters of an entry's name (MA BOT and MOMENTUM share the first)
    function [15:0] initial_of;
        input [2:0] e;
        initial_of = (e == 0) ? "YO" : (e == 1) ? "MA" : (e == 2) ? "OV" : (e == 3) ? "MO" : (e == 4) ? "AV" : "SL";
    endfunction
    reg [7:0] ch1;                     // the character one cell to the right
    task at2;
        input [4:0] r; input [6:0] c;
        begin row = r; col = c + 7'd1; #1; ch1 = ch; col = c; #1; end
    endtask

    // the results table and the line under it for one standing
    task results_for;
        input [17:0] o;
        input [2:0]  you;              // your place, 0 = 1st
        begin
            order = o;
            for (p = 0; p < 6; p = p + 1) begin
                e = o[3*p +: 3];
                at(5'd14 + p, 7'd6);
                check(ch == "0" + p + 1, "rows go 1st to 6th");
                at2(5'd14 + p, 7'd14);
                check({ch, ch1} == initial_of(e), "the name of who is in that place");
                check((bg == K_ROW) == (e == 0), "only your row is highlighted");
                at(5'd14 + p, 7'd30);
                check(num_f == ((e == 0) ? `DN_NET : `DN_LBNET0 + e - 1), "net worth field");
                at(5'd14 + p, 7'd50);
                check(num_f == ((e == 0) ? `DN_NETPNL : `DN_LBPNL0 + e - 1), "profit / loss field");
                at(5'd14 + p, 7'd60);
                check(num_f == ((e == 0) ? `DN_NETPNL : `DN_LBPNL0 + e - 1), "return field");
            end
            if (you == 0) begin
                at(5'd21, 7'd6);  check(ch == "Y", "YOU WIN! when you are 1st");
                at(5'd21, 7'd10); check(ch == "W", "YOU WIN! when you are 1st");
            end else begin
                at(5'd21, 7'd6);  check(ch == "Y", "YOU FINISHED ...");
                at(5'd21, 7'd19); check(ch == "1" + you, "... your place");
                at2(5'd21, 7'd39); check({ch, ch1} == initial_of(o[2:0]), "... and the winner");
            end
        end
    endtask

    initial begin
        order = {3'd0, 3'd3, 3'd1, 3'd4, 3'd2, 3'd5};   // bot 4 1st ... you 6th

        // ---- flashing: GAME OVER in rows 11-17, cols 9-61; nothing else
        blink = 1'b1;
        at(5'd11, 7'd10); check(bg == K_RED, "flash on: a dot of the G is lit");
        at(5'd11, 7'd9);  check(bg == K_BLACK, "the G's top-left corner is not");
        at(5'd17, 7'd61); check(bg == K_RED, "the R's last dot is lit");
        at(5'd14, 7'd36); check(bg == K_BLACK, "the gap between the words is dark");
        blink = 1'b0;
        at(5'd11, 7'd10); check(bg == K_BLACK, "flash off: the dot is dark");
        at(5'd14, 7'd6);  check(ch == " ", "no results while it flashes");
        at(5'd11, 7'd29); check(ch == " ", "no FINAL RESULTS while it flashes");

        // ---- results: GAME OVER moves up to rows 3-9 and stays lit
        results = 1'b1;
        at(5'd3, 7'd10);  check(bg == K_RED, "GAME OVER at the top");
        blink = 1'b1; #1;
        at(5'd3, 7'd10);  check(bg == K_RED, "and it stays lit");
        at(5'd11, 7'd10); check(bg != K_RED, "not in the middle any more");
        at(5'd11, 7'd29); check(ch == "F", "FINAL RESULTS");
        at(5'd13, 7'd6);  check(ch == "P", "header: PLACE");
        at(5'd13, 7'd59); check(ch == "R", "header: RETURN");

        results_for({3'd0, 3'd3, 3'd1, 3'd4, 3'd2, 3'd5}, 3'd5);   // bot 4 1st, you 6th
        results_for({3'd5, 3'd4, 3'd3, 3'd2, 3'd1, 3'd0}, 3'd0);   // you 1st
        results_for({3'd3, 3'd1, 3'd5, 3'd0, 3'd4, 3'd2}, 3'd2);   // bot 1 1st, you 3rd
        results_for({3'd2, 3'd0, 3'd5, 3'd1, 3'd4, 3'd3}, 3'd4);   // bot 2 1st, you 5th

        // ---- numbers: +$123.45 profit is +1.23% return
        num_rd = {1'b0, 32'h0001_2345};
        at(5'd14, 7'd53); check(ch == "5", "P/L last digit");
        at(5'd14, 7'd47); check(ch == "$", "P/L dollar sign");
        at(5'd14, 7'd46); check(ch == "+", "P/L sign");
        at(5'd14, 7'd63); check(ch == "3", "return 1.23: last digit");
        at(5'd14, 7'd61); check(ch == ".", "return 1.23: point");
        at(5'd14, 7'd60); check(ch == "1", "return 1.23: first digit");
        at(5'd14, 7'd59); check(ch == "+", "return sign");
        at(5'd14, 7'd64); check(ch == "%", "percent");
        num_rd = {1'b1, 32'h0000_5000};                              // -$50.00 = -0.50%
        at(5'd14, 7'd63); check(ch == "0" && fg == K_RED, "a loss is red");
        at(5'd14, 7'd59); check(ch == "-", "return -0.50: sign");

        if (n_fail == 0) $display("PASS: tb_vga_gameover (%0d checks)", n_pass);
        else             $display("FAIL: tb_vga_gameover (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
