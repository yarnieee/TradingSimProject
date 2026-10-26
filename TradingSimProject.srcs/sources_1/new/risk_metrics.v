`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 26.10.2026 11:22:51
// Design Name: 
// Module Name: risk_metrics
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


// risk_metrics.v: mark-to-market every tick (Member C)
// On each tick from A (prices are stable then):
//   upnl[i]   = pos[i] * price[i] - cost_basis[i]      unrealised P&L per stock (cents)
//   equity    = cash + sum(pos[i] * price[i])          one multiplier, reused for 4 stocks
//   pnl       = equity - START_CASH
//   ret_bp    = pnl / 100                              return in basis points (+312 = +3.12%)
//   peak      = highest equity so far
//   dd_bp     = (peak - equity) * 10000 / peak         drawdown now, in basis points
//   max_dd_bp = largest dd_bp so far
// Both divides share ONE seq_divider (48-bit), run one after the other.
module risk_metrics #(parameter [31:0] START_CASH = 32'd1_000_000) (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick,                              // 1-clock pulse from A
    input  wire [15:0] price0, price1, price2, price3,    // cents, from A
    input  wire [31:0] cash,                              // from ledger
    input  wire [9:0]  pos0, pos1, pos2, pos3,            // from ledger
    input  wire [31:0] cb0, cb1, cb2, cb3,                // cost basis, from ledger
    output reg  [31:0] equity,
    output reg  signed [31:0] pnl,
    output reg  signed [31:0] ret_bp,
    output reg  signed [31:0] upnl0, upnl1, upnl2, upnl3,
    output reg  [31:0] peak,
    output reg  [31:0] dd_bp,
    output reg  [31:0] max_dd_bp,
    output reg         mtm_done                           // 1-clock pulse when everything is fresh
);
    localparam IDLE = 3'd0, MAC = 3'd1, FIN = 3'd2, DIV_RET = 3'd3, DIV_DD = 3'd4;
    reg [2:0] state;
    reg [1:0] i;                         // which stock we are adding (0..3)

    // snapshot taken on tick, so a fill mid-calculation can't mix old and new values
    reg [15:0] p_l  [0:3];
    reg [9:0]  q_l  [0:3];
    reg [31:0] cb_l [0:3];
    reg [31:0] acc;                      // running equity total

    // one shared multiplier: position x price for stock i
    wire [25:0]        value_i = q_l[i] * p_l[i];
    wire signed [32:0] upnl_i  = $signed({7'd0, value_i}) - $signed({1'b0, cb_l[i]});

    // |pnl| and its sign
    wire        neg     = pnl[31];
    wire [31:0] pnl_abs = neg ? -pnl : pnl;

    // drawdown numerator: (peak - equity) * 10000   (peak >= equity always)
    wire [47:0] dd_num = {16'd0, peak - equity} * 48'd10000;

    // ---- one shared divider, two jobs ----
    reg         div_sel;                 // 0 = return job, 1 = drawdown job
    reg         div_start;
    wire [47:0] div_q, div_r;
    wire        div_busy, div_done;
    seq_divider #(.W(48)) u_div (
        .clk(clk), .rst(rst), .start(div_start),
        .dividend(div_sel ? dd_num        : {16'd0, pnl_abs}),
        .divisor (div_sel ? {16'd0, peak} : 48'd100),
        .quotient(div_q), .remainder(div_r),
        .busy(div_busy), .done(div_done)
    );

    always @(posedge clk) begin
        div_start <= 1'b0;
        mtm_done  <= 1'b0;
        if (rst) begin
            state     <= IDLE;
            equity    <= START_CASH;
            pnl       <= 0;
            ret_bp    <= 0;
            upnl0 <= 0; upnl1 <= 0; upnl2 <= 0; upnl3 <= 0;
            peak      <= START_CASH;
            dd_bp     <= 0;
            max_dd_bp <= 0;
            div_sel   <= 1'b0;
        end else begin
            case (state)
            IDLE: if (tick) begin
                p_l[0]  <= price0; p_l[1]  <= price1; p_l[2]  <= price2; p_l[3]  <= price3;
                q_l[0]  <= pos0;   q_l[1]  <= pos1;   q_l[2]  <= pos2;   q_l[3]  <= pos3;
                cb_l[0] <= cb0;    cb_l[1] <= cb1;    cb_l[2] <= cb2;    cb_l[3] <= cb3;
                acc     <= cash;
                i       <= 2'd0;
                state   <= MAC;
            end

            MAC: begin                           // 4 clocks: one stock per clock
                acc <= acc + value_i;
                case (i)
                    2'd0: upnl0 <= upnl_i[31:0];
                    2'd1: upnl1 <= upnl_i[31:0];
                    2'd2: upnl2 <= upnl_i[31:0];
                    2'd3: upnl3 <= upnl_i[31:0];
                endcase
                i <= i + 1'b1;
                if (i == 2'd3) state <= FIN;
            end

            FIN: begin
                equity    <= acc;
                pnl       <= acc - START_CASH;
                if (acc > peak) peak <= acc;
                div_sel   <= 1'b0;               // first job: return
                div_start <= 1'b1;
                state     <= DIV_RET;
            end

            DIV_RET: if (div_done) begin
                ret_bp    <= neg ? -div_q[31:0] : div_q[31:0];
                div_sel   <= 1'b1;               // second job: drawdown
                div_start <= 1'b1;
                state     <= DIV_DD;
            end

            DIV_DD: if (div_done) begin
                dd_bp <= div_q[31:0];
                if (div_q[31:0] > max_dd_bp) max_dd_bp <= div_q[31:0];
                mtm_done <= 1'b1;
                state    <= IDLE;
            end

            default: state <= IDLE;
            endcase
        end
    end
endmodule
