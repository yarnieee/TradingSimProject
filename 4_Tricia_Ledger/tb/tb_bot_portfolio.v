`timescale 1ns / 1ps
// Exercise the real Component C integration: trader -> ledger -> mark-to-market.
module tb_bot_portfolio;
    reg clk=0, rst=1, run=1, tick=0;
    always #5 clk=~clk;
    reg [15:0] price0=10000,price1=10000,price2=10000,price3=10000;
    wire [31:0] cash,eq;
    wire [9:0] p0,p1,p2,p3;
    wire signed [31:0] u0,u1,u2,u3,realised;
    wire [31:0] player_cash;
    C_portfolio_top #(.ENABLE_BOT(1)) dut (
        .clk(clk),.sys_reset(rst),.bot_run(run),.tick(tick),
        .price0(price0),.price1(price1),.price2(price2),.price3(price3),
        .fill(1'b0),.fill_stock(2'd0),.fill_side(1'b0),
        .fill_qty(8'd0),.fill_price(16'd0),.fill_fee(16'd0),
        .cash(player_cash),.bot_cash(cash),.bot_equity(eq),
        .bot_pos0(p0),.bot_pos1(p1),.bot_pos2(p2),.bot_pos3(p3),
        .bot_upnl0(u0),.bot_upnl1(u1),.bot_upnl2(u2),.bot_upnl3(u3),
        .bot_realised(realised)
    );
    integer errors=0;
    task day;
        begin
            @(negedge clk);tick=1;
            @(negedge clk);tick=0;
            repeat(300) @(negedge clk);
            if (eq !== cash+p0*price0+p1*price1+p2*price2+p3*price3) begin
                errors=errors+1;$display("FAIL: bot equity is not marked to market");
            end
            if (player_cash !== 32'd1000000) begin
                errors=errors+1;$display("FAIL: bot modified player cash");
            end
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst=0;
        day;
        if(cash!==1000000 || eq!==1000000 || {p0,p1,p2,p3}!==40'd0) begin
            errors=errors+1;$display("FAIL: initial bot portfolio");
        end
        price0=10100;price1=10100;price2=10100;price3=10100;day;
        if(p0!==20 || p1!==20 || p2!==20 || p3!==20 || cash!==191200 ||
           u0!==-200 || u1!==-200 || u2!==-200 || u3!==-200) begin
            errors=errors+1;$display("FAIL: four bot buys/cash/P&L cash=%0d u0=%0d",cash,u0);
        end
        price0=9500;price1=9500;price2=9500;price3=9500;day;
        if({p0,p1,p2,p3}!==40'd0 || cash!==950400 || realised!==-49600 ||
           {u0,u1,u2,u3}!==128'd0) begin
            errors=errors+1;$display("FAIL: four bot sells/cash/P&L");
        end
        run=0;price0=12000;price1=12000;price2=12000;price3=12000;day;
        if(cash!==950400 || {p0,p1,p2,p3}!==40'd0) begin
            errors=errors+1;$display("FAIL: gameplay gating");
        end
        if(errors==0) $display("PASS: ALL BOT PORTFOLIO TESTS PASSED");
        else $display("FAIL: %0d BOT PORTFOLIO TEST(S) FAILED",errors);
        $finish;
    end
endmodule
