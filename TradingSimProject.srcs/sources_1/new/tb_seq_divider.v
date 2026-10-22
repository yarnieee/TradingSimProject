`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.10.2026 12:23:30
// Design Name: 
// Module Name: tb_seq_divider
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_seq_divider;
    reg clk = 0, rst = 1, start = 0;
    reg  [31:0] dividend, divisor;
    wire [31:0] quotient, remainder;
    wire busy, done;
    integer errors = 0;

    seq_divider #(.W(32)) dut (
        .clk(clk), .rst(rst), .start(start),
        .dividend(dividend), .divisor(divisor),
        .quotient(quotient), .remainder(remainder),
        .busy(busy), .done(done)
    );

    always #5 clk = ~clk;   // 100 MHz

    task check(input [31:0] a, input [31:0] b, input [31:0] exp_q, input [31:0] exp_r);
    begin
        @(negedge clk); dividend = a; divisor = b; start = 1;
        @(negedge clk); start = 0;
        wait (done); @(negedge clk);
        if (quotient !== exp_q || remainder !== exp_r) begin
            $display("FAIL %0d / %0d -> q=%0d r=%0d (expected q=%0d r=%0d)",
                     a, b, quotient, remainder, exp_q, exp_r);
            errors = errors + 1;
        end else
            $display("PASS %0d / %0d = %0d r %0d", a, b, quotient, remainder);
    end
    endtask

    initial begin
        #20 rst = 0;
        check(183683, 15, 12245, 8);      // avg cost from ledger example
        check(100, 7, 14, 2);
        check(7, 100, 0, 7);              // divisor bigger than dividend
        check(0, 5, 0, 0);
        check(32'hFFFFFFFF, 1, 32'hFFFFFFFF, 0);
        check(1000000, 1000000, 1, 0);
        check(150000000, 1010000, 148, 520000); // drawdown bp example
        check(42, 0, 0, 42);              // divide by zero
        if (errors == 0) $display("=== ALL TESTS PASSED ===");
        else             $display("=== %0d TEST(S) FAILED ===", errors);
        $finish;
    end
endmodule
