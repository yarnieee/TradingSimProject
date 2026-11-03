`timescale 1ns / 1ps

// tb_progress_width: both game-progress bars (96 and 1242 pixels over 120 days)
// give days_gone x width / 120, rounded down, for every day 0..120, and stay
// full if days_gone is ever past the last day.
module tb_progress_width;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1;
    reg [31:0] dg = 0;
    wire [6:0]  w_oled;
    wire [10:0] w_vga;
    progress_width #(.DAYS(120), .WIDTH(96),   .W(7))  oled (.clk(clk), .rst(rst), .days_gone(dg), .width(w_oled));
    progress_width #(.DAYS(120), .WIDTH(1242), .W(11)) vga  (.clk(clk), .rst(rst), .days_gone(dg), .width(w_vga));

    integer d, bad = 0, n_pass = 0, n_fail = 0;
    task check;
        input cond; input [8*60:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s", name); end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk); rst = 0;
        repeat (80) @(posedge clk); #1;
        check(w_oled == 0 && w_vga == 0, "day 0: empty bars");
        for (d = 0; d <= 120; d = d + 1) begin
            dg = d;
            repeat (80) @(posedge clk); #1;
            if (w_oled !== (d * 96) / 120 || w_vga !== (d * 1242) / 120) begin
                bad = bad + 1;
                if (bad < 5) $display("     day %0d: %0d / %0d, want %0d / %0d", d, w_oled, w_vga, (d * 96) / 120, (d * 1242) / 120);
            end
        end
        check(bad == 0, "every day 0..120: width = days x pixels / 120");
        check(w_oled == 96 && w_vga == 1242, "day 120: full bars");
        dg = 500; repeat (80) @(posedge clk); #1;
        check(w_oled == 96 && w_vga == 1242, "past the last day: still full");
        if (n_fail == 0) $display("PASS: tb_progress_width (%0d checks)", n_pass);
        else             $display("FAIL: tb_progress_width (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
