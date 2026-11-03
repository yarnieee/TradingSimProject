`timescale 1ns / 1ps

// tb_debouncer: one bouncy press gives one press, however long the button is
// held; the bounce on release does not give a second press; a quick tap is not
// lost; presses further apart than the lock all count.
module tb_debouncer;
    reg clk = 0; always #5 clk = ~clk;
    reg btn = 0;
    wire db;
    debouncer #(.DEBOUNCE_CTR(100)) dut (.clk(clk), .btn(btn), .debounced(db));

    integer presses = 0;
    reg db_d = 0;
    always @(posedge clk) begin db_d <= db; if (db && !db_d) presses = presses + 1; end

    integer n_pass = 0, n_fail = 0;
    task check;
        input cond; input [8*64:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s (presses %0d)", name, presses); end
        end
    endtask

    task bounce;                              // a few fast changes, ending at level v
        input v;
        integer k;
        begin
            for (k = 0; k < 5; k = k + 1) begin
                btn = v;  repeat (3 + k) @(posedge clk);
                btn = !v; repeat (2 + k) @(posedge clk);
            end
            btn = v;
        end
    endtask

    integer p0, lag;
    initial begin
        repeat (20) @(posedge clk);
        // a press held well past the lock, with bounce on press and on release
        p0 = presses;
        bounce(1);
        lag = 0; while (!db && lag < 10) begin @(posedge clk); lag = lag + 1; end
        check(lag <= 4 || p0 != presses, "a press shows straight away (within the synchroniser)");
        repeat (400) @(posedge clk);          // held: 4 x the lock
        bounce(0);
        repeat (400) @(posedge clk);
        check(presses == p0 + 1 && db == 0, "held press with bouncy release: exactly one press");

        // a quick tap, shorter than the lock
        p0 = presses;
        btn = 1; repeat (20) @(posedge clk); btn = 0;
        repeat (300) @(posedge clk);
        check(presses == p0 + 1 && db == 0, "a quick tap counts once and ends released");

        // three presses, each further apart than the lock
        p0 = presses;
        repeat (3) begin bounce(1); repeat (200) @(posedge clk); bounce(0); repeat (200) @(posedge clk); end
        check(presses == p0 + 3, "three separate presses count three times");

        if (n_fail == 0) $display("PASS: tb_debouncer (%0d checks)", n_pass);
        else             $display("FAIL: tb_debouncer (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
