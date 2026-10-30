`timescale 1ns / 1ps
// control state machine for the ledger
// Decides what happens on each clock, ledger.v holds the registers and does the maths.
//
//   IDLE --fill, rejected------------------> DONE  --> IDLE   (err pulse)
//   IDLE --fill, buy----------------------> BUY   --> IDLE   (apply buy)
//   IDLE --fill, sell whole position------> APPLY --> IDLE   (apply sell)
//   IDLE --fill, sell part of position----> DIV --div_done--> APPLY --> IDLE
//
// ledger_busy is high in every state except IDLE, so it rises the clock after
// any fill and falls on the same clock cash/positions are updated.
module ledger_fsm (
    input  wire clk,
    input  wire rst,
    input  wire fill,
    input  wire fill_side,     // 0 = buy, 1 = sell
    input  wire reject,        // from ledger_validate
    input  wire full_close,    // from ledger_validate
    input  wire div_done,      // from seq_divider
    output wire ledger_busy,
    output wire latch,         // capture the incoming fill this clock
    output wire take_full,     // removed <= whole cost basis this clock
    output wire take_avg,      // removed <= avg cost * qty this clock
    output wire do_buy,        // apply buy this clock
    output wire do_apply,      // apply sell this clock
    output reg  div_start,     // 1-clock pulse to start the divider
    output reg  err            // 1-clock pulse when a fill is rejected
);
    localparam IDLE = 3'd0, DIV = 3'd1, APPLY = 3'd2, BUY = 3'd3, DONE = 3'd4;
    reg [2:0] state;

    // control outputs (decoded from the current state)
    assign ledger_busy = (state != IDLE);
    assign latch       = (state == IDLE) & fill;
    assign take_full   = latch & ~reject & fill_side & full_close;
    assign take_avg    = (state == DIV) & div_done;
    assign do_buy      = (state == BUY);
    assign do_apply    = (state == APPLY);

    always @(posedge clk) begin
        div_start <= 1'b0;
        err       <= 1'b0;
        if (rst) begin
            state <= IDLE;
        end else begin
            case (state)
            IDLE: if (fill) begin
                if (reject) begin
                    err   <= 1'b1;
                    state <= DONE;
                end else if (!fill_side)
                    state <= BUY;
                else if (full_close)
                    state <= APPLY;
                else begin
                    div_start <= 1'b1;
                    state     <= DIV;
                end
            end
            DIV:     if (div_done) state <= APPLY;
            BUY:     state <= IDLE;
            APPLY:   state <= IDLE;
            DONE:    state <= IDLE;   // reject: hold busy for one clock, change nothing
            default: state <= IDLE;
            endcase
        end
    end
endmodule
