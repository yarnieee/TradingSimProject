`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// B_sound_top: sound effects on the JXADC port (Douglas).
//
//   sound      when                                              priority
//   CLICK      any button (moving or selecting)                     1
//   UP / DOWN  BTNU / BTND on the quantity screen                   2
//   ERROR      on the quantity screen, a BTNU that makes the order   2
//              fail (not enough cash, too few shares, over 255), or
//              a BTND with the quantity already 0: one low "EHHH"
//   WOOSH      an order is sent (ord_req)                           3
//   BELL       one of your orders fills (also later, from the book)  4
//   GAME END   the game-over screen starts                          5
// A sound starts if nothing plays or it ranks at least as high as the one
// playing. A fill during the woosh waits for it (woosh, then bell).
// mute (sw12 up) silences everything and switches the amplifier off.
//
// Outputs, for a Pmod AMP2 on JXADC (top row): pin 1 aud_pwm (audio),
// pin 2 aud_gain (1: 6 dB), pin 4 aud_sd_n (1: amplifier on). A small speaker
// or piezo also works between pin 1 and GND.
module B_sound_top #(
    parameter integer SAMPLE_SHIFT = 11              // 48.8 kHz samples (the test uses fewer clocks)
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       mute,                          // synchronised
    input  wire [4:0] btn_pulse,                     // {D, R, L, U, C}, one clock per press
    input  wire [3:0] screen_state,
    input  wire       order_ok,                      // the order on screen passes Matthew's checks
    input  wire [2:0] order_code,                    // if not, why (RJ_*)
    input  wire       qty_zero,                      // the quantity is 0
    input  wire       ord_req,                       // an order sent from the review screen
    input  wire       fill,                          // one of your orders filled
    output wire       aud_pwm,
    output wire       aud_gain,
    output wire       aud_sd_n,
    output reg  [2:0] now_playing                    // 0 none, else the priority above (for tests / LEDs)
);
    localparam [2:0] P_CLICK = 3'd1, P_UPDN = 3'd2, P_WOOSH = 3'd3, P_BELL = 3'd4, P_END = 3'd5;
    localparam [3:0] S_CLICK = 4'd0, S_UP = 4'd1, S_DOWN = 4'd3, S_WOOSH = 4'd5, S_BELL = 4'd6, S_END = 4'd7,
                     S_ERR = 4'd11;

    // ------------------------------------------------------------ events
    reg  [3:0] state_d;
    always @(posedge clk) state_d <= rst ? `UI_TITLE : screen_state;
    wire on_qty  = (screen_state == `UI_QUANTITY);
    wire ev_end  = (screen_state == `UI_GAME_END) && (state_d != `UI_GAME_END);
    wire ev_up   = on_qty && btn_pulse[1];
    wire ev_down = on_qty && btn_pulse[4];
    wire ev_click = (|btn_pulse) && !ev_up && !ev_down;

    // ERROR: the check of the order is a few clocks behind the button (the
    // quantity, then price x quantity, then the check), so a BTNU is judged
    // 6 clocks later; a BTND at quantity 0 is known at once
    reg  [2:0] up_wait;
    always @(posedge clk)
        if (rst)                  up_wait <= 3'd0;
        else if (ev_up)           up_wait <= 3'd6;
        else if (up_wait != 3'd0) up_wait <= up_wait - 3'd1;
    wire bad_qty = !order_ok && ((order_code == `RJ_NO_CASH) || (order_code == `RJ_NO_POS) ||
                                 (order_code == `RJ_BAD_QTY));
    wire ev_err  = on_qty && (((up_wait == 3'd1) && bad_qty) || (ev_down && qty_zero));

    // the highest event this clock
    reg  [2:0] e_pri;
    reg  [3:0] e_seg;
    always @* begin
        e_pri = 3'd0; e_seg = S_CLICK;
        if      (ev_end)   begin e_pri = P_END;   e_seg = S_END;   end
        else if (fill)     begin e_pri = P_BELL;  e_seg = S_BELL;  end
        else if (ord_req)  begin e_pri = P_WOOSH; e_seg = S_WOOSH; end
        else if (ev_err)   begin e_pri = P_UPDN;  e_seg = S_ERR;   end   // replaces the blip just started
        else if (ev_up)    begin e_pri = P_UPDN;  e_seg = S_UP;    end
        else if (ev_down)  begin e_pri = P_UPDN;  e_seg = S_DOWN;  end
        else if (ev_click) begin e_pri = P_CLICK; e_seg = S_CLICK; end
    end

    // ------------------------------------------------------------ which sound plays
    wire playing, done;
    reg  start, bell_wait;
    reg  [3:0] start_seg;
    always @(posedge clk) begin
        start <= 1'b0;
        if (rst || mute) begin
            now_playing <= 3'd0;
            bell_wait   <= 1'b0;
        end else begin
            if (done) now_playing <= 3'd0;
            if (e_pri == P_BELL && now_playing == P_WOOSH && !done)
                bell_wait <= 1'b1;                               // woosh first, then the bell
            else if (e_pri != 3'd0 && (now_playing == 3'd0 || done || e_pri >= now_playing)) begin
                start <= 1'b1; start_seg <= e_seg; now_playing <= e_pri;
                if (e_pri == P_END) bell_wait <= 1'b0;
            end else if (done && bell_wait) begin
                start <= 1'b1; start_seg <= S_BELL; now_playing <= P_BELL;
                bell_wait <= 1'b0;
            end
        end
    end

    wire pwm;
    sound_synth #(.SAMPLE_SHIFT(SAMPLE_SHIFT)) u_synth (
        .clk(clk), .rst(rst || mute), .start(start), .start_seg(start_seg),
        .playing(playing), .done(done), .duty(), .pwm(pwm)
    );

    assign aud_pwm  = pwm;
    assign aud_gain = 1'b1;
    assign aud_sd_n = !mute;
endmodule

`default_nettype wire
