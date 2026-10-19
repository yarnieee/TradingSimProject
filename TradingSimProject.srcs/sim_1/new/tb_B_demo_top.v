`timescale 1ns / 1ps

// tb_B_demo_top: the whole board-test top, as it will run on the Basys3.
// Raw button presses (with contact bounce) go through the debouncers into the order engine,
// fills go to the ledger (stub, or Tricia's real one with -DUSE_PART_C), and one
// full frame is captured from the real Oled_Display driver as it clocks pixels
// out, then written to demo_frame.hex.
// Only the debounce time is shrunk (10 ms -> 50 clocks); the OLED driver runs at its real timing.
module tb_B_demo_top;
    reg clk = 0;
    always #5 clk = ~clk;

    reg  [15:0] sw = 16'h0004;            // sw[3:2] = 1: TEK selected, market flat
    reg         btnC = 0, btnU = 0, btnL = 0, btnR = 0, btnD = 0;
    wire [7:0]  JB;
    wire [15:0] led;

    B_demo_top dut (.clk(clk), .sw(sw), .btnC(btnC), .btnU(btnU), .btnL(btnL),
                    .btnR(btnR), .btnD(btnD), .JB(JB), .led(led));

    defparam dut.u_bc.STABLE = 50;
    defparam dut.u_bu.STABLE = 50;
    defparam dut.u_bl.STABLE = 50;
    defparam dut.u_br.STABLE = 50;
    defparam dut.u_bd.STABLE = 50;

    integer n_pass = 0, n_fail = 0;
    task check;
        input          cond;
        input [8*64:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s (t=%0t)", name, $time); end
        end
    endtask

    // count debounced pulses per button
    integer n_pulse_c = 0;
    always @(posedge clk) if (dut.btn_pulse[0]) n_pulse_c = n_pulse_c + 1;

    // press with 6 bounces on the way down and up
    task press;
        input integer which;   // 0 C, 1 U, 2 L, 3 R, 4 D
        integer k;
        begin
            for (k = 0; k < 12; k = k + 1) begin
                set_btn(which, k[0] == 0);
                repeat (3) @(posedge clk);
            end
            set_btn(which, 1); repeat (200) @(posedge clk);
            for (k = 0; k < 12; k = k + 1) begin
                set_btn(which, k[0] == 1);
                repeat (3) @(posedge clk);
            end
            set_btn(which, 0); repeat (200) @(posedge clk);
        end
    endtask
    task set_btn;
        input integer which;
        input v;
        begin
            case (which)
                0: btnC = v; 1: btnU = v; 2: btnL = v; 3: btnR = v; default: btnD = v;
            endcase
        end
    endtask

    // ------------------------------------------------------------ OLED frame capture
    reg [15:0] frame [0:6143];
    reg [6143:0] seen;
    integer f, i, capturing = 0, frame_done = 0;
    always @(posedge dut.clk_6_25MHz) begin
        if (capturing && dut.sample_pixel) begin
            frame[dut.pixel_index] = dut.ticket_pixel;
            seen[dut.pixel_index]  = 1'b1;
            if (&seen) begin capturing = 0; frame_done = 1; end
        end
    end

    initial begin
        repeat (100) @(posedge clk);

        // ---------------- debounce: one bouncy press = one pulse
        press(2); press(3);                       // L then R: focus qty -> submit -> qty
        check(dut.u_b.u_entry.focus == 0, "bouncy L then R returns focus to qty");

        // ---------------- market buy 3 TEK
        press(1); press(1);                       // qty 1 -> 3
        check(dut.u_b.u_entry.qty == 3, "two U presses: qty 3 (one pulse each despite bounce)");
        press(3); press(3);                       // focus submit
        press(0);                                 // submit
        repeat (2000) @(posedge clk);
        check(led[9:0] == 3, "led[9:0] shows TEK position 3 after the buy");
        check(led[15] == 1'b1, "led[15] fill flash on");
        check(n_pulse_c == 1, "centre button gave exactly one pulse");

        // ---------------- sell 5 with only 3 held: rejected
        press(3);                                 // focus qty (wraps)
        press(0);                                 // centre on qty: BUY -> SELL
        press(1); press(1);                       // qty 3 -> 5
        press(3); press(3); press(0);             // submit
        repeat (2000) @(posedge clk);
        check(led[14] == 1'b1 && led[9:0] == 3, "sell 5 of 3: led[14] reject flash, position still 3");
        check(dut.u_b.u_screen.rej_code == 3'd2, "ticket shows reject NO POS");

        // ---------------- capture one whole frame from the OLED driver
        seen = 0; capturing = 1;
        wait (frame_done);
        f = $fopen("demo_frame.hex", "w");
        for (i = 0; i < 6144; i = i + 1) $fdisplay(f, "%04h", frame[i]);
        $fclose(f);
        check(1'b1, "full frame captured from Oled_Display");

        if (n_fail == 0) $display("PASS: tb_B_demo_top (%0d checks)", n_pass);
        else             $display("FAIL: tb_B_demo_top (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end

    initial begin #300_000_000; $display("FAIL: tb_B_demo_top timeout"); $finish; end
endmodule
