`timescale 1ns / 1ps

// Regression checks for the divider-free LFSR normalization.
module tb_normalise_lfsr;
    reg [31:0] lfsr_value;
    wire [7:0] normalized;

    normalise_lfsr dut (
        .lfsr_value(lfsr_value),
        .normalized(normalized)
    );

    integer n_pass = 0;
    integer n_fail = 0;

    task check;
        input condition;
        input [8*80:1] name;
        begin
            if (condition === 1'b1) begin
                n_pass = n_pass + 1;
            end else begin
                n_fail = n_fail + 1;
                $display("FAIL: %0s (got %0d)", name, normalized);
            end
        end
    endtask

    initial begin
        lfsr_value = 32'h00000000;
        #1;
        check(normalized == 8'd0, "zero LFSR value maps to zero");

        // Four equal bytes make the expected endpoints easy to verify.
        lfsr_value = 32'h66666666; // byte sum 408, approximately 40%
        #1;
        check(normalized == 8'd40, "mid-range byte sum maps near forty percent");

        lfsr_value = 32'h80808080; // byte sum 512, approximately 50%
        #1;
        check(normalized == 8'd50, "half-scale byte sum maps to fifty percent");

        lfsr_value = 32'hFFFFFFFF;
        #1;
        check(normalized == 8'd100, "maximum LFSR value saturates at one hundred");

        lfsr_value = 32'h01000000;
        #1;
        check(normalized <= 8'd1, "normalization remains near zero for a small input");

        if (n_fail == 0)
            $display("PASS: tb_normalise_lfsr (%0d checks)", n_pass);
        else
            $display("FAIL: tb_normalise_lfsr (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
