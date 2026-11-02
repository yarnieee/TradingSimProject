`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// Integration_Top: everyone's part in one build (branch-team-integration, 0_Integrated_Top/).
// One block per person. Module names follow the team doc's rule
// (A_/B_/C_/D_<description>_top); instance names say whose part it is.
//
//   instance         module          owner    does
//   yian_market      A_top           Yi An    4 stock channels, one trading day every 5 s
//   douglas_orders   B_order_top     Douglas  validates and fills orders, order book, ticket page
//   tricia_portfolio C_portfolio_top Tricia   ledger (cash, positions, ledger_busy), risk metrics,
//                                             and the moving-average bot with its own ledger
//   bots             bot_squad       Tricia   four more bots: overnight, day trade, average
//                                             down, stop-loss / take-profit
//   bot_log          bot_logbook     Tricia   every bot's recent trades, for the bot view
//   matthew_display  D_display_top   Matthew  buttons, game screens, 7-seg, both OLEDs
//
// Board:
//   sw[0] (rst)   reset, as in Matthew's constraints
//   sw[3:2]       order type: 00 market, 01 limit, 10 stop          (order_sw[1:0])
//   sw[5:4]       SL/TP for a buy: 00 off, 01 2%, 10 5%, 11 10%     (order_sw[3:2])
//   sw[7:6]       trigger distance from the price: 1, 2, 5, 10%     (order_sw[5:4])
//                 (limit buy / stop sell below the price, limit sell / stop buy above)
//   sw[15] (view_sw) up: bot view (JB a bot against you, JA its last trades); BTNL / BTNR
//                 choose the bot, the game buttons are ignored
//   sw[14] (orders_sw) up: the buttons work the left OLED's ORDERS list: BTNU / BTND
//                 choose a pending order, BTNC cancels it (the game buttons are ignored)
//   buttons       Matthew's game FSM (title > portfolio > stocks > stock > buy/sell
//                 > quantity > review > result)
//   JB (right)    Matthew's game screens
//   JA (left)     Douglas's order ticket (title artwork on the title screen)
//   VGA           the whole game on a monitor (1280 x 720): prices, portfolio, chart, orders,
//                 a leaderboard of you and the 5 bots, what to press, the switch settings
//   7-seg         Matthew's quantity
//   led[7:4]      Matthew's screen_state;  led[15] fill;  led[14] reject;  led[11:8] pending orders
module Integration_Top #(
    parameter DAY_MAX_COUNT = 499_999_999,      // Yi An: 5 s per trading day
    parameter DEBOUNCE_CTR  = 32'd1_999_999,    // Matthew: 20 ms
    parameter FINAL_TRADING_DAY = 32'd120      // Game ends after this many days (120 x 5 s = 10 minutes)
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [5:0]  order_sw,        // sw[7:2]: order type, SL/TP, trigger distance
    input  wire        view_sw,         // sw[15]: show the bot
    input  wire        orders_sw,       // sw[14]: the buttons work the left OLED's ORDERS list (cancel)
    input  wire        btnU,
    input  wire        btnD,
    input  wire        btnL,
    input  wire        btnR,
    input  wire        btnC,
    output wire [3:0]  vgaRed,
    output wire [3:0]  vgaGreen,
    output wire [3:0]  vgaBlue,
    output wire        Hsync,
    output wire        Vsync,
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
    wire signed [31:0] upnl0, upnl1, upnl2, upnl3;    // player's profit/loss per stock (Tricia)
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
    wire [7:0]   book_valid, book_side, book_leg;
    wire [15:0]  book_stock, book_type;
    wire [63:0]  book_qty;
    wire [127:0] book_trig;
    wire signed [31:0] ret_bp, bot_ret_bp;
    wire [31:0]  max_dd_bp;
    wire        fill, reject;
    // bot
    wire [31:0] bot_cash, bot_equity;
    wire signed [31:0] bot_upnl0, bot_upnl1, bot_upnl2, bot_upnl3;
    wire [9:0]  bot_pos0, bot_pos1, bot_pos2, bot_pos3;
    wire        bot_last_valid, bot_last_side;
    wire [1:0]  bot_last_stock;
    wire [7:0]  bot_last_qty;
    wire [15:0] bot_last_price;
    reg  [7:0]  bot_trades;                      // the moving-average bot's trades so far
    // bot 0 is the moving-average bot, bots 1-4 are bot_squad's 0-3
    wire [2:0]   bot_sel;                        // the bot the bot view shows (BTNL / BTNR, in D)
    wire [127:0] squad_value;
    wire [31:0]  squad_cash;
    wire [39:0]  squad_pos;
    wire [127:0] squad_upnl;
    wire         squad_trade, squad_side;
    wire [1:0]   squad_bot, squad_stock;
    wire [15:0]  squad_price;
    wire [4:0]   bot_log_valid, bot_log_side;    // the chosen bot's last 5 trades, newest first
    wire [9:0]   bot_log_stock;
    wire [79:0]  bot_log_price;
    wire [39:0]  bot_log_day;
    // the bot view's numbers: the moving-average bot, or the chosen bot_squad bot
    wire        show_ma = (bot_sel == 3'd0);
    wire [1:0]  squad_sel = bot_sel[1:0] - 2'd1;    // bots 1-4 -> bot_squad 0-3
    wire [31:0] view_cash  = show_ma ? bot_cash   : squad_cash;
    wire [31:0] view_value = show_ma ? bot_equity : squad_value[32*squad_sel +: 32];
    wire [9:0]  view_pos0  = show_ma ? bot_pos0 : squad_pos[9:0];
    wire [9:0]  view_pos1  = show_ma ? bot_pos1 : squad_pos[19:10];
    wire [9:0]  view_pos2  = show_ma ? bot_pos2 : squad_pos[29:20];
    wire [9:0]  view_pos3  = show_ma ? bot_pos3 : squad_pos[39:30];
    wire signed [31:0] view_upnl0 = show_ma ? bot_upnl0 : squad_upnl[31:0];
    wire signed [31:0] view_upnl1 = show_ma ? bot_upnl1 : squad_upnl[63:32];
    wire signed [31:0] view_upnl2 = show_ma ? bot_upnl2 : squad_upnl[95:64];
    wire signed [31:0] view_upnl3 = show_ma ? bot_upnl3 : squad_upnl[127:96];
    // switches, synchronised to clk
    reg  [5:0]  osw_s0, osw;
    reg         view_s0, bot_view, ords_s0, ords_sw;
    always @(posedge clk) begin
        osw_s0   <= order_sw;
        osw      <= osw_s0;
        view_s0  <= view_sw;
        bot_view <= view_s0;
        ords_s0  <= orders_sw;
        ords_sw  <= ords_s0;
    end
    // sw14 up (not in the bot view, not on the title): the buttons go to the
    // left OLED's ORDERS list, U / D choose a pending order, C cancels it
    wire        orders_view = ords_sw && !bot_view && (screen_state != `UI_TITLE);
    wire [4:0]  d_btn_pulse;
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
        .orders_view(orders_view), .btn_pulse(d_btn_pulse),
        .final_day_reached(final_day_reached),
        .time_remaining(time_remaining),
        .order_fill(fill), .order_reject(reject), .order_reject_code(reject_code),
        .order_placed(ord_placed), .order_from_submit(res_submit),
        .sl_price(sl_price), .tp_price(tp_price),
        .bot_view(bot_view), .bot_active(1'b1), .bot_sel(bot_sel),
        .bot_cash(view_cash), .bot_value(view_value),
        .bot_pos0(view_pos0), .bot_pos1(view_pos1), .bot_pos2(view_pos2), .bot_pos3(view_pos3),
        .bot_upnl0(view_upnl0), .bot_upnl1(view_upnl1), .bot_upnl2(view_upnl2), .bot_upnl3(view_upnl3),
        .bots_value({squad_value, bot_equity}),
        .bot_signal(8'd0),                       // Tricia's bot does not output its signals
        .bot_log_valid(bot_log_valid), .bot_log_side(bot_log_side),
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
        .portfolio_upnl0(upnl0), .portfolio_upnl1(upnl1),
        .portfolio_upnl2(upnl2), .portfolio_upnl3(upnl3),
        .portfolio_samples_30(portfolio_samples_30),
        .ord_req(ord_req), .ord_side(ord_side),
        .ord_type(ord_type), .ord_trig(ord_trig), .ord_brk(ord_brk), .ord_dist(osw[5:4]),
        .ret_bp(ret_bp), .max_dd_bp(max_dd_bp), .bot_ret_bp(bot_ret_bp),
        .book_valid(book_valid), .book_side(book_side), .book_stock(book_stock),
        .book_type(book_type), .book_qty(book_qty), .book_trig(book_trig), .book_leg(book_leg),
        .game_state(game_state),
        .vga_r(vgaRed), .vga_g(vgaGreen), .vga_b(vgaBlue), .vga_hs(Hsync), .vga_vs(Vsync),
        .JA(JA), .JB(JB), .an(an), .seg(seg)
    );

    // ================================================================ order settings from the switches
    // B_order_top latches them with the order on ord_req (sending from the review
    // screen); until then the screens show the current settings.
    assign ord_type = (osw[1:0] == 2'b01) ? `OT_LMT :
                      (osw[1:0] == 2'b10) ? `OT_STP : `OT_MKT;
    assign ord_brk  = (ord_side == `SIDE_BUY) ? osw[3:2] : `BRK_OFF;   // codes match BRK_*
    // trigger = the selected stock's price -/+ 1, 2, 5 or 10% (price x k >> 16)
    reg  [15:0] sw_px;
    always @(*) begin
        case (sel_stock)
            2'd0:    sw_px = price0;
            2'd1:    sw_px = price1;
            2'd2:    sw_px = price2;
            default: sw_px = price3;
        endcase
    end
    wire [12:0] trig_k    = (osw[5:4] == 2'b00) ? 13'd656  : (osw[5:4] == 2'b01) ? 13'd1312 :
                            (osw[5:4] == 2'b10) ? 13'd3280 : 13'd6560;
    // Worked out over 3 clocks (price, then x k, then -/+), so the multiply is not
    // in one long path with whatever uses the trigger; it is 30 ns behind the
    // switches and prices, which change at most every few milliseconds.
    reg  [15:0] tg_px, tg_px2;
    reg  [12:0] tg_k;
    reg  [28:0] trig_prod;
    reg  [15:0] ord_trig_r;
    wire [15:0] trig_dist = (trig_prod[28:16] == 13'd0) ? 16'd1 : {3'd0, trig_prod[28:16]};
    wire        trig_below = ((ord_type == `OT_LMT) && (ord_side == `SIDE_BUY)) ||
                             ((ord_type == `OT_STP) && (ord_side == `SIDE_SELL));
    wire [16:0] trig_up   = {1'b0, tg_px2} + {1'b0, trig_dist};
    always @(posedge clk) begin
        tg_px      <= sw_px;
        tg_k       <= trig_k;
        trig_prod  <= tg_px * tg_k;
        tg_px2     <= tg_px;
        ord_trig_r <= (ord_type == `OT_MKT) ? 16'd0 :
                      trig_below ? ((tg_px2 > trig_dist) ? tg_px2 - trig_dist : 16'd1) :
                                   (trig_up[16] ? 16'hFFFF : trig_up[15:0]);
    end
    assign ord_trig = ord_trig_r;

    // ================================================================ YI AN: market engine
    // Yi An's A_top asks for "storage/data/AMD_seed.mem". In this repo the files are
    // in 2_YiAn_Market_Engine/data/ and are added to the Vivado project, so point
    // both stocks at the plain file names. [ASSUMPTION: Vivado finds .mem files
    // added to the project by name, in synthesis and simulation. Not tested here.]
    // Current prices and history buses for all four stocks are routed through
    // this integration level. The selected-stock chart consumes the matching
    // history bus for any of the four stock selections.
    // The market stops when the game is over, so prices, charts and net worths
    // stay at the final day.
    wire game_over = (screen_state == `UI_GAME_END);
    // The market (and the day count) starts when the player leaves the title
    // screen. Yi An's startup_seed takes its random seed then, from a counter
    // that never stops, so every game has a different market, even the first
    // one after the board is programmed; and every game gets all its days.
    reg  market_rst;
    always @(posedge clk) market_rst <= sys_reset || (screen_state == `UI_TITLE);
    A_top #(.DAY_MAX_COUNT(DAY_MAX_COUNT)) yian_market (
        .clk(clk), .rst(market_rst), .run(!game_over),
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
        if (market_rst) begin
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

    // ================================================================ TRICIA: portfolio (ledger, risk, bot)
    wire signed [31:0] realised, pnl, bot_realised, bot_pnl;
    wire [31:0] equity, bot_max_dd_bp;
    wire        ledger_busy, ledger_err;
    wire        fill_side;
    wire [1:0]  fill_stock;
    wire [7:0]  fill_qty;
    wire [15:0] fill_price, fill_fee;
    C_portfolio_top tricia_portfolio (
        .clk(clk), .sys_reset(sys_reset), .bot_run(game_state == `GS_PLAYING),
        .tick(tick), .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy), .err(ledger_err),
        .upnl0(upnl0), .upnl1(upnl1), .upnl2(upnl2), .upnl3(upnl3),
        .realised(realised), .equity(equity), .pnl(pnl), .ret_bp(ret_bp), .max_dd_bp(max_dd_bp),
        .bot_cash(bot_cash), .bot_pos0(bot_pos0), .bot_pos1(bot_pos1), .bot_pos2(bot_pos2), .bot_pos3(bot_pos3),
        .bot_upnl0(bot_upnl0), .bot_upnl1(bot_upnl1), .bot_upnl2(bot_upnl2), .bot_upnl3(bot_upnl3),
        .bot_realised(bot_realised), .bot_equity(bot_equity), .bot_pnl(bot_pnl),
        .bot_ret_bp(bot_ret_bp), .bot_max_dd_bp(bot_max_dd_bp),
        .bot_last_valid(bot_last_valid), .bot_last_stock(bot_last_stock), .bot_last_side(bot_last_side),
        .bot_last_qty(bot_last_qty), .bot_last_price(bot_last_price)
    );

    // The moving-average bot reports its most recent trade; a new trade is seen
    // as a change in the reported one (the bot alternates buy / sell per stock,
    // so two trades in a row always differ).
    reg [27:0] bot_last_d;
    wire [27:0] bot_last = {bot_last_valid, bot_last_side, bot_last_stock, bot_last_qty, bot_last_price};
    wire        ma_trade = bot_last_valid && (bot_last != bot_last_d);
    always @(posedge clk) begin
        if (sys_reset) begin
            bot_last_d <= 28'd0;
            bot_trades <= 8'd0;
        end else begin
            bot_last_d <= bot_last;
            if (ma_trade) bot_trades <= bot_trades + 8'd1;
        end
    end

    // ================================================================ TRICIA: bot_squad, four more bots
    // They trade at the market open (tick, the start of a day) and close: 90% into
    // the day, at the same price (the market has one price a day).
    localparam [31:0] CLOSE_AT = (DAY_MAX_COUNT / 10) * 9;
    reg  [31:0] day_clk;
    reg         day_on, close_tick;
    always @(posedge clk) begin
        close_tick <= 1'b0;
        if (sys_reset) begin
            day_on  <= 1'b0;
            day_clk <= 32'd0;
        end else if (tick) begin
            day_on  <= 1'b1;
            day_clk <= 32'd0;
        end else if (day_on) begin
            if (day_clk == CLOSE_AT) begin
                close_tick <= 1'b1;
                day_on     <= 1'b0;
            end else
                day_clk <= day_clk + 32'd1;
        end
    end

    bot_squad bots (
        .clk(clk), .rst(sys_reset), .run(game_state == `GS_PLAYING),
        .open_tick(tick), .close_tick(close_tick),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .sel(squad_sel),
        .value(squad_value), .sel_cash(squad_cash), .sel_pos(squad_pos), .sel_upnl(squad_upnl),
        .trade(squad_trade), .trade_bot(squad_bot), .trade_stock(squad_stock),
        .trade_side(squad_side), .trade_price(squad_price)
    );

    bot_logbook bot_log (
        .clk(clk), .rst(sys_reset), .day(trading_day_count[7:0]),
        .a_trade(ma_trade), .a_side(bot_last_side), .a_stock(bot_last_stock), .a_price(bot_last_price),
        .q_trade(squad_trade), .q_bot(squad_bot), .q_side(squad_side),
        .q_stock(squad_stock), .q_price(squad_price),
        .sel(bot_sel),
        .log_valid(bot_log_valid), .log_side(bot_log_side), .log_stock(bot_log_stock),
        .log_price(bot_log_price), .log_day(bot_log_day)
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

    // ================================================================ DOUGLAS: orders, ticket page
    wire [3:0]  pending_count;
    // The left OLED (JA) sits upside down on the board: draw the ticket rotated 180 degrees.
    B_order_top #(.TICKET_FLIP_180(1), .EMBEDDED(1)) douglas_orders (
        .clk(clk), .sys_reset(sys_reset), .game_state(game_state),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3), .tick(tick),
        .sel_stock(sel_stock),
        // Matthew owns the buttons, except with sw14 up: then they work the ORDERS list
        .page_R(orders_view ? `PG_R_TICKET : `PG_R_PORTFOLIO),
        .btn_pulse(orders_view ? d_btn_pulse : 5'd0),
        .ord_req(ord_req), .ord_side(ord_side), .ord_type(ord_type),
        .ord_qty(quantity), .ord_trig(ord_trig), .ord_brk(ord_brk),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy), .xR(xL), .yR(yL),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .reject(reject), .reject_code(reject_code), .pending_count(pending_count),
        .ord_placed(ord_placed), .res_submit(res_submit),
        .sl_price(sl_price), .tp_price(tp_price),
        .book_valid(book_valid), .book_side(book_side), .book_stock(book_stock),
        .book_type(book_type), .book_qty(book_qty), .book_trig(book_trig), .book_leg(book_leg),
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
