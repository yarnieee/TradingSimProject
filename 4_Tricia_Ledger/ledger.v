`timescale 1ns / 1ps
// ledger.v: portfolio ledger, top of the ledger block (Member C)
// Datapath: holds cash, positions, cost basis (incl. buy fees) and realised P&L,
// and wires together the three sub-modules:
//   ledger_validate  - is this fill allowed? does a sell close the whole position?
//   ledger_fsm       - control state machine, drives ledger_busy and err
//   seq_divider      - average cost = cost basis / position (partial sells only)
// Invariant (always true when idle): cash + sum(cost_basis) == START_CASH + realised
module ledger #(parameter [31:0] START_CASH = 32'd1_000_000) (   // cents ($10,000)
    input  wire        clk,
    input  wire        rst,          // also used for new game
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
    output wire        ledger_busy,  // B must not check/send the next order while high
    output wire        err           // 1-cycle pulse when a fill is rejected
);
    // ---------------- state registers ----------------
    reg [9:0]  pos [0:3];
    reg [31:0] cb  [0:3];
    assign pos0 = pos[0]; assign pos1 = pos[1]; assign pos2 = pos[2]; assign pos3 = pos[3];
    assign cb0  = cb[0];  assign cb1  = cb[1];  assign cb2  = cb[2];  assign cb3  = cb[3];

    // latched copy of the fill being processed
    reg [1:0]  s_l;
    reg [7:0]  q_l;
    reg [23:0] v_l;       // trade value = price * qty
    reg [15:0] f_l;
    reg [31:0] removed;   // cost basis removed by a sell

    // ---------------- arithmetic ----------------
    wire [23:0] value_in = fill_price * fill_qty;
    wire [31:0] cost_in  = value_in + fill_fee;
    wire [31:0] cost_l   = v_l + f_l;

    // ---------------- sub-module: validation ----------------
    wire reject, full_close;
    ledger_validate u_val (
        .fill_side(fill_side), .fill_qty(fill_qty), .cost_in(cost_in),
        .cash(cash), .pos_sel(pos[fill_stock]),
        .reject(reject), .full_close(full_close)
    );

    // ---------------- sub-module: control FSM ----------------
    wire latch, take_full, take_avg, do_buy, do_apply, div_start, div_done;
    ledger_fsm u_fsm (
        .clk(clk), .rst(rst), .fill(fill), .fill_side(fill_side),
        .reject(reject), .full_close(full_close), .div_done(div_done),
        .ledger_busy(ledger_busy), .latch(latch), .take_full(take_full),
        .take_avg(take_avg), .do_buy(do_buy), .do_apply(do_apply),
        .div_start(div_start), .err(err)
    );

    // ---------------- sub-module: divider ----------------
    wire [31:0] div_q, div_r;
    wire        div_busy;
    seq_divider #(.W(32)) u_div (
        .clk(clk), .rst(rst), .start(div_start),
        .dividend(cb[s_l]), .divisor({22'd0, pos[s_l]}),
        .quotient(div_q), .remainder(div_r),
        .busy(div_busy), .done(div_done)
    );
    wire [39:0] avg_x_q = div_q * q_l;

    // realised change for a sell: proceeds - removed cost - fee (signed)
    wire signed [33:0] delta = $signed({10'd0, v_l}) - $signed({2'b0, removed}) - $signed({18'd0, f_l});

    // ---------------- register updates (driven by the FSM) ----------------
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            cash     <= START_CASH;
            realised <= 0;
            for (i = 0; i < 4; i = i + 1) begin
                pos[i] <= 0;
                cb[i]  <= 0;
            end
        end else begin
            if (latch) begin
                s_l <= fill_stock; q_l <= fill_qty; v_l <= value_in; f_l <= fill_fee;
            end
            if (take_full) removed <= cb[fill_stock];
            if (take_avg)  removed <= avg_x_q[31:0];

            if (do_buy) begin
                cash     <= cash - cost_l;
                pos[s_l] <= pos[s_l] + q_l;
                cb[s_l]  <= cb[s_l] + cost_l;
            end
            if (do_apply) begin
                cash     <= cash + v_l - f_l;
                realised <= realised + delta[31:0];
                cb[s_l]  <= cb[s_l] - removed;
                pos[s_l] <= pos[s_l] - q_l;
            end
        end
    end
endmodule
