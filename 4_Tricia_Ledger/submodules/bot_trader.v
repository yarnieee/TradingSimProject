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
//   IDLE --tick--> UPD -> PREP -> DECIDE --trade--> SEND -> WAIT_HI -> WAIT_LO -> NEXT
//                   ^                \--no trade--------------------------------> NEXT
//                   \------------------------ k < 3 ---------------------------- NEXT --k = 3--> IDLE
// PREP registers ask, bid and ask*QTY + FEE, so DECIDE only compares registers.
// (In one clock, price mux -> ask -> multiply -> compare -> fill_price failed 100 MHz.)
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
    output reg         tick_done,                    // 1-clock pulse, this tick's trades finished
    output reg  [7:0]  signals                       // per stock: 0 neutral, 1 above, 2 below MA band
);
    localparam [3:0] IDLE = 4'd0, UPD = 4'd1, DECIDE = 4'd2, SEND = 4'd3,
                     WAIT_HI = 4'd4, WAIT_LO = 4'd5, NEXT = 4'd6, INIT = 4'd7,
                     PREP = 4'd8;
    localparam [15:0] FEE16 = FEE;
    localparam [7:0]  QTY8  = QTY;

    reg [3:0]  state;
    reg [1:0]  k;                     // stock being processed (0..3)
    reg        first;                 // 1 until the first tick after reset is done

    // price history: 8 slots per stock, slot address = {stock, wptr}
    // One asynchronous read and ONE synchronous write permit a 32x16 LUTRAM.
    // Do not reset this array or initialize eight addresses in one clock.
    // INIT writes all eight copies before the first DECIDE for each stock.
    (* ram_style = "distributed" *) reg [15:0] hist [0:31];
    reg [18:0] sum  [0:3];            // 8 x 65535 fits in 19 bits
    reg [2:0]  wptr;                  // oldest slot (shared: all stocks advance together)
    reg [2:0]  init_slot;
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
    wire [31:0] buy_cost = ask * QTY + FEE;          // registered in PREP
    reg  [31:0] r_cost;
    reg  [15:0] r_ask, r_bid;
    wire want_buy  = run && (pos_k == 10'd0) && ({1'b0, p} > {1'b0, ma} + band)
                         && (r_cost <= cash);
    wire want_sell = run && (pos_k != 10'd0) && ({1'b0, p} + band < {1'b0, ma});

    wire history_write = !rst && ((state == INIT) || ((state == UPD) && !first));
    wire [4:0] history_address = {k, (state == INIT) ? init_slot : wptr};
    always @(posedge clk) begin
        if (history_write) hist[history_address] <= p;
    end

    // ---------------- control FSM ----------------
    always @(posedge clk) begin
        fill      <= 1'b0;                           // pulses default low
        tick_done <= 1'b0;
        if (rst) begin
            state      <= IDLE;
            k          <= 2'd0;
            first      <= 1'b1;
            wptr       <= 3'd0;
            init_slot  <= 3'd0;
            signals    <= 8'd0;
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
                    init_slot <= 3'd0;
                    sum[k] <= {p, 3'b000};           // 8 x price
                    state <= INIT;
                end else begin
                    sum[k]          <= sum_up;
                    state <= PREP;
                end
            end

            INIT: begin
                // The separate single-port memory process writes this slot.
                if (init_slot == 3'd7) state <= PREP;
                else init_slot <= init_slot + 1'b1;
            end

            PREP: begin                              // price maths for stock k, one clock
                r_ask  <= ask;
                r_bid  <= bid;
                r_cost <= buy_cost;
                state  <= DECIDE;
            end

            DECIDE: begin                            // MA/band now include today
                signals[2*k +: 2] <= ({1'b0, p} > {1'b0, ma} + band) ? 2'd1 :
                                    ({1'b0, p} + band < {1'b0, ma}) ? 2'd2 : 2'd0;
                if (want_buy) begin
                    fill_stock <= k; fill_side <= 1'b0; fill_qty <= QTY8;
                    fill_price <= r_ask; fill_fee <= FEE16;
                    state      <= SEND;
                end else if (want_sell) begin
                    // the bot only ever holds QTY shares, so the position fits in 8 bits
                    fill_stock <= k; fill_side <= 1'b1; fill_qty <= pos_k[7:0];
                    fill_price <= r_bid; fill_fee <= FEE16;
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
