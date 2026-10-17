`timescale 1ns / 1ps
`default_nettype none

// b_demo_btn: debounce one push button and emit a 1-clock pulse per press.
// Board-demo stand-in only. In the team build, D owns debouncing and sends
// btn_pulse to B.
//   2-FF synchroniser, then the input must hold its new level for STABLE
//   clocks before the debounced state changes; pulse on the rising edge.
module b_demo_btn #(
    parameter STABLE = 1_000_000          // 10 ms at 100 MHz
) (
    input  wire clk,
    input  wire rst,
    input  wire btn,                      // raw, asynchronous
    output reg  pulse
);
    reg        s0, s1, state;
    reg [20:0] cnt;

    always @(posedge clk) begin
        s0    <= btn;
        s1    <= s0;
        pulse <= 1'b0;
        if (rst) begin
            state <= 1'b0;
            cnt   <= 21'd0;
        end else if (s1 == state) begin
            cnt <= 21'd0;
        end else if (cnt == STABLE - 1) begin
            cnt   <= 21'd0;
            state <= s1;
            pulse <= s1;                  // press, not release
        end else begin
            cnt <= cnt + 21'd1;
        end
    end
endmodule

`default_nettype wire
