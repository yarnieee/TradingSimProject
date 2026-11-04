`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_vga_controls: the right panel's TRADE CONTROLS (rows 16-26). While an order
// is being made (BUY / SELL, QUANTITY, ORDER REVIEW) it shows the order, the
// buttons for that screen, the switches and READY TO BUY / SELL (or why not);
// otherwise, and with sw14 up, PENDING ORDERS as before (sw15 up: the chosen bot,
// tb_vga_botview). Nothing outside
// the panel changes. Each screen's panel is printed as text.
module tb_vga_controls;
    reg  [4:0]  row = 5'd0;
    reg  [6:0]  col = 7'd0;
    reg  [3:0]  screen_state = `UI_PORTFOLIO;
    reg  [3:0]  menu_selection = 4'd0;
    reg  [2:0]  selected_stock = 3'd0;
    reg         trade_side = 1'b0;
    reg         order_valid = 1'b1;
    reg  [2:0]  validation_code = 3'd0;
    reg  [1:0]  order_type = `OT_MKT, order_brk = 2'd0, order_dist = 2'd0;
    reg         orders_view = 1'b0, oled_bot_view = 1'b0;
    // two pending orders: AMD buy limit (slot 1), GME stop-loss (slot 4)
    reg  [7:0]  book_valid = 8'b0001_0010;
    wire [6:0]  num_f;
    wire [7:0]  ch;
    wire [3:0]  fg, bg;
    // the fields the panel reads: 10 shares, $200.68 each, $2006.80 in all
    wire [32:0] num_rd = (num_f == `DN_QTY)    ? {1'b0, 32'h00000010} :
                         (num_f == `DN_ORDPX)  ? {1'b0, 32'h00020068} :
                         (num_f == `DN_ORDTOT) ? {1'b0, 32'h00200680} : 33'd0;
    wire [`DN_N-1:0] zero = ~((`DN_N'd1 << `DN_QTY) | (`DN_N'd1 << `DN_ORDPX) | (`DN_N'd1 << `DN_ORDTOT));

    vga_cells dut (
        .row(row), .col(col),
        .screen_state(screen_state), .menu_selection(menu_selection), .selected_stock(selected_stock),
        .trade_side(trade_side), .trade_result_success(1'b0), .trade_result_placed(1'b0),
        .trade_result_code(3'd0), .order_valid(order_valid), .validation_code(validation_code),
        .order_type(order_type), .order_brk(order_brk), .order_dist(order_dist),
        .oled_bot_view(oled_bot_view), .orders_view(orders_view), .bot_sel(3'd0), .order(18'o543210),
        .go_blink(1'b0), .go_results(1'b0), .up(4'd0),
        .num_f(num_f), .num_rd(num_rd), .zero(zero),
        .book_valid(book_valid), .book_side(8'b0001_0000), .book_stock(16'b0000_0011_0000_0000),
        .book_type({6'd0, `OT_STP, 4'd0, `OT_LMT, 2'd0}), .book_leg(8'b0001_0000), .feed_valid(8'd0), .feed_bot(24'd0), .feed_side(8'd0), .feed_stock(16'd0),
        .ch(ch), .fg(fg), .bg(bg)
    );

    integer n_pass = 0, n_fail = 0;
    task check;
        input          cond;
        input [8*64:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s", name); end
        end
    endtask

    // the 34 cells of the right panel on one row (cells 36-69)
    reg [8*34:1] txt;
    integer c, r;
    task right_text;
        input [4:0] rr;
        begin
            txt = 0;
            for (c = 0; c < 34; c = c + 1) begin
                row = rr; col = 7'd36 + c; #1;
                txt = {txt[8*33:1], ch};
            end
        end
    endtask

    // one look of the right panel
    task look;
        input [4:0] rr; input [6:0] cr;
        begin row = rr; col = 7'd36 + cr; #1; end
    endtask

    // print rows 16-26 of the right panel
    task show;
        input [8*48:1] name;
        begin
            $display("---- %0s", name);
            for (r = 16; r <= 26; r = r + 1) begin
                right_text(r);
                $display("%2d |%s|", r, txt);
            end
        end
    endtask

    // the screen outside the panel (rows 0-27; the panel's rows 16-26 skipped), as a checksum
    reg [31:0] sum;
    task outside;
        begin
            sum = 0;
            for (r = 0; r <= 27; r = r + 1)
                for (c = 0; c <= 70; c = c + 1)
                    if (!(r >= 16 && r <= 26 && c >= 36 && c <= 69)) begin
                        row = r; col = c; #1;
                        sum = {sum[30:0], sum[31]} ^ {ch, fg, bg, r[4:0], c[6:0], 8'd0};
                    end
        end
    endtask
    reg [31:0] sum_list;

    initial begin
        // ---- not making an order: PENDING ORDERS as before
        screen_state = `UI_SPECIFIC;
        show("SPECIFIC (not trading): pending orders");
        right_text(5'd16); check(txt[8*34:8*18+1] == " PENDING ORDERS ", "not trading: PENDING ORDERS header");
        look(5'd16, 7'd28); check(ch == "2", "not trading: 2 pending");
        right_text(5'd18); check(txt[8*34:8*29+1] == " AMD ", "not trading: 1st order is AMD");
        right_text(5'd19); check(txt[8*34:8*29+1] == " GME ", "not trading: 2nd order is GME");

        // ---- BUY: AMD, limit 5% below, SL/TP 5%, cursor on NEXT
        screen_state = `UI_BUY_STOCK; menu_selection = 4'd2; selected_stock = 3'd0; trade_side = 1'b0;
        order_type = `OT_LMT; order_dist = 2'd2; order_brk = 2'd2;
        show("BUY  AMD  LIMIT 5% BELOW  SL/TP 5%  (on NEXT)");
        right_text(5'd16); check(txt[8*34:8*18+1] == " TRADE CONTROLS ", "buy: TRADE CONTROLS header");
        check(txt[8*17:8*13+1] == "BUY ", "buy: BUY in the header");
        look(5'd16, 7'd17); check(fg == 4'd4, "buy: BUY green");
        look(5'd16, 7'd28); check(ch == "2", "buy: the pending count stays in the header");
        right_text(5'd17); check(txt[8*4:1] == " AMD", "buy: stock AMD at the right");
        look(5'd17, 7'd32); check(fg == 4'd3, "buy: the stock yellow");
        right_text(5'd18); check(txt[8*34:8*17+1] == " QUANTITY        " && txt[8*3:1] == " 10", "buy: quantity 10");
        right_text(5'd19); check(txt[8*16:1] == "LIMIT  5%  BELOW", "buy: limit 5% below");
        right_text(5'd20); check(txt[8*8:1] == " $200.68", "buy: price");
        right_text(5'd21); check(txt[8*9:1] == " $2006.80", "buy: total");
        right_text(5'd22); check(txt[8*34:8*28+1] == " SL/TP" && txt[8*3:1] == " 5%", "buy: SL/TP 5%");
        look(5'd23, 7'd26); check(bg == 4'd3 && fg == 4'd0, "buy: NEXT highlighted (black on yellow)");
        look(5'd23, 7'd13); check(bg == 4'd8, "buy: BACK not highlighted");
        look(5'd23, 7'd20); check(bg == 4'd8, "buy: QTY not highlighted");
        right_text(5'd26); check(txt[8*34:8*17+1] == " READY TO BUY AMD", "buy: READY TO BUY AMD");
        look(5'd26, 7'd1);  check(fg == 4'd4, "buy: READY green");
        look(5'd26, 7'd14); check(fg == 4'd3, "buy: its stock yellow");
        menu_selection = 4'd0; look(5'd23, 7'd13); check(bg == 4'd3, "buy: BACK highlighted when on it");
        menu_selection = 4'd1; look(5'd23, 7'd20); check(bg == 4'd3, "buy: QTY highlighted when on it");

        // the rest of the screen is the same as with the pending list (sw14 up shows the list)
        outside; sum_list = sum;
        orders_view = 1'b1; outside; orders_view = 1'b0;
        check(sum == sum_list, "nothing outside the panel changes (rows 0-27)");

        // ---- SELL: NVDA at market
        screen_state = `UI_SELL_STOCK; menu_selection = 4'd0; selected_stock = 3'd2; trade_side = 1'b1;
        order_type = `OT_MKT;
        show("SELL NVDA  MARKET  (on BACK)");
        right_text(5'd16); check(txt[8*17:8*13+1] == "SELL", "sell: SELL in the header");
        look(5'd16, 7'd17); check(fg == 4'd5, "sell: SELL red");
        right_text(5'd17); check(txt[8*4:1] == "NVDA", "sell: stock NVDA");
        right_text(5'd19); check(txt[8*6:1] == "MARKET", "sell: market order");
        right_text(5'd22); check(txt == {34{8'h20}}, "sell: no SL/TP row");
        right_text(5'd26); check(txt[8*34:8*15+1] == " READY TO SELL NVDA", "sell: READY TO SELL NVDA");
        look(5'd26, 7'd1); check(fg == 4'd5, "sell: READY red");

        // ---- an order that would be rejected says why instead
        order_valid = 1'b0; validation_code = `RJ_NO_POS;
        right_text(5'd26); check(txt[8*34:8*18+1] == " TOO FEW SHARES ", "rejected: the reason instead of READY");
        look(5'd26, 7'd1); check(fg == 4'd5, "rejected: the reason red");
        show("SELL NVDA  (too few shares)");
        order_valid = 1'b1;

        // ---- QUANTITY: the digit buttons
        screen_state = `UI_QUANTITY; trade_side = 1'b0; selected_stock = 3'd3;
        show("QUANTITY (buying GME)");
        right_text(5'd23); check(txt[8*34:8*5+1] == " BTNU/BTND   CHANGE THE DIGIT", "quantity: BTNU/BTND");
        right_text(5'd24); check(txt[8*34:8*6+1] == " BTNL/BTNR   MOVE TO A DIGIT", "quantity: BTNL/BTNR");
        right_text(5'd25); check(txt[8*34:8*17+1] == " BTNC        DONE", "quantity: BTNC done");

        // ---- ORDER REVIEW: send or go back
        screen_state = `UI_ORDER_REVIEW;
        show("ORDER REVIEW");
        right_text(5'd23); check(txt[8*34:8*7+1] == " BTNC        SEND THE ORDER", "review: BTNC sends");
        right_text(5'd24); check(txt[8*34:8*14+1] == " ANY OTHER   GO BACK", "review: any other button goes back");
        right_text(5'd25); check(txt[8*34:8*1+1] == " SW3:2 TYPE  SW5:4 SL/TP  SW7:6 %", "review: the switches");

        // ---- sw14 (cancel orders) or sw15 (bot view) up: the pending list, even while trading
        orders_view = 1'b1;
        right_text(5'd16); check(txt[8*34:8*18+1] == " PENDING ORDERS ", "sw14 up: PENDING ORDERS while trading");
        right_text(5'd18); check(txt[8*34:8*29+1] == " AMD ", "sw14 up: the orders listed");
        orders_view = 1'b0; oled_bot_view = 1'b1;
        right_text(5'd16); check(txt[8*34:8*18+1] == " MA BOT         ", "sw15 up: the chosen bot, even while trading");
        oled_bot_view = 1'b0;

        // ---- after the order: back to the list
        screen_state = `UI_TRADE_RESULT;
        right_text(5'd16); check(txt[8*34:8*18+1] == " PENDING ORDERS ", "result screen: PENDING ORDERS");
        book_valid = 8'd0; screen_state = `UI_PORTFOLIO;
        right_text(5'd18); check(txt[8*34:8*16+1] == " NO PENDING ORDERS", "no orders: NO PENDING ORDERS");

        if (n_fail == 0) $display("PASS: tb_vga_controls (%0d checks)", n_pass);
        else             $display("FAIL: tb_vga_controls (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
