`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// Integration_Top: everyone's part in one build (branch-team-integration, 0_Integrated_Top/).
//
//   Yi An    market engine   A_top         2 stocks (AMD, MCD), one trading day every 2 s
//   Douglas  orders          B_order_top   validates and fills orders, order book, ticket page
//   Tricia   ledger          ledger        cash, positions, cost basis, ledger_busy handshake
//   Matthew  game / display  game_fsm etc. buttons, screens, quantity on the 7-seg
//
// Nobody's module is edited. Everything that joins them is in the ADAPTERS
// section below; each adapter says which change in the owner's code would
// replace it. Board:
//   sw[0] (rst)   reset, as in Matthew's constraints
//   buttons       Matthew's game FSM (title > portfolio > stocks > stock > buy/sell > quantity > confirm)
//   JB (right)    Matthew's game screens
//   JA (left)     Douglas's order ticket: bid/ask, last fill or reject, pending count
//                 (temporary, until Yi An's chart page exists for this screen)
//   7-seg         Matthew's quantity
//   led[7:4]      Matthew's screen_state;  led[15] fill;  led[14] reject;  led[11:8] pending orders
module Integration_Top #(
    parameter DAY_MAX_COUNT = 199_999_999,      // Yi An: 2 s per trading day
    parameter DEBOUNCE_CTR  = 32'd1_999_999     // Matthew: 20 ms
) (
    input  wire        clk,
    input  wire        rst,
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

    // ================================================================ MATTHEW: buttons, game FSM, 7-seg, right OLED
    wire btnU_db, btnD_db, btnL_db, btnR_db, btnC_db;
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_U (.clk(clk), .btn(btnU), .debounced(btnU_db));
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_D (.clk(clk), .btn(btnD), .debounced(btnD_db));
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_L (.clk(clk), .btn(btnL), .debounced(btnL_db));
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_R (.clk(clk), .btn(btnR), .debounced(btnR_db));
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_C (.clk(clk), .btn(btnC), .debounced(btnC_db));

    reg [4:0] btn_prev;
    always @(posedge clk) begin
        if (sys_reset) btn_prev <= 5'd0;
        else           btn_prev <= {btnC_db, btnR_db, btnL_db, btnD_db, btnU_db};
    end
    wire btnU_p = btnU_db & ~btn_prev[0];
    wire btnD_p = btnD_db & ~btn_prev[1];
    wire btnL_p = btnL_db & ~btn_prev[2];
    wire btnR_p = btnR_db & ~btn_prev[3];
    wire btnC_p = btnC_db & ~btn_prev[4];

    wire [3:0]  screen_state;
    wire [13:0] quantity;
    game_fsm game_fsm_inst (
        .clk(clk), .rst(sys_reset),
        .btnU(btnU_p), .btnD(btnD_p), .btnL(btnL_p), .btnR(btnR_p), .btnC(btnC_p),
        .screen_state(screen_state), .quantity(quantity)
    );

    quantity_7seg quantity_7seg_inst (
        .clk(clk), .rst(sys_reset), .quantity(quantity), .an(an), .seg(seg)
    );

    wire clk_6_25MHz;
    slower_clk #(32'd7) clk_6_25MHz_inst (clk, clk_6_25MHz);

    wire [12:0] pixel_index_R;
    wire [15:0] pixel_data_R;
    wire        frame_begin_R, sending_pixels_R, sample_pixel_R;
    OLED_Renderer Oled_Renderer (
        .pixel_index(pixel_index_R), .screen_state(screen_state), .pixel_data(pixel_data_R)
    );
    oled_display oled_R (
        .clk(clk_6_25MHz), .reset(sys_reset), .pixel_data(pixel_data_R),
        .frame_begin(frame_begin_R), .sending_pixels(sending_pixels_R),
        .sample_pixel(sample_pixel_R), .pixel_index(pixel_index_R),
        .cs(JB[0]), .sdin(JB[1]), .sclk(JB[3]), .d_cn(JB[4]),
        .resn(JB[5]), .vccen(JB[6]), .pmoden(JB[7])
    );
    assign JB[2] = 1'b0;

    // ================================================================ YI AN: market engine
    wire [1:0]  market_state;
    wire        amd_ready, mcd_ready;
    wire [15:0] amd_close, mcd_close;
    wire [31:0] amd_date;
    // Yi An's A_top asks for "storage/data/AMD_seed.mem". In this repo the files are
    // in 2_YiAn_Market_Engine/data/ and are added to the Vivado project, so point
    // both stocks at the plain file names. [ASSUMPTION: Vivado finds .mem files
    // added to the project by name, in synthesis and simulation. Not tested here.]
    defparam yian_market.amd_stock_inst.SEED_FILE = "AMD_seed.mem";
    defparam yian_market.mcd_stock_inst.SEED_FILE = "MCD_seed.mem";

    // Only the current prices are used here. The history outputs (for the chart
    // page) are left unconnected, so synthesis removes the 1800-day history
    // registers, which would not fit the xc7a35t as they are.
    A_top #(.DAY_MAX_COUNT(DAY_MAX_COUNT)) yian_market (
        .clk(clk), .rst(sys_reset),
        .market_state(market_state),
        .amd_ready(amd_ready), .mcd_ready(mcd_ready),
        .amd_current_close(amd_close), .amd_current_volume(), .amd_current_date(amd_date),
        .mcd_current_close(mcd_close), .mcd_current_volume(), .mcd_current_date(),
        .amd_samples_30(), .amd_samples_180(), .amd_mean_30(), .amd_mean_180(),
        .mcd_samples_30(), .mcd_samples_180(), .mcd_mean_30(), .mcd_mean_180()
    );

    // ================================================================ ADAPTERS
    // --- Yi An -> Douglas, Tricia: price bus. Replace when A_top outputs price0..3 and tick.
    //     A_top updates both stocks on the same internal day tick, and the date
    //     always moves on a trading day, so a date change marks the tick.
    //     Stocks 2 and 3 have no data yet: price 0, which Douglas's B_order_top treats as closed.
    wire [15:0] price0 = amd_ready ? amd_close : 16'd0;
    wire [15:0] price1 = mcd_ready ? mcd_close : 16'd0;
    wire [15:0] price2 = 16'd0;
    wire [15:0] price3 = 16'd0;
    reg  [31:0] amd_date_d;
    reg         tick;
    always @(posedge clk) begin
        if (sys_reset) begin
            amd_date_d <= 32'd0;
            tick       <= 1'b0;
        end else begin
            amd_date_d <= amd_date;
            tick       <= amd_ready && (amd_date != amd_date_d);
        end
    end

    // --- Matthew -> Douglas: the order. Replace when game_fsm outputs sel_stock, the
    //     side and a confirm pulse. Screen codes are game_fsm's localparams.
    localparam [3:0] S_TITLE = 4'd0, S_PORTFOLIO = 4'd1, S_STOCKS = 4'd2, S_SPECIFIC = 4'd3,
                     S_BUY = 4'd4, S_SELL = 4'd5, S_CONFIRM = 4'd7, S_GAME_END = 4'd8;
    reg [3:0] state_d;
    always @(posedge clk) begin
        if (sys_reset) state_d <= S_TITLE;
        else           state_d <= screen_state;
    end
    // choosing "confirmation" on the buy or sell screen places the order
    wire ord_req  = (screen_state == S_CONFIRM) && (state_d == S_BUY || state_d == S_SELL);
    wire ord_side = (state_d == S_SELL) ? `SIDE_SELL : `SIDE_BUY;

    // Selected stock: a mirror of game_fsm's stocks_cursor, which is internal.
    reg [2:0] stocks_cursor;             // 0..3 stocks, 4 = back (as in game_fsm)
    reg [1:0] sel_stock;
    always @(posedge clk) begin
        if (sys_reset) begin
            stocks_cursor <= 3'd0;
            sel_stock     <= 2'd0;
        end else begin
            if (state_d == S_PORTFOLIO && screen_state == S_STOCKS)
                stocks_cursor <= 3'd0;   // game_fsm resets it on this transition
            else if (screen_state == S_STOCKS) begin
                // same order of ifs as game_fsm: L and R win over U and D
                if (btnR_p)      stocks_cursor <= 3'd0;
                else if (btnL_p) stocks_cursor <= 3'd4;
                else if (btnD_p) stocks_cursor <= (stocks_cursor == 3'd3) ? 3'd4 : stocks_cursor + 3'd1;
                else if (btnU_p) stocks_cursor <= (stocks_cursor == 3'd0 || stocks_cursor == 3'd4)
                                                  ? 3'd3 : stocks_cursor - 3'd1;
            end
            if (state_d == S_STOCKS && screen_state == S_SPECIFIC)
                sel_stock <= stocks_cursor[1:0];
        end
    end

    // --- Matthew -> Yi An, Douglas: game state. Replace when game_fsm outputs game_state.
    wire [1:0] game_state = (screen_state == S_TITLE || screen_state == S_GAME_END)
                            ? `GS_MENU : `GS_PLAYING;

    // ================================================================ TRICIA: ledger
    wire [31:0] cash, cb0, cb1, cb2, cb3;
    wire [9:0]  pos0, pos1, pos2, pos3;
    wire signed [31:0] realised;
    wire        ledger_busy, ledger_err;
    wire        fill, fill_side, reject;
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

    // ================================================================ DOUGLAS: orders, left OLED
    wire [12:0] pixel_index_L;
    wire [15:0] ticket_pixel;
    wire        frame_begin_L, sending_pixels_L, sample_pixel_L;
    wire [2:0]  reject_code;
    wire [3:0]  pending_count;
    wire [6:0]  xL = pixel_index_L % 96;
    wire [5:0]  yL = pixel_index_L / 96;

    // The left OLED (JA) sits upside down on the board: draw the ticket rotated 180 degrees.
    B_order_top #(.TICKET_FLIP_180(1)) douglas_orders (
        .clk(clk), .sys_reset(sys_reset), .game_state(game_state),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3), .tick(tick),
        .sel_stock(sel_stock),
        .page_R(`PG_R_PORTFOLIO),        // Matthew owns the buttons: Douglas's own button entry is off
        .btn_pulse(5'd0),
        .ord_req(ord_req), .ord_side(ord_side), .ord_type(`OT_MKT),
        .ord_qty(quantity), .ord_trig(16'd0),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy), .xR(xL), .yR(yL),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .reject(reject), .reject_code(reject_code), .pending_count(pending_count),
        .ticket_pixel(ticket_pixel)
    );

    oled_display oled_L (
        .clk(clk_6_25MHz), .reset(sys_reset), .pixel_data(ticket_pixel),
        .frame_begin(frame_begin_L), .sending_pixels(sending_pixels_L),
        .sample_pixel(sample_pixel_L), .pixel_index(pixel_index_L),
        .cs(JA[0]), .sdin(JA[1]), .sclk(JA[3]), .d_cn(JA[4]),
        .resn(JA[5]), .vccen(JA[6]), .pmoden(JA[7])
    );
    assign JA[2] = 1'b0;

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
