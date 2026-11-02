`timescale 1ns / 1ps
///////////
// instantiate via:
// slower_ticker #(.MAX_COUNT(9_999)) slower_ticker_inst (
//     .clk(clk), 
//     .ticker(ticker)
//     )
///////////


module slower_ticker #(
    parameter MAX_COUNT = 9_999
    )(
    input clk,
    output reg ticker = 0
    );

    reg [31:0] counter = 0;
    
    always @(posedge clk) begin
        counter <= (counter==MAX_COUNT) ? 0 : counter + 1;
        ticker <= (counter==MAX_COUNT);
    end
    
endmodule
