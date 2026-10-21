`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_order_book: insert / cancel / full, the four trigger rules at their exact
// boundaries, gap fills, slot-order servicing, rescan on a mid-scan tick,
// scan_en gating, reset during a scan, and stop-loss / take-profit pairs (one
// leg leaving removes the other). The testbench plays exec_engine:
// it acks every request ACK_DELAY clocks after it appears and logs it.
module tb_order_book;
    reg clk = 0;
    always #5 clk = ~clk;

    reg        sys_reset = 1;
    reg        tick = 0;
    reg        scan_en = 1;
    reg [15:0] price0 = 10000, price1 = 5000, price2 = 9000, price3 = 1200;
    reg        ins = 0;
    reg [1:0]  ins_stock = 0;
    reg        ins_side = 0;
    reg [1:0]  ins_type = 0;
    reg [7:0]  ins_qty = 0;
    reg [15:0] ins_trig = 0;
    reg [1:0]  ins_brk = 0;
    reg        ins_pair = 0;
    reg [1:0]  pair_stock = 0;
    reg [7:0]  pair_qty = 0;
    reg [15:0] pair_sl = 0, pair_tp = 0;
    reg        cancel = 0;
    reg [2:0]  cancel_idx = 0;
    reg [2:0]  rd_idx = 0;
    reg        trq_ack = 0;
    reg        ack_en = 1;

    wire        full;
    wire [3:0]  count;
    wire [3:0]  free_cnt;
    wire        trq;
    wire [2:0]  trq_slot;
    wire [1:0]  trq_stock;
    wire        trq_side;
    wire [1:0]  trq_type;
    wire [7:0]  trq_qty;
    wire [15:0] trq_px;
    wire [1:0]  trq_brk;
    wire [7:0]  all_valid, all_side, all_leg;
    wire [15:0] all_stock, all_type;
    wire [63:0] all_qty;
    wire [127:0] all_trig;
    wire        rd_valid;
    wire [1:0]  rd_stock;
    wire        rd_side;
    wire [1:0]  rd_type;
    wire [7:0]  rd_qty;
    wire [15:0] rd_trig;

    order_book #(.SPREAD(5)) dut (
        .clk(clk), .sys_reset(sys_reset), .tick(tick), .scan_en(scan_en),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .ins(ins), .ins_stock(ins_stock), .ins_side(ins_side), .ins_type(ins_type),
        .ins_qty(ins_qty), .ins_trig(ins_trig), .ins_brk(ins_brk),
        .ins_pair(ins_pair), .pair_stock(pair_stock), .pair_qty(pair_qty),
        .pair_sl(pair_sl), .pair_tp(pair_tp),
        .cancel(cancel), .cancel_idx(cancel_idx),
        .full(full), .count(count), .free_cnt(free_cnt),
        .trq(trq), .trq_slot(trq_slot), .trq_stock(trq_stock), .trq_side(trq_side),
        .trq_type(trq_type), .trq_qty(trq_qty), .trq_px(trq_px), .trq_brk(trq_brk),
        .trq_ack(trq_ack),
        .rd_idx(rd_idx), .rd_valid(rd_valid), .rd_stock(rd_stock), .rd_side(rd_side),
        .rd_type(rd_type), .rd_qty(rd_qty), .rd_trig(rd_trig),
        .all_valid(all_valid), .all_side(all_side), .all_stock(all_stock), .all_type(all_type),
        .all_qty(all_qty), .all_trig(all_trig), .all_leg(all_leg)
    );

    // ------------------------------------------------------------ fake exec_engine
    integer ACK_DELAY = 3;
    integer wcnt = 0;
    integer n_req = 0;
    reg [2:0]  log_slot [0:31];
    reg [15:0] log_px   [0:31];
    reg [7:0]  log_qty  [0:31];
    reg [1:0]  log_brk  [0:31];

    always @(posedge clk) begin
        trq_ack <= 1'b0;
        if (!trq || trq_ack || !ack_en) begin
            wcnt <= 0;
        end else if (wcnt >= ACK_DELAY) begin
            trq_ack         <= 1'b1;
            log_slot[n_req] = trq_slot;
            log_px[n_req]   = trq_px;
            log_qty[n_req]  = trq_qty;
            log_brk[n_req]  = trq_brk;
            n_req           = n_req + 1;
            wcnt            <= 0;
        end else begin
            wcnt <= wcnt + 1;
        end
    end

    // ------------------------------------------------------------ helpers
    integer n_pass = 0, n_fail = 0;

    task check;
        input          cond;
        input [8*56:1] name;
        begin
            if (cond === 1'b1) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("FAIL: %0s (t=%0t)", name, $time);
            end
        end
    endtask

    task step;
        input integer n;
        begin
            repeat (n) @(posedge clk);
            #1;
        end
    endtask

    task insert;
        input [1:0]  s;
        input        sd;
        input [1:0]  t;
        input [7:0]  q;
        input [15:0] tr;
        begin
            ins_stock = s; ins_side = sd; ins_type = t; ins_qty = q; ins_trig = tr;
            ins = 1; step(1); ins = 0; step(1);
        end
    endtask

    task do_cancel;
        input [2:0] k;
        begin
            cancel_idx = k; cancel = 1; step(1); cancel = 0; step(1);
        end
    endtask

    task insert_pair;
        input [1:0]  s;
        input [7:0]  q;
        input [15:0] sl;
        input [15:0] tp;
        begin
            pair_stock = s; pair_qty = q; pair_sl = sl; pair_tp = tp;
            ins_pair = 1; step(1); ins_pair = 0; step(1);
        end
    endtask

    task do_tick;
        begin
            tick = 1; step(1); tick = 0;
        end
    endtask

    task clear_book;
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1) do_cancel(k);
        end
    endtask

    integer base, k;

    initial begin
        step(3);
        sys_reset = 0;
        step(2);

        // ---------------------------------------------------- B1 insert
        check(count == 0 && !full, "B1 empty after reset");
        insert(0, `SIDE_BUY, `OT_LMT, 10, 12000);
        rd_idx = 0; #1;
        check(count == 1, "B1 count 1");
        check(rd_valid && rd_stock == 0 && rd_side == `SIDE_BUY && rd_type == `OT_LMT
              && rd_qty == 10 && rd_trig == 12000, "B1 slot 0 fields");

        // ---------------------------------------------------- B2/B3 LMT BUY: ask <= trig
        price0 = 11996;  // ask 12001
        base = n_req; do_tick; step(30);
        check(n_req == base, "B2 lmt buy no trigger at ask 12001");
        price0 = 11995;  // ask 12000
        do_tick; step(30);
        check(n_req == base + 1 && log_slot[base] == 0 && log_px[base] == 12000 && log_qty[base] == 10,
              "B3 lmt buy triggers at ask == trig, fills at ask");
        check(count == 0, "B3 slot cleared after ack");

        // ---------------------------------------------------- B4 LMT SELL: bid >= trig
        insert(1, `SIDE_SELL, `OT_LMT, 7, 5000);
        price1 = 5004;   // bid 4999
        base = n_req; do_tick; step(30);
        check(n_req == base, "B4 lmt sell no trigger at bid 4999");
        price1 = 5005;   // bid 5000
        do_tick; step(30);
        check(n_req == base + 1 && log_px[base] == 5000, "B4 lmt sell triggers at bid == trig");

        // ---------------------------------------------------- B5 STP BUY: ask >= trig
        insert(2, `SIDE_BUY, `OT_STP, 3, 9000);
        price2 = 8994;   // ask 8999
        base = n_req; do_tick; step(30);
        check(n_req == base, "B5 stp buy no trigger at ask 8999");
        price2 = 8995;   // ask 9000
        do_tick; step(30);
        check(n_req == base + 1 && log_px[base] == 9000, "B5 stp buy triggers at ask == trig");

        // ---------------------------------------------------- B6 STP SELL gap: bid <= trig
        insert(3, `SIDE_SELL, `OT_STP, 4, 1100);
        price3 = 1106;   // bid 1101: no
        base = n_req; do_tick; step(30);
        check(n_req == base, "B6 stp sell no trigger at bid 1101");
        price3 = 1000;   // gap: bid 995, well through 1100
        do_tick; step(30);
        check(n_req == base + 1 && log_px[base] == 995, "B6 stp sell gap fills at bid 995");
        check(count == 0, "B6 book empty");

        // ---------------------------------------------------- B7 stock isolation
        price1 = 5000;
        insert(1, `SIDE_BUY, `OT_LMT, 1, 4000);
        price0 = 100;    // only stock 0 crashes
        base = n_req; do_tick; step(30);
        check(n_req == base && count == 1, "B7 stock 1 order ignores stock 0 price");
        clear_book;
        check(count == 0, "B7 cancel cleared it");

        // ---------------------------------------------------- B8 full
        price0 = 10000;
        for (k = 0; k < 8; k = k + 1) insert(0, `SIDE_BUY, `OT_LMT, k + 1, 100);
        check(count == 8 && full, "B8 8 orders -> full");
        insert(0, `SIDE_BUY, `OT_LMT, 99, 100);
        rd_idx = 7; #1;
        check(count == 8 && rd_qty == 8, "B8 9th insert ignored, slot 7 unchanged");

        // ---------------------------------------------------- B9 cancel -> lowest free reused
        do_cancel(3);
        do_cancel(5);
        check(count == 6 && !full, "B9 cancel 3 and 5");
        insert(0, `SIDE_BUY, `OT_LMT, 33, 100);
        rd_idx = 3; #1;
        check(rd_valid && rd_qty == 33, "B9 insert reuses lowest free slot 3");
        clear_book;

        // ---------------------------------------------------- B10 3 triggers, slot order
        price0 = 10000;  // bid 9995, ask 10005
        insert(0, `SIDE_BUY,  `OT_LMT, 1, 10005);   // slot 0: ask <= 10005  yes
        insert(0, `SIDE_BUY,  `OT_LMT, 2,  9000);   // slot 1: no
        insert(0, `SIDE_SELL, `OT_STP, 3, 10000);   // slot 2: bid <= 10000  yes
        insert(0, `SIDE_SELL, `OT_LMT, 4, 20000);   // slot 3: no
        insert(0, `SIDE_BUY,  `OT_STP, 5, 10005);   // slot 4: ask >= 10005  yes
        ACK_DELAY = 10;
        base = n_req; do_tick; step(100);
        check(n_req == base + 3, "B10 three requests");
        check(log_slot[base] == 0 && log_slot[base+1] == 2 && log_slot[base+2] == 4, "B10 serviced in slot order 0,2,4");
        check(log_qty[base] == 1 && log_qty[base+1] == 3 && log_qty[base+2] == 5, "B10 qty matches slots");
        check(count == 2, "B10 two untriggered orders remain");
        clear_book;

        // ---------------------------------------------------- B11 tick mid-scan -> rescan
        price0 = 10000;
        insert(0, `SIDE_BUY, `OT_LMT, 1,  9000);    // slot 0: not yet
        insert(0, `SIDE_BUY, `OT_LMT, 2, 10005);    // slot 1: yes now
        ACK_DELAY = 10;
        base = n_req; do_tick;
        wait (trq); step(2);                        // scan is parked on slot 1
        price0 = 8990;                              // ask 8995 <= 9000
        do_tick;
        step(100);
        check(n_req == base + 2, "B11 rescan catches slot 0 after mid-scan tick");
        check(log_slot[base] == 1 && log_slot[base+1] == 0, "B11 order: slot 1 then slot 0");
        check(count == 0, "B11 book empty");

        // ---------------------------------------------------- B12 scan_en gates ticks
        price0 = 10000;
        insert(0, `SIDE_BUY, `OT_LMT, 1, 10005);
        scan_en = 0;
        base = n_req; do_tick; step(30);
        check(n_req == base && count == 1, "B12 no scan while !scan_en");
        scan_en = 1;
        do_tick; step(30);
        check(n_req == base + 1 && count == 0, "B12 scans again once enabled");

        // ---------------------------------------------------- B13 reset mid-scan
        for (k = 0; k < 4; k = k + 1) insert(0, `SIDE_BUY, `OT_LMT, k + 1, 10005);
        ack_en = 0;                                 // exec never answers
        base = n_req; do_tick;
        wait (trq); step(3);
        sys_reset = 1; step(1); sys_reset = 0; ack_en = 1;
        check(!trq && count == 0 && dut.state == 0, "B13 reset clears book, drops trq, FSM idle");
        step(50);
        check(!trq && n_req == base, "B13 no stray request after reset");

        // ---------------------------------------------------- B14 stop-loss / take-profit pair
        price0 = 10000;  // bid 9995
        check(count == 0 && free_cnt == 8, "B14 empty, 8 free");
        insert_pair(0, 10, 9000, 11000);
        check(count == 2 && free_cnt == 6 && all_leg == 8'b0000_0011, "B14 pair in slots 0 and 1, both legs");
        rd_idx = 0; #1;
        check(rd_side == `SIDE_SELL && rd_type == `OT_STP && rd_qty == 10 && rd_trig == 9000, "B14 slot 0 = STP SELL 10 @ 90.00 (stop-loss)");
        rd_idx = 1; #1;
        check(rd_side == `SIDE_SELL && rd_type == `OT_LMT && rd_qty == 10 && rd_trig == 11000, "B14 slot 1 = LMT SELL 10 @ 110.00 (take-profit)");
        check(dut.s_lnk[0] == 1 && dut.s_lnk[1] == 0, "B14 legs point at each other");
        check(all_trig[15:0] == 9000 && all_trig[31:16] == 11000 && all_qty[15:0] == 16'h0A0A, "B14 all_* outputs");

        // ---------------------------------------------------- B15 stop-loss fills, take-profit goes
        price0 = 9005;   // bid 9000 <= 9000
        base = n_req; do_tick; step(30);
        check(n_req == base + 1 && log_slot[base] == 0 && log_px[base] == 9000, "B15 stop-loss triggers at bid 90.00");
        check(count == 0 && all_leg == 0, "B15 take-profit removed with it");

        // ---------------------------------------------------- B16 take-profit fills, stop-loss goes
        price0 = 10000;
        insert_pair(0, 10, 9000, 11000);
        price0 = 11005;  // bid 11000 >= 11000
        base = n_req; do_tick; step(30);
        check(n_req == base + 1 && log_slot[base] == 1 && log_px[base] == 11000, "B16 take-profit triggers at bid 110.00");
        check(count == 0, "B16 stop-loss removed with it");

        // ---------------------------------------------------- B17 cancel one leg -> both go
        price0 = 10000;
        insert(1, `SIDE_BUY, `OT_LMT, 5, 100);      // slot 0, unrelated
        insert_pair(0, 10, 9000, 11000);            // slots 1 and 2
        do_cancel(2);
        check(count == 1 && all_valid == 8'b0000_0001, "B17 cancelling the TP removes the SL too, other order stays");
        // the empty slots keep stale link bits; cancelling an empty slot must not touch anything
        do_cancel(1);
        check(count == 1 && all_valid == 8'b0000_0001, "B17 cancel of an empty former leg does nothing");
        clear_book;

        // ---------------------------------------------------- B18 cancel a leg while the other is filling
        price0 = 10000;
        insert_pair(0, 10, 9000, 11000);            // SL slot 0, TP slot 1
        ack_en = 0;
        price0 = 9005;                              // SL triggers
        base = n_req; do_tick;
        wait (trq); step(2);
        check(trq_slot == 0, "B18 stop-loss is waiting on exec");
        do_cancel(1);                               // cancel the TP while the SL is filling
        check(all_valid == 8'b0000_0001 && dut.lnk_v[0] == 0, "B18 TP gone, waiting SL unlinked");
        insert(2, `SIDE_BUY, `OT_LMT, 77, 100);     // reuses slot 1
        ack_en = 1; step(30);
        rd_idx = 1; #1;
        check(n_req == base + 1 && count == 1 && rd_valid && rd_qty == 77, "B18 SL fill does not remove the new order in slot 1");
        clear_book;

        // ---------------------------------------------------- B19 pair needs two free slots
        price0 = 10000;
        for (k = 0; k < 7; k = k + 1) insert(0, `SIDE_BUY, `OT_LMT, k + 1, 100);
        insert_pair(0, 10, 9000, 11000);
        check(count == 7 && all_leg == 0, "B19 pair ignored with one free slot");
        clear_book;

        // ---------------------------------------------------- B20 SL/TP setting rides with a pending BUY
        price0 = 10000;
        ins_brk = `BRK_5;
        insert(0, `SIDE_BUY,  `OT_LMT, 1, 10005);   // slot 0: triggers now
        insert(0, `SIDE_SELL, `OT_LMT, 1, 9995);    // slot 1: triggers now; a SELL keeps no SL/TP
        ins_brk = `BRK_OFF;
        base = n_req; do_tick; step(40);
        check(n_req == base + 2 && log_brk[base] == `BRK_5 && log_brk[base+1] == `BRK_OFF, "B20 trq_brk: BUY keeps 5%, SELL has none");

        if (n_fail == 0) $display("PASS: tb_order_book (%0d checks)", n_pass);
        else             $display("FAIL: tb_order_book (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: tb_order_book timeout");
        $finish;
    end
endmodule
