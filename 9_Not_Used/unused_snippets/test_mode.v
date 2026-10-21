`timescale 1ns / 1ps

/////////////
// TEST FSM, use switches 0-7 to toggle each of these modes.
// instantiate via:
// test_mode test_mode_inst (
//     .clk(clk),
//     .btn(btn),
//     .sw(sw),
//     .rst(rst),
//     .mode(mode)
// )
/////////////

module test_mode(
    input clk,
    input [4:0] btn,
    input [15:0] sw,
    input rst,
    output reg [2:0] mode = 3'b0
    ); // can count 8 modes 0-7

    reg [2:0] next_state;

    always @(*) begin
        next_state = mode; //default

        if (sw[0]) next_state = 3'd0;
        if (sw[1]) next_state = 3'd1;
        if (sw[2]) next_state = 3'd2;
        if (sw[3]) next_state = 3'd3;
        if (sw[4]) next_state = 3'd4;
        if (sw[5]) next_state = 3'd5;
        if (sw[6]) next_state = 3'd6;
        if (sw[7]) next_state = 3'd7;
    end

    always @(posedge clk) begin //if async reset then add posedge rst
        if (rst) begin
            mode <= 3'b0;
        end else begin
            mode <= next_state;
        end
    end
        
endmodule
