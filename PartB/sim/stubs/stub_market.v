`timescale 1ns / 1ps
`default_nettype none

// stub_market: fake price bus standing in for A's market engine.
//
// Ticks come from tick_req (testbench) and, if TICK_DIV != 0, every TICK_DIV
// clocks. On a tick all four prices step by `mode` and tick pulses on the
// same clock the new prices appear.
//   mode 0  constant
//   mode 1  ramp up   ~1 % per tick  (p * 41 / 4096)
//   mode 2  ramp down ~1 % per tick, floor $1.00
//   mode 3  gap down  1/8 per tick,  floor $1.00
// force_en sets one price immediately, without a tick (scripted jumps).
// Synthesisable, so it can drive Part B on the board before A is integrated.
module stub_market #(
    parameter [15:0] P0       = 16'd10000,
    parameter [15:0] P1       = 16'd4520,
    parameter [15:0] P2       = 16'd8800,
    parameter [15:0] P3       = 16'd1230,
    parameter        TICK_DIV = 0,
    parameter [15:0] FLOOR    = 16'd100
) (
    input  wire        clk,
    input  wire        sys_reset,
    input  wire [1:0]  mode,
    input  wire        tick_req,
    input  wire        force_en,
    input  wire [1:0]  force_stock,
    input  wire [15:0] force_price,
    output reg  [15:0] price0,
    output reg  [15:0] price1,
    output reg  [15:0] price2,
    output reg  [15:0] price3,
    output reg         tick
);
    localparam M_CONST = 2'd0, M_UP = 2'd1, M_DOWN = 2'd2, M_GAP = 2'd3;

    function [15:0] step;
        input [15:0] p;
        input [1:0]  m;
        reg   [31:0] d;
        reg   [16:0] up;
        reg   [15:0] g;
        begin
            d  = ({16'd0, p} * 32'd41) >> 12;
            up = {1'b0, p} + d[16:0];
            g  = p >> 3;
            case (m)
                M_UP:    step = up[16] ? 16'hFFFF : up[15:0];
                M_DOWN:  step = ({16'd0, p} > {16'd0, FLOOR} + d) ? p - d[15:0] : FLOOR;
                M_GAP:   step = (p - g > FLOOR) ? p - g : FLOOR;
                default: step = p;
            endcase
        end
    endfunction

    reg [31:0] div;
    wire auto_tick = (TICK_DIV != 0) && (div == TICK_DIV - 1);

    always @(posedge clk) begin
        if (sys_reset) begin
            price0 <= P0;
            price1 <= P1;
            price2 <= P2;
            price3 <= P3;
            tick   <= 1'b0;
            div    <= 32'd0;
        end else begin
            tick <= 1'b0;
            div  <= auto_tick ? 32'd0 : div + 32'd1;
            if (auto_tick || tick_req) begin
                price0 <= step(price0, mode);
                price1 <= step(price1, mode);
                price2 <= step(price2, mode);
                price3 <= step(price3, mode);
                tick   <= 1'b1;
            end else if (force_en) begin
                case (force_stock)
                    2'd0:    price0 <= force_price;
                    2'd1:    price1 <= force_price;
                    2'd2:    price2 <= force_price;
                    default: price3 <= force_price;
                endcase
            end
        end
    end
endmodule

`default_nettype wire
