
`timescale 1ns / 1ps

// Hold a market state for five to twelve day ticks and apply short-lived
// market events on top of the normal regime schedule.
//
// State encoding:
//   2'b00 = bear
//   2'b01 = normal
//   2'b10 = bull
//   2'b11 = crash
//
// Event encoding:
//   3'd0 = no event
//   3'd1 = rally
//   3'd2 = sell-off
//   3'd3 = crash
module market_state(
    input wire       clk,
    input wire       rst,
    input wire       start,
    input wire       day_tick,
    input wire [1:0] random_state,
    input wire [2:0] random_interval,
    input wire [2:0] event_request,
    output reg [1:0] state = 2'b01,
    output reg [2:0] active_event = 3'd0
    );

    localparam [2:0] EVENT_NONE    = 3'd0;
    localparam [2:0] EVENT_RALLY   = 3'd1;
    localparam [2:0] EVENT_SELL_OFF = 3'd2;
    localparam [2:0] EVENT_CRASH   = 3'd3;

    reg [3:0] days_in_state = 4'b0;
    reg [3:0] state_length = 4'd5;
    reg [2:0] event_days = 3'b0;

    // If the random chooser selects the current regime, move to a
    // neighbouring regime instead of creating a silent no-op transition.
    function [1:0] choose_next_state;
        input [1:0] current_state;
        input [1:0] candidate_state;
        begin
            if (candidate_state != current_state) begin
                choose_next_state = candidate_state;
            end else begin
                case (current_state)
                    2'b00: choose_next_state = 2'b01; // bear -> normal
                    2'b01: choose_next_state = 2'b10; // normal -> bull
                    2'b10: choose_next_state = 2'b01; // bull -> normal
                    default: choose_next_state = 2'b01; // crash -> normal
                endcase
            end
        end
    endfunction

    function [1:0] event_state;
        input [2:0] event_value;
        begin
            case (event_value)
                EVENT_RALLY:    event_state = 2'b10;
                EVENT_SELL_OFF: event_state = 2'b00;
                EVENT_CRASH:    event_state = 2'b11;
                default:        event_state = 2'b01;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state <= 2'b01;
            days_in_state <= 4'b0;
            state_length <= 4'd5;
            event_days <= 3'b0;
            active_event <= EVENT_NONE;
        end else if (start) begin
            state <= 2'b01;
            days_in_state <= 4'b0;
            state_length <= 4'd5 + random_interval;
            event_days <= 3'b0;
            active_event <= EVENT_NONE;
        end else if (day_tick) begin
            if (event_days != 3'b0) begin
                // An event owns the regime until its duration expires.  The
                // following day resumes the ordinary regime schedule.
                if (event_days == 3'd1) begin
                    event_days <= 3'b0;
                    active_event <= EVENT_NONE;
                    state <= choose_next_state(state, random_state);
                    days_in_state <= 4'b0;
                    state_length <= 4'd5 + random_interval;
                end else begin
                    event_days <= event_days - 1'b1;
                end
            end else if ((event_request == EVENT_RALLY)
                || (event_request == EVENT_SELL_OFF)
                || (event_request == EVENT_CRASH)) begin
                // Event duration is one to four trading days.  The ordinary
                // regime counter is reset so the event cannot be immediately
                // overwritten by a scheduled regime transition.
                active_event <= event_request;
                if (event_request[1:0] == 2'b00)
                    event_days <= 3'd1;
                else
                    event_days <= {1'b0, random_interval[1:0]} + 3'd1;
                state <= event_state(event_request);
                days_in_state <= 4'b0;
            end else if ((days_in_state + 1'b1) >= state_length) begin
                state <= choose_next_state(state, random_state);
                days_in_state <= 4'b0;
                state_length <= 4'd5 + random_interval;
            end else begin
                days_in_state <= days_in_state + 1'b1;
            end
        end
    end

endmodule
