`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_BC_ledger: Douglas's order engine against Tricia's real ledger (Tricia's ledger.v and
// seq_divider.v, from branch-tricia-ledger), with stub_market for prices.
// Driven only through the five buttons, as in prototype 1.
//
// Checks:
//   - exact cash / position / realised P&L for a buy, then a partial sell
//     (the partial sell takes the ledger's divider path, its longest busy time)
//   - the order engine never sends a fill the ledger has to reject (ledger err never pulses)
//   - three book triggers on one tick, each a partial sell through the divider
//   - the ledger invariant cash + sum(cost basis) == START + realised, whenever idle
//   - 60 random orders on all four stocks with random price moves
module tb_BC_ledger;
    reg clk = 0;
    always #5 clk = ~clk;

    reg        sys_reset = 1;
    reg [1:0]  game_state = `GS_PLAYING;
    reg [1:0]  sel_stock = 0;
    reg        page_R = `PG_R_TICKET;
    reg [4:0]  btn_pulse = 0;
    reg [6:0]  xR = 0;
    reg [5:0]  yR = 0;
    reg [1:0]  mkt_mode = 0;
    reg        tick_req = 0;
    reg        force_en = 0;
    reg [1:0]  force_stock = 0;
    reg [15:0] force_price = 0;

    wire [15:0] price0, price1, price2, price3;
    wire        tick;
    wire [31:0] cash, cb0, cb1, cb2, cb3;
    wire [9:0]  pos0, pos1, pos2, pos3;
    wire signed [31:0] realised;
    wire        ledger_busy, ledger_err;
    wire        fill, fill_side, reject;
    wire [1:0]  fill_stock;
    wire [7:0]  fill_qty;
    wire [15:0] fill_price, fill_fee, ticket_pixel;
    wire [2:0]  reject_code;
    wire [3:0]  pending_count;

    stub_market #(.P0(12300), .P1(4520), .P2(8800), .P3(1230), .TICK_DIV(0)) u_mkt (
        .clk(clk), .sys_reset(sys_reset), .mode(mkt_mode), .tick_req(tick_req),
        .force_en(force_en), .force_stock(force_stock), .force_price(force_price),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3), .tick(tick)
    );

    // Tricia's ledger, unmodified
    ledger #(.START_CASH(32'd1_000_000)) u_c (
        .clk(clk), .rst(sys_reset),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .cb0(cb0), .cb1(cb1), .cb2(cb2), .cb3(cb3),
        .realised(realised), .ledger_busy(ledger_busy), .err(ledger_err)
    );

    B_order_top #(.REJ_SHOW_CYCLES(1000)) u_b (
        .clk(clk), .sys_reset(sys_reset), .game_state(game_state),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3), .tick(tick),
        .sel_stock(sel_stock), .page_R(page_R), .btn_pulse(btn_pulse),
        .ord_req(1'b0), .ord_side(1'b0), .ord_type(2'd0), .ord_qty(14'd0), .ord_trig(16'd0), .ord_brk(`BRK_OFF),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy), .xR(xR), .yR(yR),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .reject(reject), .reject_code(reject_code), .pending_count(pending_count),
        .ticket_pixel(ticket_pixel)
    );

    // ------------------------------------------------------------ monitors
    integer n_fill = 0, n_rej = 0, n_err = 0, n_fill_busy = 0;
    reg [2:0] last_rej = 0;
    always @(posedge clk) if (!sys_reset) begin
        if (fill) begin
            n_fill = n_fill + 1;
            if (ledger_busy) n_fill_busy = n_fill_busy + 1;
        end
        if (reject) begin n_rej = n_rej + 1; last_rej = reject_code; end
        if (ledger_err) begin
            n_err = n_err + 1;
            $display("FAIL: ledger rejected a fill from B (t=%0t)", $time);
        end
    end

    integer n_pass = 0, n_fail = 0;
    task check;
        input          cond;
        input [8*64:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s (t=%0t)", name, $time); end
        end
    endtask

    task invariant;
        input [8*32:1] where;
        begin
            check(!ledger_busy && (cash + cb0 + cb1 + cb2 + cb3) == 32'd1_000_000 + realised,
                  {"ledger invariant after ", where});
        end
    endtask

    // ------------------------------------------------------------ drivers
    task step; input integer n; begin repeat (n) @(posedge clk); #1; end endtask
    task settle; begin step(600); end endtask

    localparam K_UP = `BTN_U, K_DOWN = `BTN_D, K_LEFT = `BTN_L, K_RIGHT = `BTN_R, K_CENTER = `BTN_C;
    task press;
        input integer k;
        begin btn_pulse = 5'b00001 << k; step(1); btn_pulse = 0; step(2); end
    endtask
    task focus_to;
        input [2:0] f; integer k;
        begin for (k = 0; k < 6 && u_b.u_entry.focus != f; k = k + 1) press(K_RIGHT); end
    endtask
    task set_side;
        input s;
        begin focus_to(0); if (u_b.u_entry.side != s) press(K_CENTER); end
    endtask
    task set_type;
        input [1:0] t; integer k;
        begin focus_to(1); for (k = 0; k < 3 && u_b.u_entry.otype != t; k = k + 1) press(K_CENTER); end
    endtask
    task set_qty;
        input integer q; integer k;
        begin
            focus_to(0);
            for (k = 0; k < 300 && u_b.u_entry.qty != q; k = k + 1)
                press(q > u_b.u_entry.qty ? K_UP : K_DOWN);
        end
    endtask
    task set_trig;
        input integer t; integer k;
        begin
            focus_to(1);
            for (k = 0; k < 3000 && u_b.u_entry.trig != t; k = k + 1)
                press(t > u_b.u_entry.trig ? K_UP : K_DOWN);
        end
    endtask
    task submit; begin focus_to(2); press(K_CENTER); end endtask
    task order;
        input s; input [1:0] t; input integer q; input integer tr;
        begin
            set_side(s); set_type(t); set_qty(q);
            if (t != `OT_MKT) set_trig(tr);
            submit; settle;
        end
    endtask
    task set_price;
        input [1:0] s; input [15:0] p;
        begin force_stock = s; force_price = p; force_en = 1; step(1); force_en = 0; step(1); end
    endtask
    task do_tick; begin tick_req = 1; step(1); tick_req = 0; step(1); end endtask
    task set_stock; input [1:0] s; begin sel_stock = s; step(3); end endtask

    // ------------------------------------------------------------ scenarios
    integer bf, br, k, s, q, sd, cash_before, seed;

    initial begin
        step(5); sys_reset = 0; step(5);

        $display("---- I1 market buy 10, then partial sell 4 (divider path)");
        bf = n_fill;
        order(`SIDE_BUY, `OT_MKT, 10, 0);
        check(n_fill == bf + 1 && cash == 876850 && pos0 == 10 && cb0 == 123150, "I1 buy: cash 876850, pos 10, cost basis 123150");
        invariant("buy");
        order(`SIDE_SELL, `OT_MKT, 4, 0);   // bid 12295; avg cost 123150/10 = 12315
        check(n_fill == bf + 2 && pos0 == 6, "I1 sell: pos 6");
        check(cash == 876850 + 4 * 12295 - 100, "I1 sell: cash += proceeds - fee");
        check(realised == 4 * 12295 - 4 * 12315 - 100, "I1 sell: realised = -180");
        invariant("partial sell");

        $display("---- I2 the order engine's rejects never reach the ledger");
        br = n_rej; bf = n_fill;
        order(`SIDE_SELL, `OT_MKT, 7, 0);                    // only 6 held
        check(n_rej == br + 1 && last_rej == `RJ_NO_POS && n_fill == bf, "I2 sell 7 of 6: RJ_NO_POS in the order engine");
        order(`SIDE_BUY, `OT_MKT, 255, 0);                   // 255 * 12305 > cash
        check(n_rej == br + 2 && last_rej == `RJ_NO_CASH && n_fill == bf, "I2 buy 255: RJ_NO_CASH in the order engine");

        $display("---- I3 three stop sells trigger on one tick (divider each time)");
        set_price(0, 12300);
        bf = n_fill;
        order(`SIDE_SELL, `OT_STP, 1, 12000);
        order(`SIDE_SELL, `OT_STP, 1, 12000);
        order(`SIDE_SELL, `OT_STP, 1, 12000);
        check(pending_count == 3, "I3 three stops resting");
        set_price(0, 11800);                                 // bid 11795 <= 12000
        do_tick; settle;
        check(n_fill == bf + 3 && pos0 == 3 && pending_count == 0, "I3 three fills, pos 6 -> 3");
        invariant("three triggered sells");

        $display("---- I4 random orders on all four stocks");
        seed = 2026;
        for (k = 0; k < 60; k = k + 1) begin
            s = $unsigned($random(seed)) % 4;
            set_stock(s);
            if ($unsigned($random(seed)) % 3 == 0) begin     // move a price and tick
                set_price(s, 500 + $unsigned($random(seed)) % 20000);
                do_tick;
            end
            sd = $unsigned($random(seed)) % 2;
            q  = 1 + $unsigned($random(seed)) % 20;
            order(sd, `OT_MKT, q, 0);
            invariant("random order");
        end
        $display("     after random orders: cash %0d, pos %0d/%0d/%0d/%0d, realised %0d, %0d fills, %0d B rejects",
                 cash, pos0, pos1, pos2, pos3, realised, n_fill, n_rej);

        check(n_err == 0, "ledger never rejected a fill from the order engine");
        check(n_fill_busy == 0, "order engine never sent a fill while ledger_busy was high");

        if (n_fail == 0) $display("PASS: tb_BC_ledger (%0d checks)", n_pass);
        else             $display("FAIL: tb_BC_ledger (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end

    initial begin #200_000_000; $display("FAIL: tb_BC_ledger timeout"); $finish; end
endmodule
