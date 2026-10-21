`timescale 1ns / 1ps

///////////
// instantiate via:
// reg enable_delay_Xms;
// wire delay_Xms_done;
//
// delay #(.DELAY(99_999_999)) delay_inst (
//     .clk(clk),
//     .enable(enable_delay_Xms),
//     .done(delay_Xms_done)
//     );
//
// always @(posedge clk) begin
//     enable_delay_Xms <= 1'b1;
//     if (delay_Xms_done) begin
//         enable_delay_Xms <= 1'b0;
//         //do thing
        
//     end
// end
///////////

module delay #(
    parameter DELAY = 99_999_999 //default is 1s
    )(
    input clk,
    input enable,
    output reg done = 1'b0
    );

    reg [31:0] counter = 0;
    
    always @(posedge clk) begin
        if (enable) begin
            if (!done) begin
               counter <= counter + 1'b1;
                if (counter==DELAY) done <= 1'b1; 
            end
            //after done is set, counter value is held at DELAY until enable is released.
        end else begin
            counter <= 1'b0;
            done <= 1'b0;
        end
    end
    
endmodule