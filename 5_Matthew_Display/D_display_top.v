`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// D_display_top: Matthew's complete display component.
//
// SHOW_GAME_ON_JA = 1 reproduces the earlier two-game-screen behaviour:
//   JB: normal game screen
//   JA: the same game screen rotated 180 degrees, with live button indicators
//
// SHOW_GAME_ON_JA = 0 keeps the team-integration arrangement:
//   JB: game screen
//   JA: the external page supplied through left_pixel
module D_display_top #(
    parameter DEBOUNCE_CTR    = 32'd1_999_999,
    parameter SHOW_GAME_ON_JA = 1'b1
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        btnU,
    input  wire        btnD,
    input  wire        btnL,
    input  wire        btnR,
    input  wire        btnC,
    input  wire        final_day_reached,
    // External page for JA when SHOW_GAME_ON_JA == 0.
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
    input  wire [31:0] portfolio_value,
    input  wire [959:0] portfolio_samples_30,
    output wire        ord_req,
    output wire        ord_side,
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

    game_fsm game_fsm_inst (
        .clk(clk),
        .rst(rst),
        .btnU(btnU_p),
        .btnD(btnD_p),
        .btnL(btnL_p),
        .btnR(btnR_p),
        .btnC(btnC_p),
        .final_day_reached(final_day_reached),
        .screen_state(screen_state),
        .quantity(quantity),
        .selected_stock(selected_stock),
        .quantity_cursor(quantity_cursor),
        .menu_selection(menu_selection)
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
    localparam [3:0] S_TITLE    = 4'd0;
    localparam [3:0] S_BUY      = 4'd4;
    localparam [3:0] S_SELL     = 4'd5;
    localparam [3:0] S_CONFIRM  = 4'd7;
    localparam [3:0] S_GAME_END = 4'd8;

    reg [3:0] state_d;
    always @(posedge clk) begin
        if (rst)
            state_d <= S_TITLE;
        else
            state_d <= screen_state;
    end

    // Generate a one-clock order request when BUY/SELL confirmation is entered.
    assign ord_req  = (screen_state == S_CONFIRM) &&
                      ((state_d == S_BUY) || (state_d == S_SELL));
    assign ord_side = (state_d == S_SELL);

    assign game_state = ((screen_state == S_TITLE) ||
                         (screen_state == S_GAME_END)) ?
                        2'd0 : 2'd1;

    // ================================================================ OLED clocks
    wire clk_6_25MHz;
    slower_clk #(32'd7) clk_6_25MHz_inst (clk, clk_6_25MHz);

    // ================================================================ right OLED (JB)
    wire [12:0] pixel_index_R;
    wire [15:0] pixel_data_R;
    wire        frame_begin_R;
    wire        sending_pixels_R;
    wire        sample_pixel_R;

    OLED_Renderer oled_renderer_R (
        .pixel_index(pixel_index_R),
        .screen_state(screen_state),
        .selected_stock(selected_stock),
        .quantity(quantity),
        .menu_selection(menu_selection),
        .stock_samples(selected_samples_30),
        .portfolio_samples(portfolio_samples_30),
        .portfolio_cash(portfolio_cash),
        .portfolio_pos0(portfolio_pos0),
        .portfolio_pos1(portfolio_pos1),
        .portfolio_value(portfolio_value),
        .selected_price(selected_price),
        .pixel_data(pixel_data_R)
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
    wire [15:0] pixel_data_game_L;
    wire [15:0] pixel_data_L;
    wire        frame_begin_L;
    wire        sending_pixels_L;
    wire        sample_pixel_L;

    assign left_x = pixel_index_L % 96;
    assign left_y = pixel_index_L / 96;

    OLED_Button_Renderer oled_renderer_L (
        .pixel_index(pixel_index_L),
        .screen_state(screen_state),
        .selected_stock(selected_stock),
        .quantity(quantity),
        .menu_selection(menu_selection),
        .stock_samples(selected_samples_30),
        .portfolio_samples(portfolio_samples_30),
        .portfolio_cash(portfolio_cash),
        .portfolio_pos0(portfolio_pos0),
        .portfolio_pos1(portfolio_pos1),
        .portfolio_value(portfolio_value),
        .selected_price(selected_price),
        .btnU(btnU_db),
        .btnD(btnD_db),
        .btnL(btnL_db),
        .btnR(btnR_db),
        .btnC(btnC_db),
        .pixel_data(pixel_data_game_L)
    );

    assign pixel_data_L = SHOW_GAME_ON_JA ? pixel_data_game_L : left_pixel;

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
