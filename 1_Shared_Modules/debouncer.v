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


module debouncer #(
    parameter DEBOUNCE_CTR = 19_999_999 //default 0.2s
    )(
    input clk,
    input btn,
    output reg debounced = 1'b0
    );

    reg btn_locked = 1'b0;
    reg [31:0] ctr = 32'b0;
    
    always @(posedge clk) begin
        if (btn_locked) begin
            if (ctr != DEBOUNCE_CTR) begin //not reached debounce ctr yet -> increment
                ctr <= ctr + 1'b1;
            end else begin //release btn lock
                btn_locked <= 1'b0;
            end
            
            if (debounced==1'b1 && !btn) debounced <= 1'b0;
            
        end else if (btn) begin //btn pressed -> start debounce ctr;
            ctr <= 32'd0;
            btn_locked <= 1'b1;
            debounced <= 1'b1;
        end
    end

endmodule
