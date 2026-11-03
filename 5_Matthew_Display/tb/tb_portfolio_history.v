`timescale 1ns / 1ps

// tb_portfolio_history: verifies that all four stock positions contribute to
// the live portfolio value and to the oldest-to-newest history bus.
module tb_portfolio_history;
    reg clk = 0;
    always #5 clk = ~clk;

    reg         rst = 1;
    reg         tick = 0;
    reg [31:0]  cash = 32'd1000;
    reg [9:0]   pos0 = 0, pos1 = 0, pos2 = 0, pos3 = 0;
    reg [15:0]  price0 = 0, price1 = 0, price2 = 0, price3 = 0;
    wire [31:0] portfolio_value;
    wire [959:0] portfolio_samples;

    portfolio_history dut (
        .clk(clk), .rst(rst), .tick(tick),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .portfolio_value(portfolio_value),
        .portfolio_samples(portfolio_samples)
    );

    integer n_pass = 0;
    integer n_fail = 0;

    task check;
        input         cond;
        input [8*72:1] name;
        begin
            if (cond === 1'b1)
                n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("FAIL: %0s (t=%0t)", name, $time);
            end
        end
    endtask

    // portfolio_value is registered: it follows its inputs 4 clocks later
    task settle; begin repeat (6) @(posedge clk); #1; end endtask

    initial begin
        #12;
        rst = 0;
        settle;
        check(portfolio_value == 32'd1000,
              "cash-only portfolio value is available after reset");
        check(portfolio_samples[31:0] == 32'd1000
              && portfolio_samples[959:928] == 32'd1000,
              "history initializes flat across its full range");

        // a fill first (cash 1000 -> 1100), so the history has distinct values
        cash = 32'd1100;
        settle;
        // a new trading day: prices move and tick pulses on the next clock (as at the top)
        @(negedge clk);
        pos0 = 10'd2; price0 = 16'd10;
        pos1 = 10'd3; price1 = 16'd20;
        pos2 = 10'd4; price2 = 16'd30;
        pos3 = 10'd5; price3 = 16'd40;
        @(negedge clk);
        tick = 1;
        @(negedge clk);
        tick = 0;
        settle;
        check(portfolio_value == 32'd1500,
              "portfolio value includes all four stock positions");
        check(portfolio_samples[959:928] == 32'd1500,
              "new portfolio value is stored at the newest history index");
        check(portfolio_samples[927:896] == 32'd1100 && portfolio_samples[895:864] == 32'd1000,
              "one new day adds one sample, with the new prices");
        check(portfolio_samples[31:0] == 32'd1000,
              "oldest history value remains after one tick");

        // A fill can change cash/positions between market-day ticks.  The
        // newest history point must follow that live valuation immediately.
        cash = 32'd900;
        settle;
        check(portfolio_samples[959:928] == 32'd1300
              && portfolio_samples[927:896] == 32'd1500,
              "history captures a live valuation change without a market tick");

        // a day on which nothing changes still adds its one sample
        @(negedge clk); tick = 1; @(negedge clk); tick = 0;
        repeat (12) @(posedge clk); #1;
        check(portfolio_samples[959:928] == 32'd1300 && portfolio_samples[927:896] == 32'd1300
              && portfolio_samples[895:864] == 32'd1500,
              "an unchanged day adds one sample of the same value");

        // largest values: 1023 shares at $655.34 in every stock, plus cash
        @(negedge clk);
        cash = 32'd5000;
        pos0 = 10'd1023; pos1 = 10'd1023; pos2 = 10'd1023; pos3 = 10'd1023;
        price0 = 16'd65534; price1 = 16'd65534; price2 = 16'd65534; price3 = 16'd65534;
        settle;
        check(portfolio_value == 32'd5000 + 4 * 32'd1023 * 32'd65534,
              "largest holdings value without overflow");

        if (n_fail == 0)
            $display("PASS: tb_portfolio_history (%0d checks)", n_pass);
        else
            $display("FAIL: tb_portfolio_history (%0d failed, %0d passed)",
                     n_fail, n_pass);
        $finish;
    end

    initial begin
        #1000;
        $display("FAIL: tb_portfolio_history timeout");
        $finish;
    end
endmodule
