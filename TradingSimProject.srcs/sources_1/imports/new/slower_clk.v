`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.09.2026 10:38:46
// Design Name: 
// Module Name: slower_clk
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module slower_clk #(
    parameter MAX_COUNT = 9999
    )(
    input clk,
    output reg out_clk = 0
    );

    reg [31:0] counter = 0;
    
    always @(posedge clk) begin
        counter <= (counter==MAX_COUNT) ? 0 : counter + 1;
        if (counter==MAX_COUNT) out_clk <= ~out_clk;
    end
    
endmodule