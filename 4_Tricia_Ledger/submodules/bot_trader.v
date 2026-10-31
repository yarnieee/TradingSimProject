`timescale 1ns / 1ps
// bot_trader.v: 8-day moving-average momentum bot (Member C)
// Trades against the player through its OWN copy of ledger.v, using the same
// fill bus and ledger_busy handshake as Member B's exec_engine.
//
// On every tick (one trading day) the 4 stocks are processed one after another
// by a single FSM:
//   1. Moving average: ring buffer of the last 8 prices + running sum
//        sum = sum + new - oldest,  MA = sum >> 3          (no divider)
//      On the first tick after reset all 8 slots are filled with today's price
//      (sum = 8 x price), so the bot can trade from day 1.
//   2. band = MA >> 8 (~0.4%), a dead zone so noise around the MA is ignored.
//   3. BUY  QTY at ask = price + SPREAD if run, holds none, price > MA + band
//           and ask*QTY + FEE <= cash.
//      SELL the whole position at bid = price - SPREAD (min 1) if run,
//           holds some, and price + band < MA.
//   4. At most one fill per stock per tick. After a fill, wait for ledger_busy
//      to go high and then low again before moving to the next stock.
// tick_done pulses when all 4 stocks are finished (bot's cash/positions final).
//
//   IDLE --tick--> UPD -> DECIDE --trade--> SEND -> WAIT_HI -> WAIT_LO -> NEXT
//                   ^        \--no trade--------------------------------> NEXT
//                   \------------------- k < 3 ------------------------- NEXT --k = 3--> IDLE
module bot_trader #(
    parameter QTY    = 20,       // shares per buy
    parameter SPREAD = 5,        // cents per side (same as spread_calc)
    parameter FEE    = 100       // cents per trade (same as exec_engine)
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        run,                          // 1 = allowed to trade
    input  wire        tick,                         // 1-clock pulse, one trading day
    input  wire [15:0] price0, price1, price2, price3,   // mid prices (cents)
    // from the bot's own ledger
    input  wire [31:0] cash,
    input  wire [9:0]  pos0, pos1, pos2, pos3,
    input  wire        ledger_busy,
    // fill bus to the bot's ledger (fields hold their value after the pulse)
    output reg         fill,
    output reg  [1:0]  fill_stock,
    output reg         fill_side,                    // 0 = buy, 1 = sell
    output reg  [7:0]  fill_qty,
    output reg  [15:0] fill_price,
    output reg  [15:0] fill_fee,
    // bot's most recent trade (for Member D to display)
    output reg         last_valid,
    output reg  [1:0]  last_stock,
    output reg         last_side,
    output reg  [7:0]  last_qty,
    output reg  [15:0] last_price,
    output reg         tick_done                     // 1-clock pulse, this tick's trades finished
);
    localparam [2:0] IDLE = 3'd0, UPD = 3'd1, DECIDE = 3'd2, SEND = 3'd3,
                     WAIT_HI = 3'd4, WAIT_LO = 3'd5, NEXT = 3'd6;
    localparam [15:0] FEE16 = FEE;
    localparam [7:0]  QTY8  = QTY;

    reg [2:0]  state;
    reg [1:0]  k;                     // stock being processed (0..3)
    reg        first;                 // 1 until the first tick after reset is done

    // price history: 8 slots per stock, slot address = {stock, wptr}
    reg [15:0] hist [0:31];
    reg [18:0] sum  [0:3];            // 8 x 65535 fits in 19 bits
    reg [2:0]  wptr;                  // oldest slot (shared: all stocks advance together)
    reg [15:0] p_l  [0:3];            // prices latched on tick

    // ---------------- datapath for stock k ----------------
    wire [15:0] p      = p_l[k];
    wire [15:0] oldest = hist[{k, wptr}];
    wire [18:0] sum_up = sum[k] + p - oldest;        // sum after today's price goes in

    wire [15:0] ma   = sum[k][18:3];                 // sum >> 3 (read in DECIDE, after UPD)
    wire [15:0] band = {8'd0, ma[15:8]};             // MA >> 8

    reg  [9:0]  pos_k;
    always @* begin
        case (k)
            2'd0:    pos_k = pos0;
            2'd1:    pos_k = pos1;
            2'd2:    pos_k = pos2;
            default: pos_k = pos3;
        endcase
    end

    // bid/ask, same rule as spread_calc
    wire [16:0] ask_full = {1'b0, p} + SPREAD;
    wire [15:0] ask      = ask_full[16] ? 16'hFFFF : ask_full[15:0];
    wire [15:0] bid      = (p > SPREAD) ? p - SPREAD : 16'd1;

    // 17-bit compares so MA + band can't overflow
    wire [31:0] buy_cost = ask * QTY + FEE;
    wire want_buy  = run && (pos_k == 10'd0) && ({1'b0, p} > {1'b0, ma} + band)
                         && (buy_cost <= cash);
    wire want_sell = run && (pos_k != 10'd0) && ({1'b0, p} + band < {1'b0, ma});

    // ---------------- control FSM ----------------
    integer j;
    always @(posedge clk) begin
        fill      <= 1'b0;                           // pulses default low
        tick_done <= 1'b0;
        if (rst) begin
            state      <= IDLE;
            k          <= 2'd0;
            first      <= 1'b1;
            wptr       <= 3'd0;
            fill_stock <= 2'd0;
            fill_side  <= 1'b0;
            fill_qty   <= 8'd0;
            fill_price <= 16'd0;
            fill_fee   <= 16'd0;
            last_valid <= 1'b0;
            last_stock <= 2'd0;
            last_side  <= 1'b0;
            last_qty   <= 8'd0;
            last_price <= 16'd0;
        end else begin
            case (state)
            IDLE: if (tick) begin                    // snapshot the day's prices
                p_l[0] <= price0; p_l[1] <= price1; p_l[2] <= price2; p_l[3] <= price3;
                k      <= 2'd0;
                state  <= UPD;
            end

            UPD: begin                               // put today's price into the history
                if (first) begin
                    for (j = 0; j < 8; j = j + 1) hist[k*8 + j] <= p;
                    sum[k] <= {p, 3'b000};           // 8 x price
                end else begin
                    hist[{k, wptr}] <= p;            // overwrite the oldest
                    sum[k]          <= sum_up;
                end
                state <= DECIDE;
            end

            DECIDE: begin                            // MA/band now include today
                if (want_buy) begin
                    fill_stock <= k; fill_side <= 1'b0; fill_qty <= QTY8;
                    fill_price <= ask; fill_fee <= FEE16;
                    state      <= SEND;
                end else if (want_sell) begin
                    // the bot only ever holds QTY shares, so the position fits in 8 bits
                    fill_stock <= k; fill_side <= 1'b1; fill_qty <= pos_k[7:0];
                    fill_price <= bid; fill_fee <= FEE16;
                    state      <= SEND;
                end else
                    state <= NEXT;
            end

            SEND: begin                              // one-clock fill pulse
                fill       <= 1'b1;
                last_valid <= 1'b1;
                last_stock <= fill_stock; last_side <= fill_side;
                last_qty   <= fill_qty;   last_price <= fill_price;
                state      <= WAIT_HI;
            end

            WAIT_HI: if (ledger_busy)  state <= WAIT_LO;   // ledger has taken the fill
            WAIT_LO: if (!ledger_busy) state <= NEXT;      // cash/positions updated

            NEXT: begin
                if (k == 2'd3) begin                 // all 4 stocks done for today
                    if (!first) wptr <= wptr + 1'b1; // next oldest slot
                    first     <= 1'b0;
                    tick_done <= 1'b1;
                    state     <= IDLE;
                end else begin
                    k     <= k + 1'b1;
                    state <= UPD;
                end
            end

            default: state <= IDLE;
            endcase
        end
    end
endmodule
