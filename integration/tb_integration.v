`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_integration: plays the game on Integration_Top with raw button presses,
// through D's screens, and checks that the orders land in B and C correctly.
// Only two times are shrunk: a trading day is 4000 clocks (not 2 s) and the
// debounce is 50 clocks (not 20 ms). Every module is the owner's own code.
//
// A's seed files: A_top asks for "storage/AMD_seed.mem", but Vivado's simulator
// copies .mem files flat into its run folder. For simulation only, the defparams
// below point A at the plain file names. (Synthesis is not affected.)
module tb_integration;
    reg clk = 0;
    always #5 clk = ~clk;

    reg  rst = 1;
    reg  btnU = 0, btnD = 0, btnL = 0, btnR = 0, btnC = 0;
    wire [7:0]  JA, JB, seg;
    wire [15:0] led;
    wire [3:0]  an;

    defparam dut.A_inst.amd_stock_inst.SEED_FILE = "AMD_seed.mem";
    defparam dut.A_inst.mcd_stock_inst.SEED_FILE = "MCD_seed.mem";

    localparam DAY = 4000;
    Integration_Top #(.DAY_MAX_COUNT(DAY), .DEBOUNCE_CTR(32'd50)) dut (
        .clk(clk), .rst(rst), .btnU(btnU), .btnD(btnD), .btnL(btnL), .btnR(btnR), .btnC(btnC),
        .JA(JA), .JB(JB), .led(led), .an(an), .seg(seg)
    );

    // game_fsm screens
    localparam S_TITLE = 0, S_PORTFOLIO = 1, S_STOCKS = 2, S_SPECIFIC = 3, S_BUY = 4,
               S_SELL = 5, S_QUANTITY = 6, S_CONFIRM = 7;

    integer n_pass = 0, n_fail = 0;
    task check;
        input          cond;
        input [8*72:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s (t=%0t)", name, $time); end
        end
    endtask

    integer n_fill = 0, n_rej = 0, n_err = 0, n_tick = 0;
    reg [2:0]  last_rej = 0;
    reg [15:0] last_px = 0;
    always @(posedge clk) if (!dut.sys_reset) begin
        if (dut.fill)       begin n_fill = n_fill + 1; last_px = dut.fill_price; end
        if (dut.reject)     begin n_rej = n_rej + 1; last_rej = dut.reject_code; end
        if (dut.ledger_err) n_err = n_err + 1;
        if (dut.tick)       n_tick = n_tick + 1;
    end

    // one press, held long enough for the debouncer (50 clocks)
    task press;
        input integer b;      // 0 U, 1 D, 2 L, 3 R, 4 C
        begin
            case (b) 0: btnU = 1; 1: btnD = 1; 2: btnL = 1; 3: btnR = 1; default: btnC = 1; endcase
            repeat (80) @(posedge clk);
            btnU = 0; btnD = 0; btnL = 0; btnR = 0; btnC = 0;
            repeat (80) @(posedge clk);
        end
    endtask
    localparam U = 0, D = 1, L = 2, R = 3, C = 4;

    // place an order through D's screens, starting from PORTFOLIO
    task trade;
        input integer stock;   // 0..3 in D's stock list
        input         sell;
        input integer qty;     // 0..9 (ones digit only, enough here)
        integer k;
        begin
            press(R); press(C);                         // portfolio -> stocks (cursor 0)
            for (k = 0; k < stock; k = k + 1) press(D); // pick the stock
            press(C);                                   // -> specific
            if (sell) press(R);                         // sell instead of buy
            press(C);                                   // -> buy / sell screen
            press(R); press(C);                         // "quantity" -> quantity screen (qty 0)
            for (k = 0; k < qty; k = k + 1) press(U);   // ones digit
            press(C);                                   // back to buy / sell screen (cursor 0)
            press(R); press(R); press(C);               // "confirmation" -> CONFIRM: order goes to B
            repeat (300) @(posedge clk);                // B -> C: fill and ledger update
        end
    endtask

    integer cash0, f0, r0;
    reg [15:0] p0;

    initial begin
        repeat (10) @(posedge clk);
        rst = 0;
        wait (dut.amd_ready && dut.mcd_ready);
        repeat (DAY + 100) @(posedge clk);              // one day ticks over
        check(dut.price0 != 0 && dut.price1 != 0, "A: AMD and MCD have prices (if not: AMD_seed.mem / MCD_seed.mem not found)");
        check(n_tick >= 1, "A -> B: a tick reached B after a trading day");
        $display("     AMD %0d c, MCD %0d c", dut.price0, dut.price1);
        // A's own price maths, reported but not counted: see integration/README.md
        if (dut.price0 == 16'hFFFF || dut.price1 == 16'hFFFF || dut.price0 < 100 || dut.price1 < 100)
            $display("WARN: A's prices look wrong (pinned at $655.35 or near 0): see integration/README.md, Known issues");

        // ---------------- title -> portfolio
        press(C);
        check(dut.screen_state == S_PORTFOLIO, "D: title -> portfolio");

        // ---------------- buy 3 AMD
        cash0 = dut.cash; f0 = n_fill; p0 = dut.price0;
        trade(0, 0, 3);
        check(dut.sel_stock == 0, "D -> B: AMD selected");
        check(n_fill == f0 + 1 && dut.pos0 == 3, "B -> C: buy 3 AMD filled, position 3");
        check(dut.cash == cash0 - 3 * last_px - 100, "C: cash down by 3 x ask + fee");
        check(last_px == dut.B_inst.u_exec.u_spread.ask || last_px == ((p0 > 16'd65530) ? 16'hFFFF : p0 + 16'd5),
              "B: filled at the ask (price + 5 c, saturating)");
        check(dut.screen_state == S_CONFIRM, "D: on the confirm screen");
        press(C);                                       // confirm -> portfolio

        // ---------------- sell 2 MCD with none held: rejected by B, never reaches C
        f0 = n_fill; r0 = n_rej;
        trade(1, 1, 2);
        check(dut.sel_stock == 1, "D -> B: MCD selected");
        check(n_rej == r0 + 1 && last_rej == `RJ_NO_POS && n_fill == f0, "B: sell MCD with none held -> NO POS");
        press(C);

        // ---------------- stock 3 has no data from A: closed
        r0 = n_rej;
        trade(2, 0, 1);
        check(n_rej == r0 + 1 && last_rej == `RJ_NOT_LIVE, "B: stock 3 has no price -> NOT LIVE");
        press(C);

        // ---------------- quantity 0 (confirm without setting it)
        r0 = n_rej;
        trade(0, 0, 0);
        check(n_rej == r0 + 1 && last_rej == `RJ_BAD_QTY, "B: quantity 0 -> BAD QTY");
        press(C);

        // ---------------- sell 1 AMD back: partial sell through C's divider
        f0 = n_fill;
        trade(0, 1, 1);
        check(n_fill == f0 + 1 && dut.pos0 == 2, "B -> C: sell 1 AMD, position 2");
        check(dut.cash + dut.cb0 + dut.cb1 + dut.cb2 + dut.cb3 == 32'd1_000_000 + dut.realised,
              "C: ledger invariant holds");

        check(n_err == 0, "C never rejected a fill from B");
        $display("     cash %0d c, AMD position %0d, realised %0d c, %0d fills, %0d rejects",
                 dut.cash, dut.pos0, dut.realised, n_fill, n_rej);
        if (n_fail == 0) $display("PASS: tb_integration (%0d checks)", n_pass);
        else             $display("FAIL: tb_integration (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end

    initial begin #20_000_000; $display("FAIL: tb_integration timeout"); $finish; end
endmodule
