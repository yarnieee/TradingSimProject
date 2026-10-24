
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
// VOLATILITY is the approximate maximum percentage change per trading day.
module stock #(
    parameter integer BUFFER_DEPTH = 180,
    parameter integer VOLATILITY = 10,
    parameter integer INITIAL_YEAR = 2025,
    parameter integer INITIAL_MONTH = 12,
    parameter integer INITIAL_DAY = 19,
    parameter integer INITIAL_WEEKDAY = 6,
    parameter SEED_FILE = "storage/data/AMD_seed.mem"
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
        integer random_integer;
        integer adjusted_value;
        begin
            // Convert the unsigned input before subtracting the bull bias.
            // This prevents an 8-bit underflow when random_value is below 10.
            random_integer = {1'b0, random_value};
            adjusted_value = random_integer;
            case (state_value)
                2'b00: adjusted_value = random_integer + 10; // bear
                2'b10: adjusted_value = random_integer - 10; // bull
                2'b11: adjusted_value = random_integer + 30; // crash
                default: adjusted_value = random_integer;     // normal
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
        integer bounded_volatility;
        integer daily_delta_percent;
        integer price_multiplier;
        integer result;
        reg signed [31:0] signed_previous_close;
        reg signed [63:0] scaled_price;
        begin
            adjusted_random = adjust_random_for_market(random_value, state_value);
            random_offset = 50 - adjusted_random;

            // Keep the parameter in a safe range even if a future instance
            // supplies an invalid value.  The old expression always applied
            // a negative stable term, which caused a one-sided price drift.
            bounded_volatility = VOLATILITY;
            if (bounded_volatility < 0)
                bounded_volatility = 0;
            else if (bounded_volatility > 100)
                bounded_volatility = 100;

            // random_offset is -50..+50.  Scale it to approximately
            // -VOLATILITY..+VOLATILITY percent around the previous close.
            // All operands are explicitly signed before the multiplication.
            daily_delta_percent = (random_offset * bounded_volatility) / 50;
            price_multiplier = 100 + daily_delta_percent;
            signed_previous_close = {16'd0, previous_close};
            scaled_price = signed_previous_close * price_multiplier;
            result = scaled_price / 100;

            if (result < 1) begin
                result = 1;
            end else if (result > 65534) begin
                // 16'hFFFF is reserved as an invalid/saturated value by the
                // market and order-engine testbenches.
                result = 65534;
            end

            calculate_next_close = result;
        end
    endfunction

    // Calendar components are tracked directly rather than repeatedly
    // extracting YYYY/MM/DD with / and %.  Weekday encoding is Zeller-style:
    // 0 = Saturday, 1 = Sunday, 2 = Monday, ..., 6 = Friday.
    reg [15:0] calendar_year;
    reg [3:0]  calendar_month;
    reg [5:0]  calendar_day;
    reg [2:0]  calendar_weekday;

    function integer month_length;
        input [15:0] year_value;
        input [3:0] month_value;
        begin
            case (month_value)
                2: begin
                    // The simulation runs in the current century.  The
                    // low two year bits are sufficient for leap years here
                    // and avoid a binary divide/modulo cone.
                    month_length = (year_value[1:0] == 2'b00) ? 29 : 28;
                end
                4, 6, 9, 11: month_length = 30;
                default: month_length = 31;
            endcase
        end
    endfunction

    function [25:0] increment_calendar_day;
        input [15:0] year_value;
        input [3:0]  month_value;
        input [5:0]  day_value;
        reg [15:0] next_year_value;
        reg [3:0]  next_month_value;
        reg [5:0]  next_day_value;
        begin
            next_year_value = year_value;
            next_month_value = month_value;
            next_day_value = day_value + 1'b1;

            if (next_day_value > month_length(year_value, month_value)) begin
                next_day_value = 1;
                if (month_value == 12) begin
                    next_month_value = 1;
                    next_year_value = year_value + 1'b1;
                end else begin
                    next_month_value = month_value + 1'b1;
                end
            end

            increment_calendar_day = {
                next_year_value, next_month_value, next_day_value
            };
        end
    endfunction

    reg [25:0] next_calendar_parts;
    reg [2:0]  next_calendar_weekday;
    reg [31:0] next_date;
    integer calendar_step;
    integer calendar_steps;

    always @(*) begin
        next_calendar_parts = {calendar_year, calendar_month, calendar_day};
        next_calendar_weekday = calendar_weekday;

        // Friday advances three calendar days to Monday; every other
        // trading day advances one calendar day.
        if (calendar_weekday == 3'd6)
            calendar_steps = 3;
        else
            calendar_steps = 1;

        for (calendar_step = 0; calendar_step < 3; calendar_step = calendar_step + 1) begin
            if (calendar_step < calendar_steps) begin
                next_calendar_parts = increment_calendar_day(
                    next_calendar_parts[25:10],
                    next_calendar_parts[9:6],
                    next_calendar_parts[5:0]
                );
                if (next_calendar_weekday == 3'd6)
                    next_calendar_weekday = 3'd0;
                else
                    next_calendar_weekday = next_calendar_weekday + 1'b1;
            end
        end

        // Convert the tracked components back to the existing YYYYMMDD
        // output format.  These constant multiplications synthesize to
        // shifts/adds; no variable divider is required.
        next_date = (next_calendar_parts[25:10] * 32'd10000)
            + (next_calendar_parts[9:6] * 32'd100)
            + next_calendar_parts[5:0];
    end

    wire [15:0] next_close;
    assign next_close = calculate_next_close(current_close,
        normalized_random, market_state);

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
            calendar_year <= INITIAL_YEAR;
            calendar_month <= INITIAL_MONTH;
            calendar_day <= INITIAL_DAY;
            calendar_weekday <= INITIAL_WEEKDAY;
        end else if (!ready) begin
            if (seed_index == BUFFER_DEPTH-1) begin
                ready <= 1'b1;
                current_close <= seed_close;
                current_volume <= seed_volume;
                current_date <= seed_date;
                calendar_year <= INITIAL_YEAR;
                calendar_month <= INITIAL_MONTH;
                calendar_day <= INITIAL_DAY;
                calendar_weekday <= INITIAL_WEEKDAY;
            end else begin
                seed_index <= seed_index + 1'b1;
            end
        end else if (day_tick) begin
            current_close <= next_close;
            current_date <= next_date;
            calendar_year <= next_calendar_parts[25:10];
            calendar_month <= next_calendar_parts[9:6];
            calendar_day <= next_calendar_parts[5:0];
            calendar_weekday <= next_calendar_weekday;
        end
    end

endmodule
