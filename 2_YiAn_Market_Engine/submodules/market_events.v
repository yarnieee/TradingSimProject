`timescale 1ns / 1ps

// Convert one independent LFSR sample into an occasional market event.
// Five high bits provide a 1-in-32 event trigger.  The low two bits select
// the event type, keeping the mapping deterministic and synthesizable.
module market_events(
    input wire [7:0] random_value,
    output reg [2:0] event_request
    );

    localparam [2:0] EVENT_NONE = 3'd0;
    localparam [2:0] EVENT_RALLY = 3'd1;
    localparam [2:0] EVENT_SELL_OFF = 3'd2;
    localparam [2:0] EVENT_CRASH = 3'd3;

    always @(*) begin
        event_request = EVENT_NONE;
        if (random_value[7:3] == 5'd0) begin
            case (random_value[1:0])
                2'b00: event_request = EVENT_RALLY;
                2'b01: event_request = EVENT_SELL_OFF;
                default: event_request = EVENT_CRASH;
            endcase
        end
    end

endmodule
