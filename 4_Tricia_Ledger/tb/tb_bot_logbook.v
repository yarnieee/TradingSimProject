`timescale 1ns / 1ps

// tb_bot_logbook: each bot's last 5 trades, newest first; a moving-average
// trade on the same clock as a bot_squad trade is not lost; the feed of all the
// bots' last 8 trades, newest first.
module tb_bot_logbook;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg [7:0]  day = 8'd1;
    reg        a_trade = 1'b0, a_side = 1'b0, q_trade = 1'b0, q_side = 1'b0;
    reg [1:0]  a_stock = 2'd0, q_bot = 2'd0, q_stock = 2'd0;
    reg [15:0] a_price = 16'd0, q_price = 16'd0;
    reg [2:0]  sel = 3'd0;
    wire [4:0]  lv, ls;
    wire [9:0]  lk;
    wire [79:0] lp;
    wire [39:0] ld;
    wire [7:0]   fv, fs;
    wire [23:0]  fb;
    wire [15:0]  fk;
    wire [127:0] fp;
    wire [63:0]  fd;

    bot_logbook dut (
        .clk(clk), .rst(rst), .day(day),
        .a_trade(a_trade), .a_side(a_side), .a_stock(a_stock), .a_price(a_price),
        .q_trade(q_trade), .q_bot(q_bot), .q_side(q_side), .q_stock(q_stock), .q_price(q_price),
        .sel(sel),
        .log_valid(lv), .log_side(ls), .log_stock(lk), .log_price(lp), .log_day(ld),
        .feed_valid(fv), .feed_bot(fb), .feed_side(fs), .feed_stock(fk), .feed_price(fp), .feed_day(fd)
    );

    integer n_pass = 0, n_fail = 0, t;
    task check;
        input          cond;
        input [8*64:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s", name); end
        end
    endtask

    task q_pulse;            // one bot_squad trade
        input [1:0] bot; input side; input [1:0] stock; input [15:0] price;
        begin
            @(negedge clk);
            q_trade = 1'b1; q_bot = bot; q_side = side; q_stock = stock; q_price = price;
            @(negedge clk);
            q_trade = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk); rst = 1'b0;
        repeat (10) @(posedge clk); #1;
        check(lv == 5'd0, "empty after reset");

        // bot 2 (bot_squad bot 1) trades 7 times: prices 101..107
        for (t = 1; t <= 7; t = t + 1) begin
            day = t;
            q_pulse(2'd1, t[0], t[1:0], 16'd100 + t);
        end
        sel = 3'd2;
        repeat (12) @(posedge clk); #1;
        check(lv == 5'b11111, "five entries shown once there are more than five");
        check(lp[15:0] == 16'd107 && lp[31:16] == 16'd106 && lp[79:64] == 16'd103, "newest first, last five");
        check(ld[7:0] == 8'd7 && ls[0] == 1'b1 && lk[1:0] == 2'd3, "day, side and stock of the newest");
        check(fv == 8'b0111_1111 && fp[15:0] == 16'd107 && fp[111:96] == 16'd101 && fb[2:0] == 3'd2,
              "feed: seven trades, newest first, from bot 2");
        check(fd[7:0] == 8'd7 && fs[0] == 1'b1 && fk[1:0] == 2'd3 && fd[55:48] == 8'd1, "feed: day, side, stock");

        // the moving-average bot and bot 4 on the same clock
        @(negedge clk);
        a_trade = 1'b1; a_side = 1'b1; a_stock = 2'd2; a_price = 16'd555;
        q_trade = 1'b1; q_bot = 2'd3; q_side = 1'b0; q_stock = 2'd1; q_price = 16'd777;
        @(negedge clk);
        a_trade = 1'b0; q_trade = 1'b0;
        sel = 3'd0;
        repeat (12) @(posedge clk); #1;
        check(lv == 5'b00001 && lp[15:0] == 16'd555 && ls[0] && lk[1:0] == 2'd2, "the moving-average trade is kept");
        sel = 3'd4;
        repeat (12) @(posedge clk); #1;
        check(lv == 5'b00001 && lp[15:0] == 16'd777, "and so is the bot_squad trade");
        sel = 3'd1;
        repeat (12) @(posedge clk); #1;
        check(lv == 5'b00000, "a bot that has not traded shows no entries");
        // feed: bot_squad's trade (bot 4) then the waiting moving-average one (bot 0) on top
        check(fv == 8'hFF && fb[2:0] == 3'd0 && fp[15:0] == 16'd555 && fb[5:3] == 3'd4 && fp[31:16] == 16'd777
              && fp[47:32] == 16'd107 && fp[127:112] == 16'd102, "feed: all the bots, newest first, the oldest dropped");

        @(negedge clk); rst = 1'b1; @(negedge clk); rst = 1'b0; sel = 3'd2;
        repeat (12) @(posedge clk); #1;
        check(lv == 5'd0, "a new game empties the logs");
        check(fv == 8'd0, "a new game empties the feed");

        if (n_fail == 0) $display("PASS: tb_bot_logbook (%0d checks)", n_pass);
        else             $display("FAIL: tb_bot_logbook (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
