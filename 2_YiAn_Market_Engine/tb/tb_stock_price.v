`timescale 1ns / 1ps

// Unit tests for stock's signed price calculation.
// The function is checked through the stock instance's next_close wire so
// the test exercises the implementation rather than a duplicate model.
module tb_stock_price;
    reg clk = 1'b0;
    reg rst = 1'b0;
    reg day_tick = 1'b0;
    reg [1:0] market_state = 2'b01;
    reg [7:0] normalized_random = 8'd50;

    wire ready;
    wire [15:0] current_close;
    wire [31:0] current_volume;
    wire [31:0] current_date;
    wire [15:0] close_history;
    wire [31:0] volume_history;
    wire [31:0] date_history;

    stock #(
        .BUFFER_DEPTH(1),
        .VOLATILITY(10),
        .SEED_FILE("AMD_seed.mem")
    ) dut (
        .clk(clk),
        .rst(rst),
        .day_tick(day_tick),
        .market_state(market_state),
        .normalized_random(normalized_random),
        .ready(ready),
        .current_close(current_close),
        .current_volume(current_volume),
        .current_date(current_date),
        .close_history(close_history),
        .volume_history(volume_history),
        .date_history(date_history)
    );

    integer n_pass = 0;
    integer n_fail = 0;

    task check;
        input condition;
        input [8*96:1] name;
        begin
            if (condition === 1'b1) begin
                n_pass = n_pass + 1;
            end else begin
                n_fail = n_fail + 1;
                $display("FAIL: %0s (got %0d)", name, dut.next_close);
            end
        end
    endtask

    initial begin
        // Force the previous close so the tests are independent of seed data.
        force dut.current_close = 16'd10000;

        // Normal state: the centered random value leaves the price unchanged.
        normalized_random = 8'd50;
        market_state = 2'b01;
        #1;
        check(dut.next_close == 16'd10000,
              "centered random value keeps the price unchanged");

        // The two extremes must move in opposite directions.
        normalized_random = 8'd0;
        #1;
        check(dut.next_close == 16'd11000,
              "low random value increases the price by the configured volatility");
        normalized_random = 8'd100;
        #1;
        check(dut.next_close == 16'd9000,
              "high random value decreases the price by the configured volatility");

        // Regime bias must be signed and must not wrap at 8 bits.
        normalized_random = 8'd50;
        market_state = 2'b00; // bear
        #1;
        check(dut.next_close == 16'd9800,
              "bear regime applies a negative two-percent bias");
        market_state = 2'b10; // bull
        #1;
        check(dut.next_close == 16'd10200,
              "bull regime applies a positive two-percent bias");
        market_state = 2'b11; // crash
        #1;
        check(dut.next_close == 16'd9400,
              "crash regime applies a larger negative bias");

        // Saturation must never produce zero or 16'hFFFF.
        force dut.current_close = 16'd1;
        normalized_random = 8'd100;
        market_state = 2'b01;
        #1;
        check(dut.next_close == 16'd1,
              "lower saturation remains at one cent");
        force dut.current_close = 16'd65534;
        normalized_random = 8'd0;
        #1;
        check(dut.next_close == 16'd65534,
              "upper saturation avoids the reserved all-ones value");

        release dut.current_close;
        if (n_fail == 0)
            $display("PASS: tb_stock_price (%0d checks)", n_pass);
        else
            $display("FAIL: tb_stock_price (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
