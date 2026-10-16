`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.10.2026 14:04:41
// Design Name: 
// Module Name: tb_ledger
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

`timescale 1ns / 1ps
module tb_ledger;
    reg clk = 0, rst = 1;
    reg fill = 0, fill_side = 0;
    reg [1:0]  fill_stock = 0;
    reg [7:0]  fill_qty = 0;
    reg [15:0] fill_price = 0, fill_fee = 0;
    wire [31:0] cash, cb0, cb1, cb2, cb3;
    wire [9:0]  pos0, pos1, pos2, pos3;
    wire signed [31:0] realised;
    wire busy, err;
    integer errors = 0;
    reg saw_err;

    ledger dut (
        .clk(clk), .rst(rst),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .cb0(cb0), .cb1(cb1), .cb2(cb2), .cb3(cb3),
        .realised(realised), .busy(busy), .err(err)
    );

    always #5 clk = ~clk;
    always @(posedge clk) if (err) saw_err <= 1'b1;

    // send one fill and wait until the ledger is idle again
    task trade(input [1:0] s, input side, input [7:0] q, input [15:0] p, input [15:0] f);
    begin
        saw_err = 0;
        @(negedge clk); fill_stock = s; fill_side = side; fill_qty = q;
                        fill_price = p; fill_fee = f; fill = 1;
        @(negedge clk); fill = 0;
        wait (!busy); @(negedge clk);
    end
    endtask

    // check one stock's state + the invariant
    task check(input [8*24-1:0] name, input [1:0] s, input [31:0] e_cash, input [9:0] e_pos,
               input [31:0] e_cb, input integer e_real, input e_err);
        reg ok;
    begin
        ok = (cash == e_cash) && (dut.pos[s] == e_pos) && (dut.cb[s] == e_cb)
             && (realised == e_real) && (saw_err == e_err)
             && (cash + cb0 + cb1 + cb2 + cb3 == 32'd1_000_000 + realised);
        if (ok)
            $display("PASS %0s | cash=%0d pos=%0d cb=%0d realised=%0d err=%0d",
                     name, cash, dut.pos[s], dut.cb[s], realised, saw_err);
        else begin
            $display("FAIL %0s | cash=%0d pos=%0d cb=%0d realised=%0d err=%0d",
                     name, cash, dut.pos[s], dut.cb[s], realised, saw_err);
            $display("      expected cash=%0d pos=%0d cb=%0d realised=%0d err=%0d",
                     e_cash, e_pos, e_cb, e_real, e_err);
            errors = errors + 1;
        end
    end
    endtask

    initial begin
        #22 rst = 0;
        //     stock side qty  price  fee
        trade(1, 0, 10, 12350, 123); check("T1 BUY 10 @123.50",  1,  876377,  10, 123623,    0, 0);
        trade(1, 0,  5, 12000,  60); check("T2 BUY 5 @120.00",   1,  816317,  15, 183683,    0, 0);
        trade(1, 1,  6, 13000,  78); check("T3 SELL 6 (partial)",1,  894239,   9, 110213, 4452, 0);
        trade(1, 1,  9, 12500, 112); check("T4 SELL 9 (close)",  1, 1006627,   0,      0, 6627, 0);
        trade(1, 1,  1, 12500,  12); check("T5 SELL w/ no pos",  1, 1006627,   0,      0, 6627, 1);
        trade(2, 0,100,  4520, 452); check("T6 BUY 100 stock2",  2,  554175, 100, 452452, 6627, 0);
        trade(3, 0,255, 65535,16711);check("T7 BUY too pricey",  3,  554175,   0,      0, 6627, 1);
        trade(2, 1, 40,  4000, 160); check("T8 SELL 40 at loss", 2,  714015,  60, 271492,-14493, 0);

        if (errors == 0) $display("=== ALL LEDGER TESTS PASSED ===");
        else             $display("=== %0d LEDGER TEST(S) FAILED ===", errors);
        $finish;
    end
endmodule