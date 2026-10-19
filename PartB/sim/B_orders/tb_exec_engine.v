`timescale 1ns / 1ps
`include "trading_defs.vh"

// tb_exec_engine: exec_engine against stub_ledger, with the testbench driving
// the submit port and playing order_book on the trigger port.
module tb_exec_engine;
    reg clk = 0;
    always #5 clk = ~clk;

    reg        sys_reset = 1;
    reg        game_live = 1;
    reg [15:0] price0 = 12300, price1 = 4520, price2 = 8800, price3 = 1230;
    reg        submit_req = 0;
    reg [1:0]  sub_stock = 0;
    reg        sub_side = 0;
    reg [1:0]  sub_type = 0;
    reg [7:0]  sub_qty = 0;
    reg [15:0] sub_trig = 0;
    reg        book_full = 0;
    reg        trq = 0;
    reg [1:0]  trq_stock = 0;
    reg        trq_side = 0;
    reg [1:0]  trq_type = 0;
    reg [7:0]  trq_qty = 0;
    reg [15:0] trq_px = 0;

    wire        trq_ack, ins, placed, fill, reject, ledger_busy;
    wire [1:0]  ins_stock, fill_stock;
    wire        ins_side, fill_side;
    wire [1:0]  ins_type;
    wire [7:0]  ins_qty, fill_qty;
    wire [15:0] ins_trig, fill_price, fill_fee;
    wire [2:0]  reject_code;
    wire [31:0] cash;
    wire [9:0]  pos0, pos1, pos2, pos3;

    exec_engine #(.SPREAD(5), .FEE(100)) dut (
        .clk(clk), .sys_reset(sys_reset), .game_live(game_live),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy),
        .submit_req(submit_req), .sub_stock(sub_stock), .sub_side(sub_side),
        .sub_type(sub_type), .sub_qty(sub_qty), .sub_trig(sub_trig),
        .book_full(book_full),
        .trq(trq), .trq_stock(trq_stock), .trq_side(trq_side), .trq_type(trq_type),
        .trq_qty(trq_qty), .trq_px(trq_px), .trq_ack(trq_ack),
        .ins(ins), .ins_stock(ins_stock), .ins_side(ins_side), .ins_type(ins_type),
        .ins_qty(ins_qty), .ins_trig(ins_trig), .placed(placed),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .reject(reject), .reject_code(reject_code)
    );

    stub_ledger #(.START_CASH(1000000), .BUSY_CYCLES(40)) u_ledger (
        .clk(clk), .sys_reset(sys_reset),
        .fill(fill), .fill_stock(fill_stock), .fill_side(fill_side),
        .fill_qty(fill_qty), .fill_price(fill_price), .fill_fee(fill_fee),
        .cash(cash), .pos0(pos0), .pos1(pos1), .pos2(pos2), .pos3(pos3),
        .ledger_busy(ledger_busy)
    );

    // ------------------------------------------------------------ event log
    integer n_fill = 0, n_rej = 0, n_ins = 0, n_ack = 0;
    integer fill_t [0:15];
    reg [1:0]  f_stock [0:15];
    reg [15:0] f_price [0:15];
    reg [2:0]  last_rej = 0;

    always @(posedge clk) begin
        if (fill) begin
            fill_t[n_fill]  = $time;
            f_stock[n_fill] = fill_stock;
            f_price[n_fill] = fill_price;
            n_fill = n_fill + 1;
        end
        if (reject) begin
            last_rej = reject_code;
            n_rej = n_rej + 1;
        end
        if (ins)     n_ins = n_ins + 1;
        if (trq_ack) begin
            n_ack = n_ack + 1;
            trq <= 1'b0;          // the book drops its request on ack
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

    task submit;
        input [1:0]  s;
        input        sd;
        input [1:0]  t;
        input [7:0]  q;
        input [15:0] tr;
        begin
            sub_stock = s; sub_side = sd; sub_type = t; sub_qty = q; sub_trig = tr;
            submit_req = 1; step(1); submit_req = 0;
        end
    endtask

    task book_req;
        input [1:0]  s;
        input        sd;
        input [1:0]  t;
        input [7:0]  q;
        input [15:0] px;
        begin
            trq_stock = s; trq_side = sd; trq_type = t; trq_qty = q; trq_px = px;
            trq = 1;
        end
    endtask

    integer b_fill, b_rej, b_ins, b_ack;
    task mark;
        begin
            b_fill = n_fill; b_rej = n_rej; b_ins = n_ins; b_ack = n_ack;
        end
    endtask

    initial begin
        step(3);
        sys_reset = 0;
        step(2);

        // ---------------------------------------------------- E1 MKT BUY 10 @ 12300
        mark;
        submit(0, `SIDE_BUY, `OT_MKT, 10, 0);
        step(10);
        check(n_fill == b_fill + 1, "E1 one fill");
        check(fill_stock == 0 && fill_side == `SIDE_BUY && fill_qty == 10, "E1 fill fields");
        check(fill_price == 12305 && fill_fee == 100, "E1 fills at ask 12305, fee 100");
        step(60);
        check(cash == 876850 && pos0 == 10, "E1 ledger cash 876850, pos0 10");

        // ---------------------------------------------------- E2 submit while ledger busy
        mark;
        submit(0, `SIDE_BUY, `OT_MKT, 1, 0);
        wait (ledger_busy);
        submit(1, `SIDE_BUY, `OT_MKT, 1, 0);         // arrives mid-busy
        step(100);
        check(n_fill == b_fill + 2, "E2 both fills issued");
        // busy spans 40 clocks after the first fill; stub_ledger also stops
        // the sim with FAIL if a fill ever lands while busy
        check(fill_t[b_fill + 1] >= fill_t[b_fill] + 41 * 10, "E2 second fill waited out ledger_busy");

        // ---------------------------------------------------- E3 rejects
        mark; game_live = 0;
        submit(0, `SIDE_BUY, `OT_MKT, 1, 0); step(10);
        check(n_rej == b_rej + 1 && last_rej == `RJ_NOT_LIVE && n_fill == b_fill, "E3 NOT_LIVE");
        game_live = 1;

        mark; submit(0, `SIDE_BUY, `OT_MKT, 0, 0); step(10);
        check(n_rej == b_rej + 1 && last_rej == `RJ_BAD_QTY, "E3 BAD_QTY (scenario 4)");

        mark; submit(2, `SIDE_SELL, `OT_MKT, 5, 0); step(10);
        check(n_rej == b_rej + 1 && last_rej == `RJ_NO_POS, "E3 NO_POS");

        mark; submit(0, `SIDE_BUY, `OT_MKT, 255, 0); step(10);
        check(n_rej == b_rej + 1 && last_rej == `RJ_NO_CASH && n_fill == b_fill, "E3 NO_CASH");

        mark; submit(0, `SIDE_BUY, `OT_LMT, 1, 0); step(10);
        check(n_rej == b_rej + 1 && last_rej == `RJ_BAD_TRIG, "E3 BAD_TRIG");

        mark; book_full = 1; submit(0, `SIDE_BUY, `OT_LMT, 1, 12000); step(10); book_full = 0;
        check(n_rej == b_rej + 1 && last_rej == `RJ_BOOK_FULL && n_ins == b_ins, "E3 BOOK_FULL");

        // ---------------------------------------------------- E4 pending submit -> insert
        mark;
        submit(3, `SIDE_BUY, `OT_STP, 20, 1300);
        wait (ins);
        check(ins_stock == 3 && ins_side == `SIDE_BUY && ins_type == `OT_STP && ins_qty == 20 && ins_trig == 1300,
              "E4 insert fields");
        step(10);
        check(n_ins == b_ins + 1 && n_fill == b_fill && n_rej == b_rej, "E4 insert only, no fill");

        // ---------------------------------------------------- E5 book trigger fills at book price
        mark;
        book_req(2, `SIDE_BUY, `OT_LMT, 3, 8700);    // book latched ask 8700
        step(10);
        check(n_fill == b_fill + 1 && fill_price == 8700 && fill_stock == 2 && fill_qty == 3,
              "E5 fill at the price the book latched");
        check(n_ack == b_ack + 1 && !trq, "E5 book acked");
        step(60);

        // ---------------------------------------------------- E6 trigger fails re-validation
        mark;
        book_req(0, `SIDE_BUY, `OT_LMT, 255, 60000);
        step(10);
        check(n_rej == b_rej + 1 && last_rej == `RJ_TRIG_FAIL && n_fill == b_fill, "E6 TRIG_FAIL");
        check(n_ack == b_ack + 1 && !trq, "E6 slot acked so it gets cleared");

        // ---------------------------------------------------- E7 submit beats book request
        mark;
        @(negedge clk);
        book_req(2, `SIDE_BUY, `OT_LMT, 1, 8805);
        sub_stock = 1; sub_side = `SIDE_BUY; sub_type = `OT_MKT; sub_qty = 1; sub_trig = 0;
        submit_req = 1; @(negedge clk); submit_req = 0;
        step(100);
        check(n_fill == b_fill + 2, "E7 both served");
        check(f_stock[b_fill] == 1 && f_stock[b_fill + 1] == 2, "E7 submit first, then book");

        // ---------------------------------------------------- E8 reset mid-job
        mark;
        submit(0, `SIDE_BUY, `OT_MKT, 1, 0);
        wait (ledger_busy);
        submit(0, `SIDE_BUY, `OT_MKT, 1, 0);         // parked in CHECK
        step(2);
        sys_reset = 1; step(1); sys_reset = 0;
        step(100);
        check(n_fill == b_fill + 1 && dut.state == 0 && !dut.hold_v, "E8 reset drops the parked job");

        if (n_fail == 0) $display("PASS: tb_exec_engine (%0d checks)", n_pass);
        else             $display("FAIL: tb_exec_engine (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: tb_exec_engine timeout");
        $finish;
    end
endmodule
