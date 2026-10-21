`timescale 1ns / 1ps

///////////
// instantiate via:
// wire out_clk;
// slower_clk #(.MAX_COUNT(9_999)) slower_clk_inst (
//     .clk(clk),
//     .out_clk(out_clk)
//     );
///////////

module slower_clk #(
    parameter MAX_COUNT = 9_999
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