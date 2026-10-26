`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_matthew_game_fsm: checks Matthew's game_fsm on its own (button pulses in,
// screen_state and quantity out). Covers every screen transition in the
// current flow and the quantity editor's digits and limits.
module tb_matthew_game_fsm;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    reg U = 0, D = 0, L = 0, R = 0, C = 0;
    reg final_day_reached = 0;
    reg order_fill = 0, order_reject = 0;
    reg [2:0] order_reject_code = 0;
    reg order_valid = 1;
    reg [2:0] validation_code = `RJ_NONE;
    wire [3:0]  screen_state;
    wire [13:0] quantity;
    wire [2:0]  selected_stock;
    wire [3:0]  menu_selection;
    wire        trade_side;

    game_fsm dut (.clk(clk), .rst(rst), .btnU(U), .btnD(D), .btnL(L), .btnR(R), .btnC(C),
                  .final_day_reached(final_day_reached),
                  .order_fill(order_fill), .order_reject(order_reject),
                  .order_reject_code(order_reject_code),
                  .order_valid(order_valid), .validation_code(validation_code),
                  .screen_state(screen_state), .quantity(quantity),
                  .selected_stock(selected_stock), .menu_selection(menu_selection),
                  .trade_side(trade_side));

    localparam TITLE = `UI_TITLE, PORTFOLIO = `UI_PORTFOLIO,
               STOCKS = `UI_STOCKS, SPECIFIC = `UI_SPECIFIC,
               BUY = `UI_BUY_STOCK, SELL = `UI_SELL_STOCK,
               QUANTITY = `UI_QUANTITY, ORDER_REVIEW = `UI_ORDER_REVIEW,
               ORDER_RESULT = `UI_ORDER_RESULT, TRADE_RESULT = `UI_TRADE_RESULT,
               GAME_END = `UI_GAME_END;
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
        check(screen_state == SPECIFIC && selected_stock == 0,
              "stocks --D, C--> AMD screen with stock code 0");

        press(BU); press(BR); press(BC);
        check(screen_state == STOCKS && menu_selection == 4'd2,
              "specific: returning to stocks preserves the AMD cursor");
        press(BD); press(BC);
        check(screen_state == SPECIFIC && selected_stock == 1,
              "stocks --D, C--> AVGO screen with stock code 1");

        press(BU); press(BR); press(BC);
        check(screen_state == STOCKS && menu_selection == 4'd3,
              "AVGO returns to the stock list with its cursor preserved");
        press(BD); press(BC);
        check(screen_state == SPECIFIC && selected_stock == 2,
              "stocks --D, C--> NVDA screen with stock code 2");

        press(BU); press(BR); press(BC);
        check(screen_state == STOCKS && menu_selection == 4'd4,
              "NVDA returns to the stock list with its cursor preserved");
        press(BD); press(BC);
        check(screen_state == SPECIFIC && selected_stock == 3,
              "stocks --D, C--> GME screen with stock code 3");

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
        check(screen_state == ORDER_REVIEW, "buy --R, R, C--> order review");
        press(BC);
        check(screen_state == ORDER_RESULT, "order review --C--> order result");
        order_fill = 1;
        @(negedge clk);
        order_fill = 0;
        @(negedge clk);
        check(screen_state == TRADE_RESULT, "order fill --> trade result");
        press(BC);
        check(screen_state == PORTFOLIO && quantity == 0, "trade result --C--> portfolio and reset quantity");

        // sell path
        press(BR); press(BC); press(BD); press(BC);    // stocks, stock 0
        press(BR); press(BC);
        check(screen_state == SELL && trade_side == 1'b1,
              "specific --R, C--> sell screen with sell side latched");
        press(BR); press(BC);
        check(screen_state == QUANTITY && quantity == 0, "sell --R, C--> quantity, reset to 0");
        presses(BU, 5); press(BC);
        check(screen_state == SELL && quantity == 5, "quantity 5 --C--> back to sell");
        press(BL); press(BC);
        check(screen_state == SPECIFIC, "sell: back item returns to the stock screen");

        rst = 1; @(negedge clk); rst = 0; @(negedge clk);
        check(screen_state == TITLE && quantity == 0, "reset returns to title, quantity 0");

        // The final-day pulse is accepted from an active screen and the
        // game-end screen remains terminal even if a button is pressed.
        press(BC);
        check(screen_state == PORTFOLIO, "restart reaches portfolio before final-day test");
        final_day_reached = 1;
        @(negedge clk);
        final_day_reached = 0;
        @(negedge clk);
        check(screen_state == GAME_END, "final trading day enters game-end screen");
        press(BC);
        check(screen_state == GAME_END, "game-end screen is terminal");

        if (n_fail == 0) $display("PASS: tb_matthew_game_fsm (%0d checks)", n_pass);
        else             $display("FAIL: tb_matthew_game_fsm (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
