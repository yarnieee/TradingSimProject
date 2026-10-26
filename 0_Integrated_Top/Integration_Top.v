`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// Integration_Top: everyone's part in one build (branch-team-integration, 0_Integrated_Top/).
// One block per person. Module names follow the team doc's rule
// (A_/B_/C_/D_<description>_top); instance names say whose part it is.
//
//   instance         module          owner    does
//   yian_market      A_top           Yi An    4 stock channels, one trading day every 2 s
//   douglas_orders   B_order_top     Douglas  validates and fills orders, order book, ticket page
//   tricia_ledger    ledger          Tricia   cash, positions, cost basis, ledger_busy handshake
//   tricia_bot       bot_trader      Tricia   the computer player: STUB, Tricia writes the strategy
//   matthew_display  D_display_top   Matthew  buttons, game screens, 7-seg, both OLEDs
//
// Board:
//   sw[0] (rst)   reset, as in Matthew's constraints
//   sw[1] (bot_sw) up: bot view (JB the bot against you, JA the bot's last trades)
//   buttons       Matthew's game FSM (title > portfolio > stocks > stock > buy/sell
//                 > quantity / order type > review > result)
//   JB (right)    Matthew's game screens
//   JA (left)     Douglas's order ticket (title artwork on the title screen)
//   7-seg         Matthew's quantity
//   led[7:4]      Matthew's screen_state;  led[15] fill;  led[14] reject;  led[11:8] pending orders
module Integration_Top #(
    parameter DAY_MAX_COUNT = 199_999_999,      // Yi An: 2 s per trading day
    parameter DEBOUNCE_CTR  = 32'd1_999_999,    // Matthew: 20 ms
    parameter FINAL_TRADING_DAY = 32'd30       // Game ends after this many days
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        bot_sw,          // sw[1]: show the bot
    input  wire        btnU,
    input  wire        btnD,
    input  wire        btnL,
    input  wire        btnR,
    input  wire        btnC,
    output wire [7:0]  JA,
    output wire [7:0]  JB,
    output wire [15:0] led,
    output wire [3:0]  an,
    output wire [7:0]  seg
);
    // ================================================================ reset
    reg rst_s0, sys_reset;
    always @(posedge clk) begin
        rst_s0    <= rst;
        sys_reset <= rst_s0;
    end

    // ================================================================ shared data buses
    // The market and ledger values are routed through this top level to the
    // display as well as to the order engine.
    wire [1:0]   market_state;
    wire [2:0]   market_event;
    wire         amd_ready, mcd_ready, stock2_ready, stock3_ready;
    wire [15:0]  amd_close, mcd_close, stock2_close, stock3_close;
    wire [31:0]  amd_date, mcd_date, stock2_date, stock3_date;
    wire [31:0]  stock2_volume, stock3_volume;
    wire [111:0] stock2_samples_7, stock3_samples_7;
    wire [15:0]  stock2_mean_7, stock3_mean_7;
    wire [479:0] amd_samples_30, mcd_samples_30;
    wire [479:0] stock2_samples_30, stock3_samples_30;
    wire [479:0] stock2_samples_180, stock3_samples_180;
    wire [15:0]  stock2_mean_30, stock3_mean_30;
    wire [15:0]  stock2_mean_180, stock3_mean_180;
    wire         all_stocks_ready;
    wire [31:0]  cash;
    wire [9:0]   pos0, pos1, pos2, pos3;
    wire [15:0]  price0, price1, price2, price3;
    reg          tick;
    reg  [31:0]  trading_day_count;
    wire         final_day_reached;
    wire [31:0]  portfolio_value;
    wire [959:0] portfolio_samples_30;
    wire [31:0]  cb0, cb1, cb2, cb3;
    wire [31:0]  time_remaining;

    // The game timer is expressed in remaining simulated trading days.  The
    // ledger starts with 1,000,000 cents ($10,000), and the same cash bus is
    // used by every screen so purchases and sales remain consistent.
    assign time_remaining = (trading_day_count < FINAL_TRADING_DAY) ?
                            (FINAL_TRADING_DAY - trading_day_count) : 32'd0;

    // ================================================================ MATTHEW: buttons, screens, 7-seg, both OLEDs
    wire [3:0]  screen_state;
    wire [13:0] quantity;
    wire [1:0]  sel_stock, game_state;
    wire        ord_req, ord_side;
    wire [1:0]  ord_type, ord_brk;
    wire [15:0] ord_trig;
    wire        ord_placed, res_submit;
    wire [63:0] sl_price, tp_price;
    wire        fill, reject;
    // bot
    wire        bot_active;
    wire [31:0] bot_cash, bot_value, bot_cb0, bot_cb1, bot_cb2, bot_cb3;
    wire [9:0]  bot_pos0, bot_pos1, bot_pos2, bot_pos3;
    wire [7:0]  bot_signal, bot_trades;
    wire [4:0]  bot_log_valid, bot_log_side;
    wire [9:0]  bot_log_stock;
    wire [79:0] bot_log_price;
    wire [39:0] bot_log_day;
    reg         bot_s0, bot_view;           // sw[1], synchronised
    always @(posedge clk) begin
        bot_s0   <= bot_sw;
        bot_view <= bot_s0;
    end
    wire [2:0]  reject_code;
    wire [15:0] ticket_pixel;
    wire [6:0]  xL;
    wire [5:0]  yL;
    D_display_top #(
        .DEBOUNCE_CTR(DEBOUNCE_CTR),
        .FINAL_TRADING_DAY(FINAL_TRADING_DAY)
    ) matthew_display (
        .clk(clk), .rst(sys_reset),
        .btnU(btnU), .btnD(btnD), .btnL(btnL), .btnR(btnR), .btnC(btnC),
        .final_day_reached(final_day_reached),
        .time_remaining(time_remaining),
        .order_fill(fill), .order_reject(reject), .order_reject_code(reject_code),
        .order_placed(ord_placed), .order_from_submit(res_submit),
        .sl_price(sl_price), .tp_price(tp_price),
        .bot_view(bot_view), .bot_active(bot_active), .bot_cash(bot_cash), .bot_value(bot_value),
        .bot_pos0(bot_pos0), .bot_pos1(bot_pos1), .bot_pos2(bot_pos2), .bot_pos3(bot_pos3),
        .bot_cb0(bot_cb0), .bot_cb1(bot_cb1), .bot_cb2(bot_cb2), .bot_cb3(bot_cb3),
        .bot_signal(bot_signal), .bot_log_valid(bot_log_valid), .bot_log_side(bot_log_side),
        .bot_log_stock(bot_log_stock), .bot_log_price(bot_log_price), .bot_log_day(bot_log_day),
        .left_pixel(ticket_pixel), .left_x(xL), .left_y(yL),
        .screen_state(screen_state), .quantity(quantity), .sel_stock(sel_stock),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .stock0_samples_30(amd_samples_30),
        .stock1_samples_30(mcd_samples_30),
        .stock2_samples_30(stock2_samples_30),
        .stock3_samples_30(stock3_samples_30),
        .portfolio_cash(cash), .portfolio_pos0(pos0), .portfolio_pos1(pos1),
        .portfolio_pos2(pos2), .portfolio_pos3(pos3),
        .stock_ready0(amd_ready), .stock_ready1(mcd_ready),
        .stock_ready2(stock2_ready), .stock_ready3(stock3_ready),
        .portfolio_value(portfolio_value),
        .portfolio_cb0(cb0), .portfolio_cb1(cb1),
        .portfolio_cb2(cb2), .portfolio_cb3(cb3),
        .portfolio_samples_30(portfolio_samples_30),
        .ord_req(ord_req), .ord_side(ord_side),
        .ord_type(ord_type), .ord_trig(ord_trig), .ord_brk(ord_brk), .game_state(game_state),
        .JA(JA), .JB(JB), .an(an), .seg(seg)
    );

    // ================================================================ YI AN: market engine
    // Yi An's A_top asks for "storage/data/AMD_seed.mem". In this repo the files are
    // in 2_YiAn_Market_Engine/data/ and are added to the Vivado project, so point
    // both stocks at the plain file names. [ASSUMPTION: Vivado finds .mem files
    // added to the project by name, in synthesis and simulation. Not tested here.]
    // Current prices and history buses for all four stocks are routed through
    // this integration level. The selected-stock chart consumes the matching
    // history bus for any of the four stock selections.
    A_top #(.DAY_MAX_COUNT(DAY_MAX_COUNT)) yian_market (
        .clk(clk), .rst(sys_reset),
        .market_state(market_state),
        .market_event(market_event),
        .amd_ready(amd_ready), .mcd_ready(mcd_ready),
        .amd_current_close(amd_close), .amd_current_volume(), .amd_current_date(amd_date),
        .mcd_current_close(mcd_close), .mcd_current_volume(), .mcd_current_date(mcd_date),
        .amd_samples_30(amd_samples_30), .amd_samples_180(), .amd_mean_30(), .amd_mean_180(),
        .mcd_samples_30(mcd_samples_30), .mcd_samples_180(), .mcd_mean_30(), .mcd_mean_180(),
        .stock2_ready(stock2_ready),
        .stock2_current_close(stock2_close),
        .stock2_current_volume(stock2_volume),
        .stock2_current_date(stock2_date),
        .stock2_samples_7(stock2_samples_7),
        .stock2_mean_7(stock2_mean_7),
        .stock2_samples_30(stock2_samples_30),
        .stock2_samples_180(stock2_samples_180),
        .stock2_mean_30(stock2_mean_30),
        .stock2_mean_180(stock2_mean_180),
        .stock3_ready(stock3_ready),
        .stock3_current_close(stock3_close),
        .stock3_current_volume(stock3_volume),
        .stock3_current_date(stock3_date),
        .stock3_samples_7(stock3_samples_7),
        .stock3_mean_7(stock3_mean_7),
        .stock3_samples_30(stock3_samples_30),
        .stock3_samples_180(stock3_samples_180),
        .stock3_mean_30(stock3_mean_30),
        .stock3_mean_180(stock3_mean_180)
    );

    // Vivado resolves hierarchical defparams after the referenced instance
    // has been declared. Keep these overrides after yian_market so the
    // integration project elaborates consistently across Vivado versions.
    defparam yian_market.amd_stock_inst.SEED_FILE = "AMD_seed.mem";
    defparam yian_market.mcd_stock_inst.SEED_FILE = "MCD_seed.mem";
    // Implementation 4 gives every channel its own deterministic seed data.
    defparam yian_market.stock2_inst.SEED_FILE = "NVDA_seed.mem";
    defparam yian_market.stock3_inst.SEED_FILE = "GME_seed.mem";

    // A_top updates all four stocks on the same internal day tick. A date
    // change marks the tick only after every stock is ready and all four dates
    // agree, so the order engine and portfolio history see a complete market
    // update.
    assign price0 = amd_ready ? amd_close : 16'd0;
    assign price1 = mcd_ready ? mcd_close : 16'd0;
    assign price2 = stock2_ready ? stock2_close : 16'd0;
    assign price3 = stock3_ready ? stock3_close : 16'd0;
    assign all_stocks_ready = amd_ready && mcd_ready && stock2_ready && stock3_ready;
    reg  [31:0] market_date_d;
    always @(posedge clk) begin
        if (sys_reset) begin
            market_date_d <= 32'd0;
            tick          <= 1'b0;
            trading_day_count <= 32'd0;
        end else begin
            market_date_d <= amd_date;
            tick          <= all_stocks_ready
                          && (amd_date == mcd_date)
                          && (amd_date == stock2_date)
                          && (amd_date == stock3_date)
                          && (amd_date != market_date_d);
            if (tick && (trading_day_count < FINAL_TRADING_DAY))
                trading_day_count <= trading_day_count + 1'b1;
        end
    end

    // tick is a one-clock pulse for a completed market-day update.  The
    // counter is compared to the preceding day so the last update itself is
    // included before the display enters GAME_END.
    assign final_day_reached = (FINAL_TRADING_DAY != 0)
                             && tick
                             && (trading_day_count == (FINAL_TRADING_DAY - 1'b1));

    // ================================================================ TRICIA: ledger
    wire signed [31:0] realised;
    wire        ledger_busy, ledger_err;
    wire        fill_side;
    wire [1:0]  fill_stock;
    wire [7:0]  fill_qty;
    wire [15:0] fill_price, fill_fee;
    ledger tricia_ledger (
        .clk(clk), .rst(sys_reset),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .cb0(cb0), .cb1(cb1), .cb2(cb2), .cb3(cb3),
        .realised(realised), .ledger_busy(ledger_busy), .err(ledger_err)
    );

    // Portfolio history is sampled on the same simulated trading-day tick
    // that drives the order book. It uses live cash, positions, and prices.
    portfolio_history portfolio_history_inst (
        .clk(clk), .rst(sys_reset), .tick(tick),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .portfolio_value(portfolio_value),
        .portfolio_samples(portfolio_samples_30)
    );

    // The bot (Tricia): its own cash and shares. A stub for now: active = 0, no trades.
    bot_trader tricia_bot (
        .clk(clk), .rst(sys_reset), .tick(tick), .game_live(game_state == `GS_PLAYING),
        .day(trading_day_count[7:0] + 8'd1),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .samples0(amd_samples_30), .samples1(mcd_samples_30),
        .samples2(stock2_samples_30), .samples3(stock3_samples_30),
        .active(bot_active), .cash(bot_cash), .pos0(bot_pos0), .pos1(bot_pos1), .pos2(bot_pos2), .pos3(bot_pos3),
        .cb0(bot_cb0), .cb1(bot_cb1), .cb2(bot_cb2), .cb3(bot_cb3), .value(bot_value),
        .signal(bot_signal), .trades(bot_trades),
        .log_valid(bot_log_valid), .log_side(bot_log_side), .log_stock(bot_log_stock),
        .log_price(bot_log_price), .log_day(bot_log_day)
    );

    // ================================================================ DOUGLAS: orders, ticket page
    wire [3:0]  pending_count;
    // The left OLED (JA) sits upside down on the board: draw the ticket rotated 180 degrees.
    B_order_top #(.TICKET_FLIP_180(1)) douglas_orders (
        .clk(clk), .sys_reset(sys_reset), .game_state(game_state),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3), .tick(tick),
        .sel_stock(sel_stock),
        .page_R(`PG_R_PORTFOLIO),        // Matthew owns the buttons: Douglas's own button entry is off
        .btn_pulse(5'd0),
        .ord_req(ord_req), .ord_side(ord_side), .ord_type(ord_type),
        .ord_qty(quantity), .ord_trig(ord_trig), .ord_brk(ord_brk),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy), .xR(xL), .yR(yL),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .reject(reject), .reject_code(reject_code), .pending_count(pending_count),
        .ord_placed(ord_placed), .res_submit(res_submit),
        .sl_price(sl_price), .tp_price(tp_price),
        .ticket_pixel(ticket_pixel)
    );

    // ================================================================ LEDs
    reg [24:0] fill_led, rej_led;        // ~0.3 s flash
    always @(posedge clk) begin
        if (sys_reset) begin
            fill_led <= 25'd0;
            rej_led  <= 25'd0;
        end else begin
            fill_led <= fill   ? 25'd30_000_000 : (fill_led != 0 ? fill_led - 25'd1 : 25'd0);
            rej_led  <= reject ? 25'd30_000_000 : (rej_led  != 0 ? rej_led  - 25'd1 : 25'd0);
        end
    end
    assign led = {fill_led != 0, rej_led != 0, 2'b00, pending_count, screen_state, 4'b0000};
endmodule

`default_nettype wire
