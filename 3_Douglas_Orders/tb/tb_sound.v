`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_sound: B_sound_top. Which sound each event plays, their order and
// priorities (woosh then bell; game end over everything; a click does not cut a
// bell), their pitch (zero crossings) and length, and mute.
// Samples come every 16 clocks here (SAMPLE_SHIFT 4) instead of 2048; a sound
// has the same samples either way. The samples of each sound are written to
// sound_<name>.txt (one 0..255 value a line, 48,828 a second on the board):
// 3_Douglas_Orders/tb/sound_to_wav.py turns them into .wav files to listen to.
module tb_sound;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1, mute = 0, ord_req = 0, fill = 0;
    reg [4:0] btn = 5'd0;
    reg [3:0] screen = `UI_PORTFOLIO;
    wire pwm, gain, sd_n;
    wire [2:0] now;
    B_sound_top #(.SAMPLE_SHIFT(4)) dut (
        .clk(clk), .rst(rst), .mute(mute), .btn_pulse(btn), .screen_state(screen),
        .order_ok(1'b1), .order_code(3'd0), .qty_zero(1'b0),     // no error buzz in this test
        .ord_req(ord_req), .fill(fill), .aud_pwm(pwm), .aud_gain(gain), .aud_sd_n(sd_n),
        .now_playing(now)
    );

    integer n_pass = 0, n_fail = 0;
    task check;
        input cond; input [8*64:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s (t=%0t)", name, $time); end
        end
    endtask

    // ---- samples: one per sample tick (3 clocks after it, when the mix is through)
    wire tick = dut.u_synth.tick;
    reg  [2:0] tick_d;
    always @(posedge clk) tick_d <= {tick_d[1:0], tick};
    wire sample_now = tick_d[2];
    wire [7:0] smp = dut.u_synth.duty;
    integer fd = 0, n_smp = 0, xings = 0;
    reg     above;
    always @(posedge clk) if (sample_now && dut.playing) begin
        if (fd != 0) $fdisplay(fd, "%0d", smp);
        n_smp = n_smp + 1;
        if ((smp >= 8'd128) != above) xings = xings + 1;
        above = (smp >= 8'd128);
    end
    task count_from_now; begin n_smp = 0; xings = 0; above = 1'b1; end endtask
    task samples; input integer k; begin repeat (k * 16) @(posedge clk); end endtask

    task press;                      // one button pulse
        input [4:0] b;
        begin @(negedge clk); btn = b; @(negedge clk); btn = 5'd0; end
    endtask
    task pulse_ord;  begin @(negedge clk); ord_req = 1; @(negedge clk); ord_req = 0; end endtask
    task pulse_fill; begin @(negedge clk); fill = 1;    @(negedge clk); fill = 0;    end endtask
    task wait_quiet; begin while (now != 3'd0) @(posedge clk); repeat (40) @(posedge clk); end endtask
    reg [8*32:1] fname;
    task record;                     // write the next sound's samples to sound_<name>.txt
        input [8*12:1] name;
        begin
            if (fd != 0) $fclose(fd);
            $sformat(fname, "sound_%0s.txt", name);
            fd = $fopen(fname, "w");
        end
    endtask
    task stop_recording; begin if (fd != 0) $fclose(fd); fd = 0; end endtask

    integer x1, x2, t0, len_w;
    initial begin
        repeat (5) @(posedge clk); rst = 0;
        repeat (100) @(posedge clk);
        check(now == 0 && pwm == 0 && gain == 1 && sd_n == 1, "quiet at the start, amplifier on");

        // ---- CLICK: 1.5 kHz for 1220 samples (25 ms): about 75 zero crossings
        record("click"); count_from_now;
        press(5'b00100);                                  // BTNL on the portfolio screen
        repeat (3) @(posedge clk);
        check(now == 3'd1, "a button plays the click");
        wait_quiet; stop_recording;
        check(n_smp >= 1215 && n_smp <= 1225, "click lasts 25 ms (1220 samples)");
        check(xings >= 68 && xings <= 82, "click is 1.5 kHz");

        // ---- UP on the quantity screen: 880 Hz (2441 samples) then 1319 Hz (3418)
        screen = `UI_QUANTITY;
        record("up"); count_from_now;
        press(5'b00010);                                  // BTNU
        repeat (3) @(posedge clk);
        check(now == 3'd2, "BTNU on the quantity screen plays UP");
        samples(2441); x1 = xings; count_from_now;
        wait_quiet; x2 = xings; stop_recording;
        check(x1 >= 80 && x1 <= 96 && x2 >= 172 && x2 <= 196, "UP rises: 880 Hz then 1319 Hz");

        // ---- DOWN: 1319 Hz then 880 Hz
        record("down"); count_from_now;
        press(5'b10000);                                  // BTND
        repeat (3) @(posedge clk);
        check(now == 3'd2, "BTND on the quantity screen plays DOWN");
        samples(2441); x1 = xings; count_from_now;
        wait_quiet; x2 = xings; stop_recording;
        check(x1 >= 124 && x1 <= 140 && x2 >= 115 && x2 <= 131, "DOWN falls: 1319 Hz then 880 Hz");
        press(5'b00100);                                  // BTNL on the quantity screen: a click
        repeat (3) @(posedge clk);
        check(now == 3'd1, "other buttons on the quantity screen click");
        wait_quiet;
        screen = `UI_ORDER_REVIEW;

        // ---- an order: the BTNC click is replaced by the woosh; the fill rings the bell after it
        record("order"); count_from_now;
        press(5'b00001);                                  // BTNC on the review screen
        pulse_ord;                                        // the order goes the clock after
        repeat (3) @(posedge clk);
        check(now == 3'd3, "sending an order plays the woosh (over the click)");
        repeat (200) @(posedge clk);
        pulse_fill;                                       // a market order fills at once
        repeat (3) @(posedge clk);
        check(now == 3'd3 && dut.bell_wait, "the fill waits for the woosh to finish");
        t0 = $time;
        while (now == 3'd3) @(posedge clk);
        len_w = ($time - t0) / 10;
        check(now == 3'd4, "then the bell rings");
        samples(3000);
        press(5'b00100);                                  // a click does not cut the bell
        repeat (3) @(posedge clk);
        check(now == 3'd4, "a click does not interrupt the bell");
        wait_quiet; stop_recording;
        check(n_smp >= 16384 + 58594 - 10 && n_smp <= 16384 + 58594 + 300,
              "woosh 335 ms (16,384 samples), bell 1.2 s (58,594 samples)");

        // ---- a fill on its own (a limit order from the book): just the bell
        pulse_fill;
        repeat (3) @(posedge clk);
        check(now == 3'd4, "a fill from the book rings the bell");

        // ---- game end takes over at once, and plays C5 E5 G5, C6
        record("game_end"); count_from_now;
        @(negedge clk); screen = `UI_GAME_END;
        repeat (3) @(posedge clk);
        check(now == 3'd5, "the game-over screen plays the game-end sound (over the bell)");
        samples(5859); x1 = xings;
        wait_quiet; stop_recording;
        check(x1 >= 115 && x1 <= 140, "game end starts on C5 (523 Hz)");
        check(n_smp >= 3 * 5859 + 39062 - 10 && n_smp <= 3 * 5859 + 39062 + 10, "game end lasts 1.16 s");
        press(5'b00001);
        repeat (3) @(posedge clk);
        check(now == 3'd1, "buttons still click on the game-over screen");
        wait_quiet;

        // ---- mute: nothing plays, the amplifier is off
        screen = `UI_PORTFOLIO;
        @(negedge clk); mute = 1;
        press(5'b00100); pulse_ord; pulse_fill;
        repeat (500) @(posedge clk);
        check(now == 0 && pwm == 0 && sd_n == 0, "mute: silent, amplifier off");
        mute = 0;
        press(5'b00100);
        repeat (3) @(posedge clk);
        check(now == 3'd1 && sd_n == 1, "unmuted: sounds again");
        wait_quiet;

        if (n_fail == 0) $display("PASS: tb_sound (%0d checks)", n_pass);
        else             $display("FAIL: tb_sound (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end
endmodule
