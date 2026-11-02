`timescale 1ns / 1ps
// Compare the bounded datapath against the original wide signed formula.
module tb_price_equivalence;
    stock #(.BUFFER_DEPTH(1), .VOLATILITY(0), .SEED_FILE("AMD_seed.mem")) v0();
    stock #(.BUFFER_DEPTH(1), .VOLATILITY(8), .SEED_FILE("AMD_seed.mem")) v8();
    stock #(.BUFFER_DEPTH(1), .VOLATILITY(10), .SEED_FILE("AMD_seed.mem")) v10();
    stock #(.BUFFER_DEPTH(1), .VOLATILITY(14), .SEED_FILE("AMD_seed.mem")) v14();
    stock #(.BUFFER_DEPTH(1), .VOLATILITY(20), .SEED_FILE("AMD_seed.mem")) v20();
    stock #(.BUFFER_DEPTH(1), .VOLATILITY(100), .SEED_FILE("AMD_seed.mem")) v100();
    stock #(.BUFFER_DEPTH(1), .VOLATILITY(-1), .SEED_FILE("AMD_seed.mem")) vn();
    stock #(.BUFFER_DEPTH(1), .VOLATILITY(101), .SEED_FILE("AMD_seed.mem")) vx();
    function [15:0] reference_price;
        input [15:0] previous;
        input integer rv, regime, vol;
        integer adjusted, delta, multiplier;
        reg signed [63:0] product, result;
        begin
            adjusted = rv;
            case (regime) 0: adjusted=rv+10; 2: adjusted=rv-10; 3: adjusted=rv+30; endcase
            if (adjusted < 0) adjusted=0;
            if (adjusted > 100) adjusted=100;
            if (vol < 0) vol=0;
            if (vol > 100) vol=100;
            delta = ((50-adjusted)*vol)/50;
            multiplier = 100+delta;
            product = $signed({1'b0,previous}) * multiplier;
            result = product/100;
            if (result < 1) result=1;
            if (result > 65534) result=65534;
            reference_price=result;
        end
    endfunction
    integer prices [0:13];
    integer p, r, s, errors=0, checks=0;
    reg [15:0] price;
    reg [31:0] rng=32'h5329ab17;
    task compare(input [15:0] actual, input integer vol);
        begin
            checks=checks+1;
            if (actual !== reference_price(price,r,s,vol)) begin
                if (errors < 8) $display("FAIL: price=%0d random=%0d regime=%0d vol=%0d actual=%0d expected=%0d",
                       price,r,s,vol,actual,reference_price(price,r,s,vol));
                errors=errors+1;
            end
        end
    endtask
    task check_price;
        begin
            compare(v0.calculate_next_close(price,r,s),0);
            compare(v8.calculate_next_close(price,r,s),8);
            compare(v10.calculate_next_close(price,r,s),10);
            compare(v14.calculate_next_close(price,r,s),14);
            compare(v20.calculate_next_close(price,r,s),20);
            compare(v100.calculate_next_close(price,r,s),100);
            compare(vn.calculate_next_close(price,r,s),-1);
            compare(vx.calculate_next_close(price,r,s),101);
        end
    endtask
    initial begin
        prices[0]=0; prices[1]=1; prices[2]=2; prices[3]=49; prices[4]=50;
        prices[5]=99; prices[6]=100; prices[7]=101; prices[8]=255;
        prices[9]=32767; prices[10]=32768; prices[11]=65533; prices[12]=65534; prices[13]=65535;
        #1;
        for (p=0;p<14;p=p+1) begin
            price=prices[p];
            for (r=0;r<256;r=r+1)
                for (s=0;s<4;s=s+1) check_price;
        end
        for (p=0;p<4096;p=p+1) begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            price=rng[15:0]; r=rng[23:16]; s=rng[25:24]; check_price;
        end
        if (errors==0) $display("PASS: ALL PRICE EQUIVALENCE TESTS PASSED (%0d comparisons)",checks);
        else $display("FAIL: %0d PRICE EQUIVALENCE TEST(S) FAILED",errors);
        $finish;
    end
endmodule
