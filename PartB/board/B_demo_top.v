`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// B_demo_top: stand-alone board test for Part B (prototype 1).
// NOT the team top level: My_Top_Module stays the real one. This lets Part B
// be checked on the Basys3 before A, C and D are integrated.
//
//   Right OLED (Pmod on JB)  Order Ticket page
//   btnU/D/L/R/C             the five ticket buttons (debounced here; D's job later)
//   sw[15]                   reset (also a short power-on reset)
//   sw[1:0]                  fake market: 0 flat, 1 up ~1%/tick, 2 down ~1%/tick, 3 gap down 1/8
//   sw[3:2]                  selected stock (0 ABC, 1 TEK, 2 NRG, 3 MEM)
//   led[9:0]                 position in the selected stock
//   led[13:10]               pending orders in the book
//   led[14]                  flashes on a reject
//   led[15]                  flashes on a fill
//
// Ledger: stub_ledger by default. Compile with `define USE_PART_C (Vivado:
// Settings > Verilog options > Defines) to use C's real ledger.v and seq_divider.v.
module B_demo_top (
    input  wire        clk,
    input  wire [15:0] sw,
    input  wire        btnC,
    input  wire        btnU,
    input  wire        btnL,
    input  wire        btnR,
    input  wire        btnD,
    output wire [7:0]  JB,
    output wire [15:0] led
);
    // ------------------------------------------------------------ reset
    reg [4:0] por = 5'd0;                     // power-on reset: 31 clocks
    always @(posedge clk) if (!por[4]) por <= por + 5'd1;
    reg rst_s0, sys_reset;
    always @(posedge clk) begin
        rst_s0    <= sw[15] || !por[4];
        sys_reset <= rst_s0;
    end

    // ------------------------------------------------------------ buttons
    wire [4:0] btn_pulse;
    b_demo_btn u_bc (.clk(clk), .rst(sys_reset), .btn(btnC), .pulse(btn_pulse[`BTN_C]));
    b_demo_btn u_bu (.clk(clk), .rst(sys_reset), .btn(btnU), .pulse(btn_pulse[`BTN_U]));
    b_demo_btn u_bl (.clk(clk), .rst(sys_reset), .btn(btnL), .pulse(btn_pulse[`BTN_L]));
    b_demo_btn u_br (.clk(clk), .rst(sys_reset), .btn(btnR), .pulse(btn_pulse[`BTN_R]));
    b_demo_btn u_bd (.clk(clk), .rst(sys_reset), .btn(btnD), .pulse(btn_pulse[`BTN_D]));

    // ------------------------------------------------------------ fake market (A)
    wire [15:0] price0, price1, price2, price3;
    wire        tick;
    stub_market #(.TICK_DIV(25_000_000)) u_mkt (          // 250 ms
        .clk(clk), .sys_reset(sys_reset), .mode(sw[1:0]), .tick_req(1'b0),
        .force_en(1'b0), .force_stock(2'd0), .force_price(16'd0),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3), .tick(tick)
    );

    // ------------------------------------------------------------ ledger (C)
    wire [31:0] cash;
    wire [9:0]  pos0, pos1, pos2, pos3;
    wire        ledger_busy;
    wire        fill, fill_side, reject;
    wire [1:0]  fill_stock;
    wire [7:0]  fill_qty;
    wire [15:0] fill_price, fill_fee;
    wire [2:0]  reject_code;
    wire [3:0]  pending_count;

`ifdef USE_PART_C
    wire [31:0] cb0, cb1, cb2, cb3;
    wire signed [31:0] realised;
    wire        ledger_err;
    ledger u_ledger (
        .clk(clk), .rst(sys_reset),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .cb0(cb0), .cb1(cb1), .cb2(cb2), .cb3(cb3),
        .realised(realised), .ledger_busy(ledger_busy), .err(ledger_err)
    );
`else
    stub_ledger u_ledger (
        .clk(clk), .sys_reset(sys_reset),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy)
    );
`endif

    // ------------------------------------------------------------ right OLED
    wire        clk_6_25MHz;
    wire [12:0] pixel_index;
    wire [15:0] ticket_pixel;
    wire        frame_begin, sending_pixels, sample_pixel;
    wire [6:0]  xR = pixel_index % 96;
    wire [5:0]  yR = pixel_index / 96;

    slower_clk #(32'd7) u_clk_6_25MHz (clk, clk_6_25MHz);

    Oled_Display u_oled_R (
        .clk(clk_6_25MHz), .reset(sys_reset), .pixel_data(ticket_pixel),
        .frame_begin(frame_begin), .sending_pixels(sending_pixels),
        .sample_pixel(sample_pixel), .pixel_index(pixel_index),
        .cs(JB[0]), .sdin(JB[1]), .sclk(JB[3]), .d_cn(JB[4]),
        .resn(JB[5]), .vccen(JB[6]), .pmoden(JB[7])
    );
    assign JB[2] = 1'b0;                  // unused Pmod pin (as in My_Top_Module)

    // ------------------------------------------------------------ Part B
    B_order_top u_b (
        .clk(clk), .sys_reset(sys_reset), .game_state(`GS_PLAYING),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3), .tick(tick),
        .sel_stock(sw[3:2]), .page_R(`PG_R_TICKET), .btn_pulse(btn_pulse),
        .ord_req(1'b0), .ord_side(1'b0), .ord_type(2'd0), .ord_qty(14'd0), .ord_trig(16'd0),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy), .xR(xR), .yR(yR),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .reject(reject), .reject_code(reject_code), .pending_count(pending_count),
        .ticket_pixel(ticket_pixel)
    );

    // ------------------------------------------------------------ LEDs
    reg [9:0] pos_sel;
    always @* begin
        case (sw[3:2])
            2'd0:    pos_sel = pos0;
            2'd1:    pos_sel = pos1;
            2'd2:    pos_sel = pos2;
            default: pos_sel = pos3;
        endcase
    end

    reg [24:0] fill_led, rej_led;         // ~0.3 s flash
    always @(posedge clk) begin
        if (sys_reset) begin
            fill_led <= 25'd0;
            rej_led  <= 25'd0;
        end else begin
            fill_led <= fill   ? 25'd30_000_000 : (fill_led != 0 ? fill_led - 25'd1 : 25'd0);
            rej_led  <= reject ? 25'd30_000_000 : (rej_led  != 0 ? rej_led  - 25'd1 : 25'd0);
        end
    end

    assign led = {fill_led != 0, rej_led != 0, pending_count, pos_sel};
endmodule

`default_nettype wire
