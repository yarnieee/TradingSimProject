`timescale 1ns / 1ps

/////////////////
// instantiate via:
// wire [N:0] debounced_btn;
// debouncer [N:0] debouncer_inst (
//     .clk(clk),
//     .btn(btn),
//     .debounced(debounced_btn)
//     );
/////////////////

// The button is synchronised to clk (two flip-flops), then any change, press or
// release, is passed on at once and the button is ignored for DEBOUNCE_CTR
// clocks after it. So a press shows straight away and the bounce after both
// the press and the release is ignored (a bounce on release used to look like
// a second press when the button was held longer than DEBOUNCE_CTR).
module debouncer #(
    parameter DEBOUNCE_CTR = 19_999_999 //default 0.2s
    )(
    input clk,
    input btn,
    output reg debounced = 1'b0
    );

    reg btn_s0 = 1'b0, btn_s = 1'b0;     // synchronised button
    reg btn_locked = 1'b0;
    reg [31:0] ctr = 32'b0;

    always @(posedge clk) begin
        btn_s0 <= btn;
        btn_s  <= btn_s0;
        if (btn_locked) begin
            if (ctr != DEBOUNCE_CTR) //not reached debounce ctr yet -> increment
                ctr <= ctr + 1'b1;
            else //release btn lock
                btn_locked <= 1'b0;
        end else if (btn_s != debounced) begin //pressed or released -> pass it on, start debounce ctr
            debounced  <= btn_s;
            ctr        <= 32'd0;
            btn_locked <= 1'b1;
        end
    end

endmodule
