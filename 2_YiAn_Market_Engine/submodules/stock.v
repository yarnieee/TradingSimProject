
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

    // The repository's packed seed files provide the four stock histories
    // (AMD, MCD, NVDA, and GME) consumed by the four A_top channels.
    (* rom_style = "block" *) reg [RECORD_WIDTH-1:0] seed_memory [0:BUFFER_DEPTH-1];
    reg [INDEX_WIDTH-1:0] seed_index;

    initial begin
        $readmemh(SEED_FILE, seed_memory);
    end

    // The seed records are read on the clock so they sit in block RAM rather
    // than logic: seed_record is record seed_index one clock later.
    // seed_valid: seed_record holds a record still to be loaded;
    // seed_last: it is the last one.
    reg [RECORD_WIDTH-1:0] seed_record;
    reg seed_valid;
    reg seed_last;

    always @(posedge clk) begin
        seed_record <= seed_memory[seed_index];
    end

    wire [31:0] seed_date;
    wire [15:0] seed_close;
    wire [31:0] seed_volume;

    assign seed_date = seed_record[79:48];
    assign seed_close = seed_record[47:32];
    assign seed_volume = seed_record[31:0];

    function [7:0] adjust_random_for_market;
        input [7:0] random_value;
        input [1:0] state_value;
        // Raw random input plus regime bias ranges from -10 to 285.
        reg signed [9:0] random_integer;
        reg signed [9:0] adjusted_value;
        begin
            // Convert the unsigned input before subtracting the bull bias.
            // This prevents an 8-bit underflow when random_value is below 10.
            random_integer = $signed({2'b00, random_value});
            adjusted_value = random_integer;
            case (state_value)
                2'b00: adjusted_value = random_integer + 10'sd10; // bear
                2'b10: adjusted_value = random_integer - 10'sd10; // bull
                2'b11: adjusted_value = random_integer + 10'sd30; // crash
                default: adjusted_value = random_integer;     // normal
            endcase

            if (adjusted_value < 10'sd0) begin
                adjusted_value = 10'sd0;
            end else if (adjusted_value > 10'sd100) begin
                adjusted_value = 10'sd100;
            end

            adjust_random_for_market = adjusted_value;
        end
    endfunction

    function [15:0] calculate_next_close;
        input [15:0] previous_close;
        input [7:0] random_value;
        input [1:0] state_value;
        reg [7:0] adjusted_random;
        reg signed [7:0] random_offset;
        reg signed [7:0] bounded_volatility;
        reg signed [13:0] weighted_offset;
        reg signed [7:0] daily_delta_percent;
        reg [7:0] price_multiplier;
        reg [23:0] scaled_price;
        reg [23:0] result;
        begin
            adjusted_random = adjust_random_for_market(random_value, state_value);
            random_offset = 8'sd50 - $signed(adjusted_random);

            // Keep the parameter in a safe range even if a future instance
            // supplies an invalid value.  The old expression always applied
            // a negative stable term, which caused a one-sided price drift.
            // Clamp the integer parameter BEFORE narrowing it: e.g. 256
            // must clamp to 100 rather than wrap to zero in eight bits.
            bounded_volatility = (VOLATILITY < 0) ? 8'sd0 :
                                 (VOLATILITY > 100) ? 8'sd100 : VOLATILITY;

            // random_offset is -50..+50.  Scale it to approximately
            // -VOLATILITY..+VOLATILITY percent around the previous close.
            // All operands are explicitly signed before the multiplication.
            // offset [-50,50] * volatility [0,100] fits signed 14 bits.
            // Signed division preserves truncation toward zero, including
            // negative daily changes. Multiplier is always in [0,200].
            weighted_offset = random_offset * bounded_volatility;
            daily_delta_percent = weighted_offset / 14'sd50;
            price_multiplier = 9'sd100 + daily_delta_percent;
            // 65535 * 200 = 13,107,000 < 2^24. The old signed 64-bit
            // divide synthesized a wide combinational cone in each stock.
            // Here both operands are nonnegative; unsigned /100 is EXACT.
            scaled_price = previous_close * price_multiplier;
            result = scaled_price / 24'd100;

            if (result < 24'd1) begin
                result = 24'd1;
            end else if (result > 24'd65534) begin
                // 16'hFFFF is reserved as an invalid/saturated value by the
                // market and order-engine testbenches.
                result = 24'd65534;
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

    // Reference model of the next close, used by the testbenches only.
    // Nothing in the hardware reads it, so synthesis removes it.
    wire [15:0] next_close;
    assign next_close = calculate_next_close(current_close,
        normalized_random, market_state);

    // ------------------------------------------------------------ next trading day
    // The next close and date are worked out one small step per clock after
    // day_tick (30 clocks, 0.3 us; a trading day lasts seconds), so no long
    // chain of arithmetic has to finish inside one 10 ns clock.  The result is
    // the same as calculate_next_close.  Close, date, calendar and history all
    // change together on the P_COMMIT clock, and every stock takes the same
    // number of clocks, so the four stocks still move on the same clock.
    localparam integer VOL = (VOLATILITY < 0) ? 0 :
                             (VOLATILITY > 100) ? 100 : VOLATILITY;

    localparam [2:0] P_IDLE   = 3'd0,
                     P_OFFSET = 3'd1,   // (50 - adjusted random) * VOL
                     P_DELTA  = 3'd2,   // multiplier = 100 + offset / 50
                     P_SCALE  = 3'd3,   // previous close * multiplier
                     P_DIV    = 3'd4,   // / 100, one quotient bit a clock (24 clocks)
                     P_CLAMP  = 3'd5,   // 1..65534; year part of the date
                     P_DATE   = 3'd6,   // YYYYMMDD
                     P_COMMIT = 3'd7;   // new close, date, calendar and history

    reg [2:0]         p_state;
    reg [7:0]         p_rand;           // random value and market state seen on day_tick
    reg [1:0]         p_mstate;
    reg [15:0]        p_prev;           // close before day_tick
    reg signed [13:0] p_offset;         // -5000..5000
    reg [7:0]         p_mult;           // 0..200
    reg [23:0]        p_num;            // close * multiplier, shifted into the quotient
    reg [6:0]         p_rem;            // divider remainder, below 100
    reg [4:0]         p_bit;            // quotient bits still to do
    reg [15:0]        p_close;
    reg [31:0]        p_year_part;      // year * 10000
    reg [31:0]        p_date;
    reg [1:0]         p_days;           // calendar days still to add (3 on a Friday)
    reg [15:0]        p_year;           // calendar for the new day, one day per clock
    reg [3:0]         p_month;
    reg [5:0]         p_day;
    reg [2:0]         p_weekday;

    wire        p_commit = (p_state == P_COMMIT);

    // / 50 of |offset| <= 5000 as * 5243 >> 18 (exact for 0..5000);
    // the sign goes back on after, so the result rounds toward zero
    wire [12:0] p_offset_abs = p_offset[13] ? -p_offset : p_offset;
    wire [25:0] p_pct_full   = p_offset_abs * 13'd5243;
    wire [6:0]  p_pct        = p_pct_full[24:18];

    // one restoring-division step by 100
    wire [7:0]  p_rem_shift  = {p_rem, p_num[23]};
    wire        p_fits       = (p_rem_shift >= 8'd100);

    wire [25:0] p_next_cal   = increment_calendar_day(p_year, p_month, p_day);

    always @(posedge clk) begin
        if (rst) begin
            p_state     <= P_IDLE;
            p_rand      <= 8'd0;
            p_mstate    <= 2'd0;
            p_prev      <= 16'd0;
            p_offset    <= 14'sd0;
            p_mult      <= 8'd0;
            p_num       <= 24'd0;
            p_rem       <= 7'd0;
            p_bit       <= 5'd0;
            p_close     <= 16'd0;
            p_year_part <= 32'd0;
            p_date      <= 32'd0;
            p_days      <= 2'd0;
            p_year      <= INITIAL_YEAR;
            p_month     <= INITIAL_MONTH;
            p_day       <= INITIAL_DAY;
            p_weekday   <= INITIAL_WEEKDAY;
        end else begin
            // calendar: one day per clock while the price is worked out
            if (p_days != 2'd0) begin
                {p_year, p_month, p_day} <= p_next_cal;
                p_weekday <= (p_weekday == 3'd6) ? 3'd0 : p_weekday + 1'b1;
                p_days    <= p_days - 1'b1;
            end

            case (p_state)
                P_IDLE: if (ready && day_tick) begin
                    p_rand    <= normalized_random;
                    p_mstate  <= market_state;
                    p_prev    <= current_close;
                    p_year    <= calendar_year;
                    p_month   <= calendar_month;
                    p_day     <= calendar_day;
                    p_weekday <= calendar_weekday;
                    // Friday advances three calendar days to Monday
                    p_days    <= (calendar_weekday == 3'd6) ? 2'd3 : 2'd1;
                    p_state   <= P_OFFSET;
                end
                P_OFFSET: begin
                    p_offset <= (8'sd50 - $signed({1'b0, adjust_random_for_market(p_rand, p_mstate)}))
                                * VOL;
                    p_state  <= P_DELTA;
                end
                P_DELTA: begin
                    p_mult  <= p_offset[13] ? 8'd100 - p_pct : 8'd100 + p_pct;
                    p_state <= P_SCALE;
                end
                P_SCALE: begin
                    p_num   <= p_prev * p_mult;
                    p_rem   <= 7'd0;
                    p_bit   <= 5'd23;
                    p_state <= P_DIV;
                end
                P_DIV: begin
                    p_rem <= p_fits ? p_rem_shift - 8'd100 : p_rem_shift[6:0];
                    p_num <= {p_num[22:0], p_fits};
                    p_bit <= p_bit - 1'b1;
                    if (p_bit == 5'd0)
                        p_state <= P_CLAMP;
                end
                P_CLAMP: begin
                    // 16'hFFFF is reserved as an invalid/saturated value by the
                    // market and order-engine testbenches.
                    p_close     <= (p_num < 24'd1)     ? 16'd1 :
                                   (p_num > 24'd65534) ? 16'd65534 : p_num[15:0];
                    p_year_part <= p_year * 32'd10000;
                    p_state     <= P_DATE;
                end
                P_DATE: begin
                    p_date  <= p_year_part + (p_month * 32'd100) + p_day;
                    p_state <= P_COMMIT;
                end
                default: p_state <= P_IDLE;   // P_COMMIT: the block below takes the results
            endcase
        end
    end

    wire buffer_write;
    wire [15:0] buffer_close;
    wire [31:0] buffer_volume;
    wire [31:0] buffer_date;

    assign buffer_write = (!ready && seed_valid) || p_commit;
    assign buffer_close = ready ? p_close : seed_close;
    assign buffer_volume = ready ? current_volume : seed_volume;
    assign buffer_date = ready ? p_date : seed_date;

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
            seed_valid <= 1'b0;
            seed_last <= 1'b0;
            current_close <= 16'b0;
            current_volume <= 32'b0;
            current_date <= 32'b0;
            calendar_year <= INITIAL_YEAR;
            calendar_month <= INITIAL_MONTH;
            calendar_day <= INITIAL_DAY;
            calendar_weekday <= INITIAL_WEEKDAY;
        end else if (!ready) begin
            seed_valid <= 1'b1;
            seed_last <= (seed_index == BUFFER_DEPTH-1);
            if (seed_index != BUFFER_DEPTH-1)
                seed_index <= seed_index + 1'b1;
            if (seed_valid && seed_last) begin
                ready <= 1'b1;
                current_close <= seed_close;
                current_volume <= seed_volume;
                current_date <= seed_date;
                calendar_year <= INITIAL_YEAR;
                calendar_month <= INITIAL_MONTH;
                calendar_day <= INITIAL_DAY;
                calendar_weekday <= INITIAL_WEEKDAY;
            end
        end else if (p_commit) begin
            current_close <= p_close;
            current_date <= p_date;
            calendar_year <= p_year;
            calendar_month <= p_month;
            calendar_day <= p_day;
            calendar_weekday <= p_weekday;
        end
    end

endmodule
