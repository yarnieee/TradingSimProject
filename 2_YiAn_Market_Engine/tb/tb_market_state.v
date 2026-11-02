`timescale 1ns / 1ps

// Unit tests for the event generator and regime transition policy.
module tb_market_state;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg start = 1'b0;
    reg day_tick = 1'b0;
    reg [1:0] random_state = 2'b01;
    reg [2:0] random_interval = 3'd0;
    reg [2:0] event_request = 3'd0;
    reg [7:0] event_random = 8'h00;
    wire [1:0] state;
    wire [2:0] active_event;

    market_state dut (
        .clk(clk), .rst(rst), .start(start), .day_tick(day_tick),
        .random_state(random_state), .random_interval(random_interval),
        .event_request(event_request), .state(state),
        .active_event(active_event)
    );

    wire [2:0] generated_event;
    market_events event_dut (
        .random_value(event_random),
        .event_request(generated_event)
    );
    integer n_pass = 0;
    integer n_fail = 0;

    task check;
        input condition;
        input [8*96:1] name;
        begin
            if (condition === 1'b1)
                n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("FAIL: %0s (t=%0t state=%0d event=%0d)",
                    name, $time, state, active_event);
            end
        end
    endtask

    task pulse_day;
        begin
            @(negedge clk);
            day_tick = 1'b1;
            @(negedge clk);
            day_tick = 1'b0;
        end
    endtask

    initial begin
        // Start in normal with a five-day scheduled regime.
        repeat (2) @(posedge clk);
        rst = 1'b0;
        start = 1'b1;
        @(posedge clk);
        #1 start = 1'b0;
        check(state == 2'b01 && active_event == 3'd0,
              "start initializes normal regime with no event");

        // Selecting the current normal state must now produce a real
        // transition rather than silently staying normal.
        repeat (5) pulse_day;
        check(state == 2'b10 && active_event == 3'd0,
              "repeated normal candidate transitions to bull");

        // A rally event takes over immediately and lasts one day when the
        // interval low bits are zero.
        event_request = 3'd1;
        pulse_day;
        event_request = 3'd0;
        check(state == 2'b10 && active_event == 3'd1,
              "rally event selects bull state");
        pulse_day;
        check(state == 2'b01 && active_event == 3'd0,
              "rally event expires and resumes normal regime");

        // A crash event with interval low bits of one lasts two days.
        random_interval = 3'd1;
        event_request = 3'd3;
        pulse_day;
        event_request = 3'd0;
        check(state == 2'b11 && active_event == 3'd3,
              "crash event selects crash state");
        pulse_day;
        check(state == 2'b11 && active_event == 3'd3,
              "crash event remains active for its duration");
        pulse_day;
        check(active_event == 3'd0 && state != 2'b11,
              "crash event expires before ordinary transition");

        // Event generator: zero high bits trigger, other values do not.
        event_random = 8'b0000_0000;
        #1 check(generated_event == 3'd1,
                 "event generator maps low sample to rally");
        event_random = 8'b0000_0001;
        #1 check(generated_event == 3'd2,
                 "event generator maps next sample to sell-off");
        event_random = 8'b0000_0010;
        #1 check(generated_event == 3'd3,
                 "event generator maps next sample to crash");
        event_random = 8'b0010_0000;
        #1 check(generated_event == 3'd0,
                 "event generator suppresses non-trigger samples");

        if (n_fail == 0) $display("PASS: tb_market_state (%0d checks)", n_pass);
        else             $display("FAIL: tb_market_state (%0d failed, %0d passed)", n_fail, n_pass);
        $finish;
    end

    initial begin
        #100_000;
        $display("FAIL: tb_market_state timeout");
        $finish;
    end
endmodule
