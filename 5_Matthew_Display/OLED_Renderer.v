`timescale 1ns / 1ps
`include "trading_defs.vh"

// Right OLED (JB): every game screen.
//
// text_grid lays the screen out (header bar, six body rows or one big row);
// text_layer says what goes in each cell for the current screen; on the
// specific-stock screen chart_renderer draws the 30-day chart in rows 3-5,
// with the stock's stop-loss / take-profit levels as dashed lines. The bottom
// line of the header bar is a progress bar: how much of the game has gone.
// The title screen is drawn by title_art_renderer in D_display_top.
module OLED_Renderer (
    input  [12:0] pixel_index,
    input  [3:0]  screen_state,
    input  [2:0]  selected_stock,
    input  [3:0]  menu_selection,
    input  [1:0]  quantity_cursor,
    input         trade_side,
    input         trade_result_success,
    input  [2:0]  trade_result_code,
    input         order_valid,
    input  [2:0]  validation_code,
    input  [479:0] stock_samples,          // selected stock's 30-day history
    input  [`DN_N*32-1:0] numbers_bcd,     // from display_numbers
    input  [`DN_N-1:0]    numbers_neg,
    input  [3:0]  stock_up,                // stock k at or above its price 30 days ago
    input         trade_result_placed,
    input  [1:0]  order_type,
    input  [1:0]  order_brk,
    input         bot_view,                // sw15: the bot's screen
    input         bot_active,              // 0: no bot yet
    input  [7:0]  bot_signal,
    input  [15:0] sel_sl,                  // selected stock's SL / TP levels (0 = none)
    input  [15:0] sel_tp,
    input  [6:0]  progress_w,              // 0..96: width of the game-progress bar
    output [15:0] pixel_data
);
    wire [6:0]  pixel_x = pixel_index % 96;
    wire [5:0]  pixel_y = pixel_index / 96;

    wire [2:0]  row;
    wire [3:0]  col;
    wire        is_big, big, chart_on;
    wire [7:0]  ch;
    wire [15:0] fg, bg, text_color;

    text_grid grid (
        .x(pixel_x), .y(pixel_y), .big(big),
        .row(row), .col(col), .is_big(is_big),
        .ch(ch), .fg(fg), .bg(bg), .color(text_color)
    );

    text_layer text_layer_inst (
        .row(row), .col(col),
        .screen_state(screen_state),
        .menu_selection(menu_selection),
        .selected_stock(selected_stock),
        .quantity_cursor(quantity_cursor),
        .trade_side(trade_side),
        .trade_result_success(trade_result_success),
        .trade_result_code(trade_result_code),
        .order_valid(order_valid),
        .validation_code(validation_code),
        .bcd(numbers_bcd),
        .neg(numbers_neg),
        .up(stock_up),
        .trade_result_placed(trade_result_placed),
        .order_type(order_type),
        .order_brk(order_brk),
        .bot_view(bot_view),
        .bot_active(bot_active),
        .bot_signal(bot_signal),
        .big(big), .chart_on(chart_on),
        .ch(ch), .fg(fg), .bg(bg)
    );

    wire        chart_active;
    wire [15:0] chart_color;
    chart_renderer chart_renderer_inst (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .chart_mode(chart_on ? 2'b01 : 2'b00),
        .stock_samples(stock_samples),
        .portfolio_samples(960'd0),
        .live_value(32'd0),
        .sl_price(sel_sl),
        .tp_price(sel_tp),
        .pixel_active(chart_active),
        .pixel_color(chart_color)
    );

    // game progress: the header's bottom line, filled from the left
    wire on_progress = (screen_state != `UI_TITLE) && (pixel_y == 6'd9) && (pixel_x < progress_w);

    assign pixel_data = on_progress  ? 16'hFFE0 :
                        chart_active ? chart_color : text_color;
endmodule
