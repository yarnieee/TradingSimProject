`timescale 1ns / 1ps
`default_nettype none

// sound_synth: plays one sound at a time as a list of segments (the table below),
// out of two tone voices and a noise voice, as PWM on one pin.
//
// Samples: one every 2^SAMPLE_SHIFT clocks (2048: 48.8 kHz). Each sample:
//   voice A   square or triangle, phase += incA          (frequency = inc x 48,828 / 65,536 Hz)
//   voice B   triangle, phase += incB
//   noise     16-bit LFSR through a low-pass filter
//   volumes   A and B fade: vol -= vol >> k (k larger = longer ring); the noise
//             "swells" (up, then down) over a 16,384-sample segment, and the
//             filter opens in the middle: a woosh
// mix = waveA x volA + waveB x volB + 2 x noise x volN, registered in two steps;
// PWM: 8-bit duty at clk / 256 (390 kHz); the pin is low when nothing plays.
//
// start loads segment start_seg and plays on until a segment marked last;
// starting again while playing switches sound at once. done pulses at the end.
module sound_synth #(
    parameter integer SAMPLE_SHIFT = 11
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [3:0] start_seg,
    output reg        playing,
    output reg        done,
    output reg  [7:0] duty,              // the sample (128 = silence while playing)
    output reg        pwm
);
    // ------------------------------------------------------------ the segments
    // {incA, incB, square A, noise, last, vA, kA, vB, kB, length in samples}
    //   0      CLICK   1.5 kHz square, 25 ms
    //   1, 2   UP      880 Hz then 1319 Hz
    //   3, 4   DOWN    1319 Hz then 880 Hz
    //   5      WOOSH   noise swell, 335 ms
    //   6      BELL    1568 Hz + 4328 Hz (x 2.76, a bell's overtone), rings 1.2 s
    //   7-10   GAME END  C5, E5, G5, then C6 + E6 held
    localparam integer SEGW = 16 + 16 + 3 + 8 + 4 + 8 + 4 + 16;
    function [SEGW-1:0] seg;
        input [3:0] n;
        begin
            case (n)
                //                 incA      incB     sq,nz,last  vA     kA     vB     kB     length
                4'd0:  seg = {16'd2013, 16'd0,    3'b101, 8'd220, 4'd9,  8'd0,   4'd0,  16'd1220};
                4'd1:  seg = {16'd1181, 16'd0,    3'b100, 8'd200, 4'd11, 8'd0,   4'd0,  16'd2441};
                4'd2:  seg = {16'd1770, 16'd0,    3'b101, 8'd200, 4'd11, 8'd0,   4'd0,  16'd3418};
                4'd3:  seg = {16'd1770, 16'd0,    3'b100, 8'd200, 4'd11, 8'd0,   4'd0,  16'd2441};
                4'd4:  seg = {16'd1181, 16'd0,    3'b101, 8'd200, 4'd11, 8'd0,   4'd0,  16'd3418};
                4'd5:  seg = {16'd0,    16'd0,    3'b011, 8'd0,   4'd0,  8'd0,   4'd0,  16'd16384};
                4'd6:  seg = {16'd2104, 16'd5809, 3'b001, 8'd255, 4'd15, 8'd140, 4'd13, 16'd58594};
                4'd7:  seg = {16'd702,  16'd1404, 3'b100, 8'd180, 4'd13, 8'd80,  4'd12, 16'd5859};
                4'd8:  seg = {16'd885,  16'd1770, 3'b100, 8'd180, 4'd13, 8'd80,  4'd12, 16'd5859};
                4'd9:  seg = {16'd1052, 16'd2104, 3'b100, 8'd180, 4'd13, 8'd80,  4'd12, 16'd5859};
                4'd10: seg = {16'd1405, 16'd1770, 3'b101, 8'd200, 4'd15, 8'd120, 4'd15, 16'd39062};
                default: seg = {16'd0, 16'd0, 3'b001, 8'd0, 4'd0, 8'd0, 4'd0, 16'd1};
            endcase
        end
    endfunction

    reg  [3:0]  si;                      // segment playing
    wire [SEGW-1:0] s = seg(si);
    wire [15:0] s_incA = s[SEGW-1 -: 16];
    wire [15:0] s_incB = s[SEGW-17 -: 16];
    wire        s_sq   = s[SEGW-33];
    wire        s_nz   = s[SEGW-34];
    wire        s_last = s[SEGW-35];
    wire [7:0]  s_vA   = s[39:32];
    wire [3:0]  s_kA   = s[31:28];
    wire [7:0]  s_vB   = s[27:20];
    wire [3:0]  s_kB   = s[19:16];
    wire [15:0] s_len  = s[15:0];

    // ------------------------------------------------------------ sample clock
    reg  [SAMPLE_SHIFT-1:0] div;
    wire tick = (div == {SAMPLE_SHIFT{1'b0}});

    // ------------------------------------------------------------ voices
    reg  [15:0] phA, phB, pos;
    reg  [23:0] volA, volB;              // volume x 65536, so slow fades keep their fraction
    reg  [15:0] lfsr;
    reg  signed [9:0] lp;                // low-passed noise
    reg         load;                    // load segment si on the next tick

    wire signed [8:0] triA = {1'b0, phA[15] ? ~phA[14:7] : phA[14:7]} - 9'sd128;
    wire signed [8:0] sqA  = phA[15] ? 9'sd100 : -9'sd100;
    wire signed [8:0] wA   = (s_incA == 16'd0) ? 9'sd0 : s_sq ? sqA : triA;
    wire signed [8:0] wB   = (s_incB == 16'd0) ? 9'sd0 :
                             ({1'b0, phB[15] ? ~phB[14:7] : phB[14:7]} - 9'sd128);
    wire signed [9:0] noise = {{2{lfsr[7]}}, lfsr[7:0]};
    wire [7:0]  swell  = pos[13] ? ~pos[12:5] : pos[12:5];        // up, then down
    wire [1:0]  fshift = swell[7] ? 2'd1 : swell[6] ? 2'd2 : 2'd3; // brighter at the top
    wire [7:0]  volN   = s_nz ? swell : 8'd0;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            div <= {SAMPLE_SHIFT{1'b0}};
            playing <= 1'b0; load <= 1'b0; si <= 4'd0;
            phA <= 16'd0; phB <= 16'd0; pos <= 16'd0;
            volA <= 24'd0; volB <= 24'd0;
            lfsr <= 16'hACE1; lp <= 10'sd0;
        end else begin
            div <= div + 1'b1;
            if (start) begin
                si <= start_seg; load <= 1'b1; playing <= 1'b1;
            end else if (tick && playing) begin
                if (load) begin                       // a new segment: its volumes, from sample 0
                    volA <= {s_vA, 16'd0};
                    volB <= {s_vB, 16'd0};
                    pos  <= 16'd0;
                    load <= 1'b0;
                end else begin
                    phA  <= phA + s_incA;
                    phB  <= phB + s_incB;
                    volA <= volA - (volA >> s_kA);
                    volB <= volB - (volB >> s_kB);
                    lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
                    lp   <= lp + ((noise - lp) >>> fshift);
                    pos  <= pos + 16'd1;
                    if (pos == s_len - 16'd1) begin
                        if (s_last) begin playing <= 1'b0; done <= 1'b1; end
                        else begin si <= si + 4'd1; load <= 1'b1; end
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------ mix (two registered steps), PWM
    reg  signed [17:0] mA, mB, mN;
    reg  signed [19:0] mix;
    wire signed [19:0] lvl = mix >>> 8;
    reg  [7:0]  pcnt;
    always @(posedge clk) begin
        mA  <= wA * $signed({1'b0, volA[23:16]});
        mB  <= wB * $signed({1'b0, volB[23:16]});
        mN  <= (lp * $signed({1'b0, volN})) <<< 1;        // noise x 2: as loud as the tones
        mix <= mA + mB + mN;
        duty <= (lvl > 20'sd127) ? 8'd255 : (lvl < -20'sd128) ? 8'd0 : lvl[7:0] + 8'd128;
        pcnt <= pcnt + 8'd1;
        pwm  <= playing && (pcnt < duty);
        if (rst) begin pcnt <= 8'd0; pwm <= 1'b0; duty <= 8'd128; end
    end
endmodule

`default_nettype wire
