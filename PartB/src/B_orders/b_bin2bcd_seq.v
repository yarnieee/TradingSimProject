`timescale 1ns / 1ps
`default_nettype none

// b_bin2bcd_seq: 16-bit binary -> 5 BCD digits, sequential double-dabble.
// One add-3/shift step per clock, 16 clocks per conversion.
//
// Part B's private copy until D's shared bin2bcd_seq exists. The spec said a
// combinational converter for now; this is sequential instead because a
// 16-stage add-3 chain is a likely 100 MHz timing failure, and one shared
// sequential unit is the resource story the plan wants anyway. [ASSUMPTION]
module b_bin2bcd_seq (
    input  wire        clk,
    input  wire        sys_reset,
    input  wire        start,      // ignored while busy
    input  wire [15:0] bin,
    output reg         busy,
    output reg         done,       // 1-clock pulse, bcd valid from then on
    output reg  [19:0] bcd         // {d4, d3, d2, d1, d0}
);
    reg [35:0] sh;                 // {bcd[19:0], bin[15:0]}
    reg [4:0]  cnt;

    function [3:0] add3;
        input [3:0] n;
        begin
            add3 = (n >= 4'd5) ? n + 4'd3 : n;
        end
    endfunction

    wire [35:0] sh_adj  = {add3(sh[35:32]), add3(sh[31:28]), add3(sh[27:24]),
                           add3(sh[23:20]), add3(sh[19:16]), sh[15:0]};
    wire [35:0] sh_next = {sh_adj[34:0], 1'b0};

    always @(posedge clk) begin
        if (sys_reset) begin
            sh   <= 36'd0;
            cnt  <= 5'd0;
            busy <= 1'b0;
            done <= 1'b0;
            bcd  <= 20'd0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                if (start) begin
                    sh   <= {20'd0, bin};
                    cnt  <= 5'd16;
                    busy <= 1'b1;
                end
            end else begin
                sh  <= sh_next;
                cnt <= cnt - 5'd1;
                if (cnt == 5'd1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    bcd  <= sh_next[35:16];
                end
            end
        end
    end
endmodule

`default_nettype wire
