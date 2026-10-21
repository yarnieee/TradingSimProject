`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// Integration_Top: everyone's part in one build (branch-team-integration, 0_Integrated_Top/).
// One block per person:
//
//   yian_market      A_top         Yi An    2 stocks (AMD, MCD), one trading day every 2 s
//   douglas_orders   B_order_top   Douglas  validates and fills orders, order book, ticket page
//   tricia_ledger    ledger        Tricia   cash, positions, cost basis, ledger_busy handshake
//   matthew_display  matthew_top   Matthew  buttons, game screens, 7-seg, both OLEDs
//
// Board:
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

    // ================================================================ MATTHEW: buttons, screens, 7-seg, both OLEDs
    wire [3:0]  screen_state;
    wire [13:0] quantity;
    wire [1:0]  sel_stock, game_state;
    wire        ord_req, ord_side;
    wire [15:0] ticket_pixel;
    wire [6:0]  xL;
    wire [5:0]  yL;
    matthew_top #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) matthew_display (
        .clk(clk), .rst(sys_reset),
        .btnU(btnU), .btnD(btnD), .btnL(btnL), .btnR(btnR), .btnC(btnC),
        .left_pixel(ticket_pixel), .left_x(xL), .left_y(yL),
        .screen_state(screen_state), .quantity(quantity), .sel_stock(sel_stock),
        .ord_req(ord_req), .ord_side(ord_side), .game_state(game_state),
        .JA(JA), .JB(JB), .an(an), .seg(seg)
    );

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
    // page) are left unconnected, so synthesis removes them.
    A_top #(.DAY_MAX_COUNT(DAY_MAX_COUNT)) yian_market (
        .clk(clk), .rst(sys_reset),
        .market_state(market_state),
        .amd_ready(amd_ready), .mcd_ready(mcd_ready),
        .amd_current_close(amd_close), .amd_current_volume(), .amd_current_date(amd_date),
        .mcd_current_close(mcd_close), .mcd_current_volume(), .mcd_current_date(),
        .amd_samples_30(), .amd_samples_180(), .amd_mean_30(), .amd_mean_180(),
        .mcd_samples_30(), .mcd_samples_180(), .mcd_mean_30(), .mcd_mean_180()
    );

    // Price bus for Douglas. Replace when A_top outputs price0..3 and tick.
    // A_top updates both stocks on the same internal day tick, and the date
    // always moves on a trading day, so a date change marks the tick.
    // Stocks 2 and 3 have no data yet: price 0, which B_order_top treats as closed.
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

    // ================================================================ DOUGLAS: orders, ticket page
    wire [2:0]  reject_code;
    wire [3:0]  pending_count;
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
