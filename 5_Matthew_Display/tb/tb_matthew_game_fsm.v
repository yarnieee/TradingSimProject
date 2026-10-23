`timescale 1ns / 1ps

// tb_matthew_game_fsm: checks Matthew's game_fsm on its own (button pulses in,
// screen_state and quantity out). Covers every screen transition in the
// current flow and the quantity editor's digits and limits.
module tb_matthew_game_fsm;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    reg U = 0, D = 0, L = 0, R = 0, C = 0;
    wire [3:0]  screen_state;
    wire [13:0] quantity;

    game_fsm dut (.clk(clk), .rst(rst), .btnU(U), .btnD(D), .btnL(L), .btnR(R), .btnC(C),
                  .screen_state(screen_state), .quantity(quantity));

    localparam TITLE = 0, PORTFOLIO = 1, STOCKS = 2, SPECIFIC = 3, BUY = 4, SELL = 5,
               QUANTITY = 6, CONFIRM = 7;
    localparam BU = 0, BD = 1, BL = 2, BR = 3, BC = 4;

    integer n_pass = 0, n_fail = 0;
    task check;
        input          cond;
        input [8*72:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1;
                $display("FAIL: %0s (screen %0d, quantity %0d, t=%0t)", name, screen_state, quantity, $time); end
        end
    endtask

    task press;                     // one 1-clock pulse, as the debouncer edge gives
        input integer b;
        begin
            @(negedge clk);
            case (b) BU: U = 1; BD: D = 1; BL: L = 1; BR: R = 1; default: C = 1; endcase
            @(negedge clk);
            U = 0; D = 0; L = 0; R = 0; C = 0;
            repeat (3) @(negedge clk);
        end
    endtask
    task presses;
        input integer b;
        input integer n;
        integer k;
        begin for (k = 0; k < n; k = k + 1) press(b); end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);
        check(screen_state == TITLE, "starts on the title screen");
        press(BU); press(BL);
        check(screen_state == TITLE, "title ignores U and L");
        press(BC);
        check(screen_state == PORTFOLIO, "title --C--> portfolio");

        press(BC);
        check(screen_state == PORTFOLIO, "portfolio: C on the default item stays");
        press(BR); press(BC);
        check(screen_state == STOCKS, "portfolio --R, C--> stocks");

        press(BL); press(BC);
        check(screen_state == PORTFOLIO, "stocks: L selects back, C returns to portfolio");
        press(BR); press(BC);
        press(BD); press(BC);
        check(screen_state == SPECIFIC, "stocks --D, C--> stock 1's screen");

        press(BU); press(BR); press(BC);
        check(screen_state == STOCKS, "specific: U, R selects back-to-stocks");
        press(BD); press(BC);
        check(screen_state == SPECIFIC, "stocks --C--> specific again");
        press(BU); press(BC);
        check(screen_state == PORTFOLIO, "specific: U selects back-to-portfolio");

        // buy path with the quantity editor
        press(BR); press(BC); press(BD); press(BC);    // stocks, stock 0
        press(BC);
        check(screen_state == BUY, "specific --C--> buy screen (default item)");
        press(BR); press(BC);
        check(screen_state == QUANTITY && quantity == 0, "buy --R, C--> quantity screen, quantity reset to 0");
        press(BD);
        check(quantity == 0, "quantity cannot go below 0");
        presses(BU, 3);
        check(quantity == 3, "U x3 on the ones digit: 3");
        press(BL); presses(BU, 2);
        check(quantity == 23, "L to tens, U x2: 23");
        press(BL); press(BL); presses(BU, 9);
        check(quantity == 9023, "thousands digit x9: 9023");
        press(BU);
        check(quantity == 9023, "thousands cannot push past 9999");
        press(BR); press(BR); presses(BU, 9);
        check(quantity == 9113, "back to tens, U x9: 9113");
        press(BR); presses(BU, 9);
        check(quantity == 9122, "ones digit carries: 9122");
        press(BC);
        check(screen_state == BUY && quantity == 9122, "quantity --C--> back to buy, quantity kept");
        press(BR); press(BR); press(BC);
        check(screen_state == CONFIRM, "buy --R, R, C--> confirm");
        press(BC);
        check(screen_state == PORTFOLIO && quantity == 0, "confirm --C--> portfolio and reset quantity");

        // sell path
        press(BR); press(BC); press(BD); press(BC);    // stocks, stock 0
        press(BR); press(BC);
        check(screen_state == SELL, "specific --R, C--> sell screen");
        press(BR); press(BC);
        check(screen_state == QUANTITY && quantity == 0, "sell --R, C--> quantity, reset to 0");
        presses(BU, 5); press(BC);
        check(screen_state == SELL && quantity == 5, "quantity 5 --C--> back to sell");
        press(BL); press(BC);
        check(screen_state == SPECIFIC, "sell: back item returns to the stock screen");

        rst = 1; @(negedge clk); rst = 0; @(negedge clk);
        check(screen_state == TITLE && quantity == 0, "reset returns to title, quantity 0");

        if (n_fail == 0) $display("PASS: tb_matthew_game_fsm (%0d checks)", n_pass);
        else             $display("FAIL: tb_matthew_game_fsm (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
