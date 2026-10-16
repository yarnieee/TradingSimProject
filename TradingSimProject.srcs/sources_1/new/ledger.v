`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.10.2026 14:00:43
// Design Name: 
// Module Name: ledger
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



// Applies fills from B: tracks cash, positions, cost basis (incl. buy fees) and realised P&L.
// Invariant (always true when idle): cash + sum(cost_basis) == START_CASH + realised
module ledger #(parameter [31:0] START_CASH = 32'd1_000_000) (   // cents ($10,000)
    input  wire        clk,
    input  wire        rst,          
    // fill bus from B
    input  wire        fill,         // 1-cycle pulse
    input  wire [1:0]  fill_stock,
    input  wire        fill_side,    // 0 = buy, 1 = sell
    input  wire [7:0]  fill_qty,
    input  wire [15:0] fill_price,   // cents
    input  wire [15:0] fill_fee,     // cents
    // ledger outputs
    output reg  [31:0] cash,
    output wire [9:0]  pos0, pos1, pos2, pos3,
    output wire [31:0] cb0,  cb1,  cb2,  cb3,
    output reg  signed [31:0] realised,
    output wire        busy,         // high while a sell is processing: B must wait
    output reg         err           // 1-cycle pulse when a fill is rejected
);
    reg [9:0]  pos [0:3];
    reg [31:0] cb  [0:3];
    assign pos0 = pos[0]; assign pos1 = pos[1]; assign pos2 = pos[2]; assign pos3 = pos[3];
    assign cb0  = cb[0];  assign cb1  = cb[1];  assign cb2  = cb[2];  assign cb3  = cb[3];

    localparam IDLE = 2'd0, DIV = 2'd1, APPLY = 2'd2;
    reg [1:0] state;
    assign busy = (state != IDLE);

    // latched copy of the fill being processed
    reg [1:0]  s_l;
    reg [7:0]  q_l;
    reg [23:0] v_l;       // trade value = price * qty
    reg [15:0] f_l;
    reg [31:0] removed;   // cost basis removed by a sell

    // values computed straight from the incoming fill
    wire [23:0] value_in = fill_price * fill_qty;
    wire [31:0] cost_in  = value_in + fill_fee;
    wire [10:0] newpos   = pos[fill_stock] + fill_qty;   // 11 bits so overflow is visible

    // divider: avg cost = cost_basis / pos
    reg         div_start;
    wire [31:0] div_q, div_r;
    wire        div_busy, div_done;
    seq_divider #(.W(32)) u_div (
        .clk(clk), .rst(rst), .start(div_start),
        .dividend(cb[s_l]), .divisor({22'd0, pos[s_l]}),
        .quotient(div_q), .remainder(div_r),
        .busy(div_busy), .done(div_done)
    );
    wire [39:0] avg_x_q = div_q * q_l;

    // realised change for a sell: proceeds - removed cost - fee (signed)
    wire signed [33:0] delta = $signed({10'd0, v_l}) - $signed({2'b0, removed}) - $signed({18'd0, f_l});

    integer i;
    always @(posedge clk) begin
        err       <= 1'b0;
        div_start <= 1'b0;
        if (rst) begin
            cash     <= START_CASH;
            realised <= 0;
            state    <= IDLE;
            for (i = 0; i < 4; i = i + 1) begin
                pos[i] <= 0;
                cb[i]  <= 0;
            end
        end else begin
            case (state)
            IDLE: if (fill) begin
                s_l <= fill_stock; q_l <= fill_qty; v_l <= value_in; f_l <= fill_fee;
                if (fill_qty == 0) begin
                    err <= 1'b1;
                end else if (fill_side == 1'b0) begin                    //BUY
                    if (cost_in > cash || newpos > 11'd1023)
                        err <= 1'b1;
                    else begin
                        cash            <= cash - cost_in;
                        pos[fill_stock] <= newpos[9:0];
                        cb[fill_stock]  <= cb[fill_stock] + cost_in;
                    end
                end else begin                                           // SELL
                    if (fill_qty > pos[fill_stock])
                        err <= 1'b1;
                    else if (fill_qty == pos[fill_stock]) begin          // full close, no divide
                        removed <= cb[fill_stock];
                        state   <= APPLY;
                    end else begin                                       // partial, need avg cost
                        div_start <= 1'b1;
                        state     <= DIV;
                    end
                end
            end

            DIV: if (div_done) begin
                removed <= avg_x_q[31:0];
                state   <= APPLY;
            end

            APPLY: begin
                cash       <= cash + v_l - f_l;
                realised   <= realised + delta[31:0];
                cb[s_l]    <= cb[s_l] - removed;
                pos[s_l]   <= pos[s_l] - q_l;
                state      <= IDLE;
            end

            default: state <= IDLE;
            endcase
        end
    end
endmodule
