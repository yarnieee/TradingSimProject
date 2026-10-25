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

    initial begin
        #12;
        rst = 0;
        #4;
        check(portfolio_value == 32'd1000,
              "cash-only portfolio value is available after reset");
        check(portfolio_samples[31:0] == 32'd1000
              && portfolio_samples[959:928] == 32'd1000,
              "history initializes flat across its full range");

        pos0 = 10'd2; price0 = 16'd10;
        pos1 = 10'd3; price1 = 16'd20;
        pos2 = 10'd4; price2 = 16'd30;
        pos3 = 10'd5; price3 = 16'd40;
        #1;
        check(portfolio_value == 32'd1400,
              "portfolio value includes all four stock positions");

        @(negedge clk);
        tick = 1;
        @(negedge clk);
        tick = 0;
        #1;
        check(portfolio_samples[959:928] == 32'd1400,
              "new portfolio value is stored at the newest history index");
        check(portfolio_samples[31:0] == 32'd1000,
              "oldest history value remains after one tick");

        // A fill can change cash/positions between market-day ticks.  The
        // newest history point must follow that live valuation immediately.
        cash = 32'd900;
        #1;
        @(posedge clk);
        #1;
        check(portfolio_samples[959:928] == 32'd1300,
              "history captures a live valuation change without a market tick");

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
