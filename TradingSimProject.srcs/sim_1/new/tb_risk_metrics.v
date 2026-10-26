`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 26.10.2026 11:24:49
// Design Name: 
// Module Name: tb_risk_metrics
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
module tb_risk_metrics;
    reg clk = 0, rst = 1, tick = 0;
    reg  [15:0] price0 = 0, price1 = 0, price2 = 0, price3 = 0;
    reg  [31:0] cash = 32'd1_000_000;
    reg  [9:0]  pos0 = 0, pos1 = 0, pos2 = 0, pos3 = 0;
    reg  [31:0] cb0 = 0, cb1 = 0, cb2 = 0, cb3 = 0;
    wire [31:0] equity, peak, dd_bp, max_dd_bp;
    wire signed [31:0] pnl, ret_bp, upnl0, upnl1, upnl2, upnl3;
    wire mtm_done;
    integer errors = 0;

    risk_metrics dut (
        .clk(clk), .rst(rst), .tick(tick),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .cb0(cb0), .cb1(cb1), .cb2(cb2), .cb3(cb3),
        .equity(equity), .pnl(pnl), .ret_bp(ret_bp),
        .upnl0(upnl0), .upnl1(upnl1), .upnl2(upnl2), .upnl3(upnl3),
        .peak(peak), .dd_bp(dd_bp), .max_dd_bp(max_dd_bp), .mtm_done(mtm_done)
    );

    always #5 clk = ~clk;   // 100 MHz

    // send one tick, wait for the result, compare
    task check(input [8*24-1:0] name,
               input [31:0] e_eq, input integer e_ret, input integer e_upnl1,
               input [31:0] e_peak, input [31:0] e_dd, input [31:0] e_maxdd);
    begin
        @(negedge clk); tick = 1;
        @(negedge clk); tick = 0;
        wait (mtm_done); @(negedge clk);
        if (equity == e_eq && pnl == $signed(e_eq) - 1000000 && ret_bp == e_ret &&
            upnl1 == e_upnl1 && peak == e_peak && dd_bp == e_dd && max_dd_bp == e_maxdd)
            $display("PASS %0s | eq=%0d pnl=%0d ret=%0d upnl1=%0d peak=%0d dd=%0d maxdd=%0d",
                     name, equity, pnl, ret_bp, upnl1, peak, dd_bp, max_dd_bp);
        else begin
            $display("FAIL %0s | eq=%0d pnl=%0d ret=%0d upnl1=%0d peak=%0d dd=%0d maxdd=%0d",
                     name, equity, pnl, ret_bp, upnl1, peak, dd_bp, max_dd_bp);
            $display("      expected eq=%0d ret=%0d upnl1=%0d peak=%0d dd=%0d maxdd=%0d",
                     e_eq, e_ret, e_upnl1, e_peak, e_dd, e_maxdd);
            errors = errors + 1;
        end
    end
    endtask

    initial begin
        #22 rst = 0;
        //equity    ret   upnl1   peak     dd  maxdd
        // M1: no positions -> equity = cash
        price1 = 12000;
        check("M1 no positions",        1000000,    0,      0, 1000000,   0,   0);

        // M2: after T1 (bought 10 @123.50 + fee, cost basis 123623), price up to 125.00
        cash = 876377; pos1 = 10; cb1 = 123623; price1 = 12500;
        check("M2 price up",            1001377,   13,   1377, 1001377,   0,   0);

        // M3: price falls to 110.00 -> loss, new drawdown from the peak
        price1 = 11000;
        check("M3 price down",           986377, -136, -13623, 1001377, 149, 149);

        // M4: partial recovery to 120.00 -> drawdown shrinks, max drawdown stays
        price1 = 12000;
        check("M4 partial recovery",     996377,  -36,  -3623, 1001377,  49, 149);

        // M5: three stocks at once, incl. max position x max price -> new peak
        cash = 500000; pos1 = 0; cb1 = 0;
        pos0 = 100;  cb0 = 452452;   price0 = 4520;
        pos2 = 30;   cb2 = 262000;   price2 = 8750;
        pos3 = 1023; cb3 = 60000000; price3 = 65535;
        check("M5 three stocks, big",  68256805, 672568,     0, 68256805, 0, 149);
        if (upnl0 !== -452 || upnl2 !== 500 || upnl3 !== 7042305) begin
            $display("FAIL M5 per-stock P&L | upnl0=%0d upnl2=%0d upnl3=%0d (expected -452 500 7042305)",
                     upnl0, upnl2, upnl3);
            errors = errors + 1;
        end else
            $display("PASS M5 per-stock P&L | upnl0=%0d upnl2=%0d upnl3=%0d", upnl0, upnl2, upnl3);

        if (errors == 0) $display("=== ALL RISK TESTS PASSED ===");
        else             $display("=== %0d RISK TEST(S) FAILED ===", errors);
        $finish;
    end
endmodule
