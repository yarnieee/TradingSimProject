
`timescale 1ns / 1ps

// Generate one stock's daily value and maintain its recent history.
//
// The seed file contains records in chronological order.  Each record is
// packed as {date[31:0], close_in_cents[15:0], volume[31:0]}.  The records are
// loaded into the three rotating buffers before ready is asserted.
//
// The market state is used as a small directional bias on the random value:
// bear shifts the random value upward, bull shifts it downward, and crash
// applies a larger bearish shift.  Normal leaves the random value unchanged.
module stock #(
    parameter integer BUFFER_DEPTH = 1800,
    parameter integer VOLATILITY = 10,
    parameter SEED_FILE = "AMD_seed.mem"
    )(
    input wire                          clk,
    input wire                          rst,
    input wire                          day_tick,
    input wire [1:0]                    market_state,
    input wire [7:0]                    normalized_random,
    output reg                          ready,
    output reg [15:0]                   current_close,
    output reg [31:0]                   current_volume,
    output reg [31:0]                   current_date,
    output wire [(BUFFER_DEPTH*16)-1:0] close_history,
    output wire [(BUFFER_DEPTH*32)-1:0] volume_history,
    output wire [(BUFFER_DEPTH*32)-1:0] date_history
    );

    localparam integer RECORD_WIDTH = 80;
    localparam integer INDEX_WIDTH = (BUFFER_DEPTH <= 1) ? 1 : $clog2(BUFFER_DEPTH);

    // The generated memory files are derived from AMD.csv and MCD.csv.
    reg [RECORD_WIDTH-1:0] seed_memory [0:BUFFER_DEPTH-1];
    reg [INDEX_WIDTH-1:0] seed_index;

    initial begin
        $readmemh(SEED_FILE, seed_memory);
    end

    wire [31:0] seed_date;
    wire [15:0] seed_close;
    wire [31:0] seed_volume;

    assign seed_date = seed_memory[seed_index][79:48];
    assign seed_close = seed_memory[seed_index][47:32];
    assign seed_volume = seed_memory[seed_index][31:0];

    function [7:0] adjust_random_for_market;
        input [7:0] random_value;
        input [1:0] state_value;
        integer adjusted_value;
        begin
            adjusted_value = random_value;
            case (state_value)
                2'b00: adjusted_value = random_value + 10; // bear
                2'b10: adjusted_value = random_value - 10; // bull
                2'b11: adjusted_value = random_value + 30; // crash
                default: adjusted_value = random_value;     // normal
            endcase

            if (adjusted_value < 0) begin
                adjusted_value = 0;
            end else if (adjusted_value > 100) begin
                adjusted_value = 100;
            end

            adjust_random_for_market = adjusted_value;
        end
    endfunction

    function [15:0] calculate_next_close;
        input [15:0] previous_close;
        input [7:0] random_value;
        input [1:0] state_value;
        integer adjusted_random;
        integer random_offset;
        integer stable_term;
        integer random_term;
        integer result;
        begin
            adjusted_random = adjust_random_for_market(random_value, state_value);
            random_offset = 50 - adjusted_random;

            // The random term is divided by 100 a second time so that the
            // normalized value produces a percentage-scale perturbation.
            stable_term = previous_close * (100 - VOLATILITY) / 100;
            random_term = (previous_close * VOLATILITY / 100)
                * random_offset / 100;
            result = stable_term + random_term;

            if (result < 1) begin
                result = 1;
            end else if (result > 65535) begin
                result = 65535;
            end

            calculate_next_close = result;
        end
    endfunction

    function [31:0] next_calendar_date;
        input [31:0] date_value;
        integer year_value;
        integer month_value;
        integer day_value;
        integer month_end;
        begin
            year_value = date_value / 10000;
            month_value = (date_value / 100) % 100;
            day_value = date_value % 100;

            if ((month_value == 2)
                && ((year_value % 400 == 0)
                || ((year_value % 4 == 0) && (year_value % 100 != 0)))) begin
                month_end = 29;
            end else begin
                case (month_value)
                    4, 6, 9, 11: month_end = 30;
                    default: month_end = 31;
                endcase
                if (month_value == 2) begin
                    month_end = 28;
                end
            end

            day_value = day_value + 1;
            if (day_value > month_end) begin
                day_value = 1;
                month_value = month_value + 1;
                if (month_value > 12) begin
                    month_value = 1;
                    year_value = year_value + 1;
                end
            end

            next_calendar_date = year_value * 10000
                + month_value * 100 + day_value;
        end
    endfunction

    // Zeller's congruence: 0 = Saturday, 1 = Sunday.
    function integer weekday_for_date;
        input [31:0] date_value;
        integer year_value;
        integer month_value;
        integer day_value;
        integer adjusted_year;
        integer adjusted_month;
        begin
            year_value = date_value / 10000;
            month_value = (date_value / 100) % 100;
            day_value = date_value % 100;
            adjusted_year = year_value;
            adjusted_month = month_value;

            if (adjusted_month < 3) begin
                adjusted_year = adjusted_year - 1;
                adjusted_month = adjusted_month + 12;
            end

            weekday_for_date = (day_value
                + (13 * (adjusted_month + 1)) / 5
                + adjusted_year + adjusted_year / 4
                - adjusted_year / 100 + adjusted_year / 400) % 7;
        end
    endfunction

    function [31:0] next_trading_date;
        input [31:0] date_value;
        reg [31:0] candidate_date;
        begin
            candidate_date = next_calendar_date(date_value);
            if ((weekday_for_date(candidate_date) == 0)
                || (weekday_for_date(candidate_date) == 1)) begin
                candidate_date = next_calendar_date(candidate_date);
            end
            if ((weekday_for_date(candidate_date) == 0)
                || (weekday_for_date(candidate_date) == 1)) begin
                candidate_date = next_calendar_date(candidate_date);
            end
            next_trading_date = candidate_date;
        end
    endfunction

    wire [15:0] next_close;
    wire [31:0] next_date;
    assign next_close = calculate_next_close(current_close,
        normalized_random, market_state);
    assign next_date = next_trading_date(current_date);

    wire buffer_write;
    wire [15:0] buffer_close;
    wire [31:0] buffer_volume;
    wire [31:0] buffer_date;

    assign buffer_write = !ready || day_tick;
    assign buffer_close = ready ? next_close : seed_close;
    assign buffer_volume = ready ? current_volume : seed_volume;
    assign buffer_date = ready ? next_date : seed_date;

    last_x_storage #(
        .X(BUFFER_DEPTH),
        .WIDTH(16)
        ) close_storage_inst (
        .clk(clk),
        .rst(rst),
        .en(buffer_write),
        .data_in(buffer_close),
        .storage_out(close_history)
        );

    last_x_storage #(
        .X(BUFFER_DEPTH),
        .WIDTH(32)
        ) volume_storage_inst (
        .clk(clk),
        .rst(rst),
        .en(buffer_write),
        .data_in(buffer_volume),
        .storage_out(volume_history)
        );

    last_x_storage #(
        .X(BUFFER_DEPTH),
        .WIDTH(32)
        ) date_storage_inst (
        .clk(clk),
        .rst(rst),
        .en(buffer_write),
        .data_in(buffer_date),
        .storage_out(date_history)
        );

    always @(posedge clk) begin
        if (rst) begin
            ready <= 1'b0;
            seed_index <= {INDEX_WIDTH{1'b0}};
            current_close <= 16'b0;
            current_volume <= 32'b0;
            current_date <= 32'b0;
        end else if (!ready) begin
            if (seed_index == BUFFER_DEPTH-1) begin
                ready <= 1'b1;
                current_close <= seed_close;
                current_volume <= seed_volume;
                current_date <= seed_date;
            end else begin
                seed_index <= seed_index + 1'b1;
            end
        end else if (day_tick) begin
            current_close <= next_close;
            current_date <= next_date;
        end
    end

endmodule
