`timescale 1ns / 1ps

//////////////
// 
//////////////

module get_active_anode(
    input clk,
    output reg [1:0] active_anode = 0
    );
    
    wire slow_clk;
    slower_ticker #(99_999) ticker_1kHz (clk, slow_clk);
    
    always @(posedge slow_clk) begin
        active_anode <= (active_anode==3) ? 0 : active_anode + 1;
    end
    
endmodule
