`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// D_display_top: Matthew's complete display component.
//
//   JB (right OLED): the game screens (OLED_Renderer); title artwork on the title screen
//   JA (left OLED):  the page given on left_pixel (Douglas's order ticket);
//                    title artwork on the title screen
//
// Every number on the right OLED comes from display_numbers as decimal digits.
module D_display_top #(
    parameter DEBOUNCE_CTR    = 32'd1_999_999
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        btnU,
    input  wire        btnD,
    input  wire        btnL,
    input  wire        btnR,
    input  wire        btnC,
    input  wire        final_day_reached,
    input  wire [31:0] time_remaining,
    input  wire        order_fill,
    input  wire        order_reject,
    input  wire [2:0]  order_reject_code,
    // The page shown on JA (left OLED) after the title screen.
    input  wire [15:0] left_pixel,
    output wire [6:0]  left_x,
    output wire [5:0]  left_y,
    // Game and order interface.
    output wire [3:0]  screen_state,
    output wire [13:0] quantity,
    output wire [1:0]  sel_stock,
    input  wire [15:0] price0,
    input  wire [15:0] price1,
    input  wire [15:0] price2,
    input  wire [15:0] price3,
    input  wire [479:0] stock0_samples_30,
    input  wire [479:0] stock1_samples_30,
    input  wire [479:0] stock2_samples_30,
    input  wire [479:0] stock3_samples_30,
    input  wire [31:0] portfolio_cash,
    input  wire [9:0]  portfolio_pos0,
    input  wire [9:0]  portfolio_pos1,
    input  wire [9:0]  portfolio_pos2,
    input  wire [9:0]  portfolio_pos3,
    input  wire        stock_ready0,
    input  wire        stock_ready1,
    input  wire        stock_ready2,
    input  wire        stock_ready3,
    input  wire [31:0] portfolio_value,
    input  wire [31:0] portfolio_cb0,
    input  wire [31:0] portfolio_cb1,
    input  wire [31:0] portfolio_cb2,
    input  wire [31:0] portfolio_cb3,
    input  wire [959:0] portfolio_samples_30,
    output wire        ord_req,
    output wire        ord_side,
    output wire [2:0]  trade_result_code,
    output wire        trade_result_success,
    output wire [1:0]  game_state,
    // Board outputs.
    output wire [7:0]  JA,
    output wire [7:0]  JB,
    output wire [3:0]  an,
    output wire [7:0]  seg
);
    // ================================================================ buttons
    wire btnU_db, btnD_db, btnL_db, btnR_db, btnC_db;

    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_U (
        .clk(clk), .btn(btnU), .debounced(btnU_db)
    );
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_D (
        .clk(clk), .btn(btnD), .debounced(btnD_db)
    );
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_L (
        .clk(clk), .btn(btnL), .debounced(btnL_db)
    );
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_R (
        .clk(clk), .btn(btnR), .debounced(btnR_db)
    );
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_C (
        .clk(clk), .btn(btnC), .debounced(btnC_db)
    );

    reg [4:0] btn_prev;
    always @(posedge clk) begin
        if (rst)
            btn_prev <= 5'd0;
        else
            btn_prev <= {btnC_db, btnR_db, btnL_db, btnD_db, btnU_db};
    end

    wire btnU_p = btnU_db & ~btn_prev[0];
    wire btnD_p = btnD_db & ~btn_prev[1];
    wire btnL_p = btnL_db & ~btn_prev[2];
    wire btnR_p = btnR_db & ~btn_prev[3];
    wire btnC_p = btnC_db & ~btn_prev[4];

    // ================================================================ game FSM
    wire [2:0] selected_stock;
    wire [1:0] quantity_cursor;
    wire [3:0] menu_selection;
    wire       trade_side;
    reg        order_valid;
    reg  [2:0] validation_code;

    game_fsm game_fsm_inst (
        .clk(clk),
        .rst(rst),
        .btnU(btnU_p),
        .btnD(btnD_p),
        .btnL(btnL_p),
        .btnR(btnR_p),
        .btnC(btnC_p),
        .final_day_reached(final_day_reached),
        .order_fill(order_fill),
        .order_reject(order_reject),
        .order_reject_code(order_reject_code),
        .order_valid(order_valid),
        .validation_code(validation_code),
        .screen_state(screen_state),
        .quantity(quantity),
        .selected_stock(selected_stock),
        .quantity_cursor(quantity_cursor),
        .menu_selection(menu_selection),
        .trade_result_code(trade_result_code),
        .trade_result_success(trade_result_success),
        .trade_side(trade_side)
    );

    assign sel_stock = selected_stock[1:0];

    // The chart and selected-stock price follow the same four-stock index
    // that is sent to the order engine. This keeps the specific-stock screen
    // and its live graph on the same stock after the model expansion.
    wire [15:0] selected_price = (selected_stock == 3'd0) ? price0 :
                                 (selected_stock == 3'd1) ? price1 :
                                 (selected_stock == 3'd2) ? price2 : price3;
    wire [479:0] selected_samples_30 = (selected_stock == 3'd0) ?
                                       stock0_samples_30 :
                                       (selected_stock == 3'd1) ?
                                       stock1_samples_30 :
                                       (selected_stock == 3'd2) ?
                                       stock2_samples_30 : stock3_samples_30;

    wire selected_ready = (selected_stock == 3'd0) ? stock_ready0 :
                          (selected_stock == 3'd1) ? stock_ready1 :
                          (selected_stock == 3'd2) ? stock_ready2 : stock_ready3;
    wire [9:0] selected_position = (selected_stock == 3'd0) ? portfolio_pos0 :
                                   (selected_stock == 3'd1) ? portfolio_pos1 :
                                   (selected_stock == 3'd2) ? portfolio_pos2 : portfolio_pos3;
    // the selected stock's price 30 days ago (oldest of the 30 samples)
    wire [15:0] selected_reference_price = selected_samples_30[15:0];
    wire [16:0] selected_ask_full = {1'b0, selected_price} + 17'd5;
    wire [15:0] selected_ask = selected_ask_full[16] ? 16'hFFFF : selected_ask_full[15:0];
    wire [31:0] buy_notional = {16'd0, selected_ask} * {18'd0, quantity};
    wire [32:0] buy_total = {1'b0, buy_notional} + 33'd100;

    // Validate before the order-review screen can submit to B_order_top.
    // The ask and fee match B_order_top's market-order parameters.
    always @(*) begin
        order_valid = 1'b1;
        validation_code = `RJ_NONE;
        if (!selected_ready) begin
            order_valid = 1'b0;
            validation_code = `RJ_NOT_LIVE;
        end else if ((quantity == 14'd0) || (quantity > 14'd255)) begin
            order_valid = 1'b0;
            validation_code = `RJ_BAD_QTY;
        end else if (!trade_side && (buy_total > {1'b0, portfolio_cash})) begin
            order_valid = 1'b0;
            validation_code = `RJ_NO_CASH;
        end else if (trade_side && (quantity > selected_position)) begin
            order_valid = 1'b0;
            validation_code = `RJ_NO_POS;
        end
    end

    quantity_7seg quantity_7seg_inst (
        .clk(clk),
        .rst(rst),
        .quantity(quantity),
        .screen_state(screen_state),
        .quantity_cursor(quantity_cursor),
        .an(an),
        .seg(seg)
    );

    // ================================================================ order outputs
    reg [3:0] state_d;
    always @(posedge clk) begin
        if (rst)
            state_d <= `UI_TITLE;
        else
            state_d <= screen_state;
    end

    // Generate a one-clock order request when the review screen is submitted.
    assign ord_req  = (screen_state == `UI_ORDER_RESULT) &&
                      (state_d == `UI_ORDER_REVIEW);
    assign ord_side = trade_side;

    assign game_state = ((screen_state == `UI_TITLE) ||
                         (screen_state == `UI_GAME_END)) ?
                        2'd0 : 2'd1;

    // ================================================================ OLED clocks
    wire clk_6_25MHz;
    slower_clk #(32'd7) clk_6_25MHz_inst (clk, clk_6_25MHz);

    // ================================================================ right OLED (JB)
    wire [12:0] pixel_index_R;
    wire [15:0] pixel_data_game_R;
    wire [15:0] title_pixel_R;
    wire [15:0] pixel_data_R;
    wire        frame_begin_R;
    wire        sending_pixels_R;
    wire        sample_pixel_R;

    // ================================================================ numbers on the right OLED
    wire [`DN_N*32-1:0] numbers_bcd;
    wire [`DN_N-1:0]    numbers_neg;
    display_numbers display_numbers_inst (
        .clk(clk), .rst(rst),
        .cash(portfolio_cash), .portfolio_value(portfolio_value),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .pos0(portfolio_pos0), .pos1(portfolio_pos1),
        .pos2(portfolio_pos2), .pos3(portfolio_pos3),
        .cb0(portfolio_cb0), .cb1(portfolio_cb1),
        .cb2(portfolio_cb2), .cb3(portfolio_cb3),
        .sel_stock(selected_stock[1:0]), .sel_ref_price(selected_reference_price),
        .quantity(quantity), .days_left(time_remaining), .sell(trade_side),
        .bcd(numbers_bcd), .neg(numbers_neg)
    );

    // each stock against its price 30 days ago (oldest sample), for green/red
    wire [3:0] stock_up = {price3 >= stock3_samples_30[15:0], price2 >= stock2_samples_30[15:0],
                           price1 >= stock1_samples_30[15:0], price0 >= stock0_samples_30[15:0]};

    OLED_Renderer oled_renderer_R (
        .pixel_index(pixel_index_R),
        .screen_state(screen_state),
        .selected_stock(selected_stock),
        .menu_selection(menu_selection),
        .quantity_cursor(quantity_cursor),
        .trade_side(trade_side),
        .trade_result_success(trade_result_success),
        .trade_result_code(trade_result_code),
        .stock_samples(selected_samples_30),
        .numbers_bcd(numbers_bcd),
        .numbers_neg(numbers_neg),
        .stock_up(stock_up),
        .pixel_data(pixel_data_game_R)
    );

    oled_display oled_R (
        .clk(clk_6_25MHz),
        .reset(rst),
        .pixel_data(pixel_data_R),
        .frame_begin(frame_begin_R),
        .sending_pixels(sending_pixels_R),
        .sample_pixel(sample_pixel_R),
        .pixel_index(pixel_index_R),
        .cs(JB[0]),
        .sdin(JB[1]),
        .sclk(JB[3]),
        .d_cn(JB[4]),
        .resn(JB[5]),
        .vccen(JB[6]),
        .pmoden(JB[7])
    );

    assign JB[2] = 1'b0;

    // ================================================================ left OLED (JA)
    wire [12:0] pixel_index_L;
    wire [15:0] title_pixel_L;
    wire [15:0] pixel_data_L;
    wire [6:0]  title_display_x_L;
    wire [5:0]  title_display_y_L;
    wire [12:0] title_pixel_index_L;
    wire        frame_begin_L;
    wire        sending_pixels_L;
    wire        sample_pixel_L;

    assign left_x = pixel_index_L % 96;
    assign left_y = pixel_index_L / 96;
    // JA sits upside down: read the title artwork rotated 180 degrees
    assign title_display_x_L = 7'd95 - (pixel_index_L % 96);
    assign title_display_y_L = 6'd63 - (pixel_index_L / 96);
    assign title_pixel_index_L = (title_display_y_L * 13'd96) + title_display_x_L;

    title_art_renderer title_art_renderer_inst (
        .pixel_index_R(pixel_index_R),
        .pixel_index_L(title_pixel_index_L),
        .pixel_data_R(title_pixel_R),
        .pixel_data_L(title_pixel_L)
    );

    assign pixel_data_R = (screen_state == `UI_TITLE) ?
                          title_pixel_R : pixel_data_game_R;
    assign pixel_data_L = (screen_state == `UI_TITLE) ?
                          title_pixel_L : left_pixel;

    oled_display oled_L (
        .clk(clk_6_25MHz),
        .reset(rst),
        .pixel_data(pixel_data_L),
        .frame_begin(frame_begin_L),
        .sending_pixels(sending_pixels_L),
        .sample_pixel(sample_pixel_L),
        .pixel_index(pixel_index_L),
        .cs(JA[0]),
        .sdin(JA[1]),
        .sclk(JA[3]),
        .d_cn(JA[4]),
        .resn(JA[5]),
        .vccen(JA[6]),
        .pmoden(JA[7])
    );

    assign JA[2] = 1'b0;
endmodule

`default_nettype wire
