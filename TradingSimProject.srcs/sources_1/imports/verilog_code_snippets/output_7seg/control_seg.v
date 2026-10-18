`timescale 1ns / 1ps

///////////////
// 
///////////////

//program flow goes like this:
//- led is controlled by switches
//- toggle mode controls a module that keeps track of current mode

module control_seg(
    input clk,
    input [2:0] mode,
    input rst,
    output reg [3:0] an = ~4'b0,
    output reg [7:0] seg = ~8'b0
    );
        
    wire [1:0] active_anode;
    get_active_anode get_active_anode_inst (clk, active_anode);
    
    // all rendering code goes in here
    wire [31:0] temp_seg;
    seg_mode_switcher seg_mode_switcher_inst (
        .clk(clk),
        .mode(mode),
        .reset(rst),
        .all_seg(temp_seg)
    );
        
    always @(*) begin
        case(active_anode)
            2'd0: begin
                seg = temp_seg[7:0];
                an = 4'b1110;
            end
            2'd1: begin
                seg = temp_seg[15:8];
                an = 4'b1101;
            end
            2'd2: begin
                seg = temp_seg[23:16];
                an = 4'b1011;
            end
            2'd3: begin
                seg = temp_seg[31:24];
                an = 4'b0111;
            end
            default: begin
                seg = ~8'b0;
                an = 4'b1111;
            end
        endcase
    end
    
endmodule
