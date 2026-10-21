`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// matthew_top: Matthew's part in one block. Buttons, game FSM, quantity on the
// 7-seg, and both OLEDs:
//   JB (right)  Matthew's game screens (OLED_Renderer)
//   JA (left)   whatever page comes in on left_pixel (now: Douglas's order ticket)
//
// game_fsm, quantity_7seg and OLED_Renderer are used as they are. The ORDER
// OUTPUTS section works out, from screen_state and the buttons, the signals the
// plan has game_fsm output (sel_stock, the order, game_state); it goes away
// once game_fsm outputs them itself.
module matthew_top #(
    parameter DEBOUNCE_CTR = 32'd1_999_999      // 20 ms
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        btnU,
    input  wire        btnD,
    input  wire        btnL,
    input  wire        btnR,
    input  wire        btnC,
    // left OLED: the page to draw, and the pixel being asked for
    input  wire [15:0] left_pixel,
    output wire [6:0]  left_x,
    output wire [5:0]  left_y,
    // game
    output wire [3:0]  screen_state,
    output wire [13:0] quantity,
    output reg  [1:0]  sel_stock,
    output wire        ord_req,         // one-cycle pulse: place the order
    output wire        ord_side,
    output wire [1:0]  game_state,
    // board
    output wire [7:0]  JA,
    output wire [7:0]  JB,
    output wire [3:0]  an,
    output wire [7:0]  seg
);
    // ================================================================ buttons
    wire btnU_db, btnD_db, btnL_db, btnR_db, btnC_db;
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_U (.clk(clk), .btn(btnU), .debounced(btnU_db));
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_D (.clk(clk), .btn(btnD), .debounced(btnD_db));
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_L (.clk(clk), .btn(btnL), .debounced(btnL_db));
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_R (.clk(clk), .btn(btnR), .debounced(btnR_db));
    debouncer #(.DEBOUNCE_CTR(DEBOUNCE_CTR)) debounce_C (.clk(clk), .btn(btnC), .debounced(btnC_db));

    reg [4:0] btn_prev;
    always @(posedge clk) begin
        if (rst) btn_prev <= 5'd0;
        else     btn_prev <= {btnC_db, btnR_db, btnL_db, btnD_db, btnU_db};
    end
    wire btnU_p = btnU_db & ~btn_prev[0];
    wire btnD_p = btnD_db & ~btn_prev[1];
    wire btnL_p = btnL_db & ~btn_prev[2];
    wire btnR_p = btnR_db & ~btn_prev[3];
    wire btnC_p = btnC_db & ~btn_prev[4];

    // ================================================================ game FSM, 7-seg
    game_fsm game_fsm_inst (
        .clk(clk), .rst(rst),
        .btnU(btnU_p), .btnD(btnD_p), .btnL(btnL_p), .btnR(btnR_p), .btnC(btnC_p),
        .screen_state(screen_state), .quantity(quantity)
    );

    quantity_7seg quantity_7seg_inst (
        .clk(clk), .rst(rst), .quantity(quantity), .an(an), .seg(seg)
    );

    // ================================================================ ORDER OUTPUTS
    // Screen codes are game_fsm's localparams.
    localparam [3:0] S_TITLE = 4'd0, S_PORTFOLIO = 4'd1, S_STOCKS = 4'd2, S_SPECIFIC = 4'd3,
                     S_BUY = 4'd4, S_SELL = 4'd5, S_CONFIRM = 4'd7, S_GAME_END = 4'd8;
    reg [3:0] state_d;
    always @(posedge clk) begin
        if (rst) state_d <= S_TITLE;
        else     state_d <= screen_state;
    end
    // choosing "confirmation" on the buy or sell screen places the order
    assign ord_req  = (screen_state == S_CONFIRM) && (state_d == S_BUY || state_d == S_SELL);
    assign ord_side = (state_d == S_SELL) ? `SIDE_SELL : `SIDE_BUY;

    // Selected stock: a copy of game_fsm's stocks_cursor, which is internal.
    reg [2:0] stocks_cursor;             // 0..3 stocks, 4 = back (as in game_fsm)
    always @(posedge clk) begin
        if (rst) begin
            stocks_cursor <= 3'd0;
            sel_stock     <= 2'd0;
        end else begin
            if (state_d == S_PORTFOLIO && screen_state == S_STOCKS)
                stocks_cursor <= 3'd0;   // game_fsm resets it on this transition
            else if (screen_state == S_STOCKS) begin
                // same order of ifs as game_fsm: L and R win over U and D
                if (btnR_p)      stocks_cursor <= 3'd0;
                else if (btnL_p) stocks_cursor <= 3'd4;
                else if (btnD_p) stocks_cursor <= (stocks_cursor == 3'd3) ? 3'd4 : stocks_cursor + 3'd1;
                else if (btnU_p) stocks_cursor <= (stocks_cursor == 3'd0 || stocks_cursor == 3'd4)
                                                  ? 3'd3 : stocks_cursor - 3'd1;
            end
            if (state_d == S_STOCKS && screen_state == S_SPECIFIC)
                sel_stock <= stocks_cursor[1:0];
        end
    end

    assign game_state = (screen_state == S_TITLE || screen_state == S_GAME_END)
                        ? `GS_MENU : `GS_PLAYING;

    // ================================================================ OLEDs
    wire clk_6_25MHz;
    slower_clk #(32'd7) clk_6_25MHz_inst (clk, clk_6_25MHz);

    // right (JB): game screens
    wire [12:0] pixel_index_R;
    wire [15:0] pixel_data_R;
    wire        frame_begin_R, sending_pixels_R, sample_pixel_R;
    OLED_Renderer Oled_Renderer (
        .pixel_index(pixel_index_R), .screen_state(screen_state), .pixel_data(pixel_data_R)
    );
    oled_display oled_R (
        .clk(clk_6_25MHz), .reset(rst), .pixel_data(pixel_data_R),
        .frame_begin(frame_begin_R), .sending_pixels(sending_pixels_R),
        .sample_pixel(sample_pixel_R), .pixel_index(pixel_index_R),
        .cs(JB[0]), .sdin(JB[1]), .sclk(JB[3]), .d_cn(JB[4]),
        .resn(JB[5]), .vccen(JB[6]), .pmoden(JB[7])
    );
    assign JB[2] = 1'b0;

    // left (JA): left_pixel, drawn at (left_x, left_y)
    wire [12:0] pixel_index_L;
    wire        frame_begin_L, sending_pixels_L, sample_pixel_L;
    assign left_x = pixel_index_L % 96;
    assign left_y = pixel_index_L / 96;
    oled_display oled_L (
        .clk(clk_6_25MHz), .reset(rst), .pixel_data(left_pixel),
        .frame_begin(frame_begin_L), .sending_pixels(sending_pixels_L),
        .sample_pixel(sample_pixel_L), .pixel_index(pixel_index_L),
        .cs(JA[0]), .sdin(JA[1]), .sclk(JA[3]), .d_cn(JA[4]),
        .resn(JA[5]), .vccen(JA[6]), .pmoden(JA[7])
    );
    assign JA[2] = 1'b0;
endmodule

`default_nettype wire
