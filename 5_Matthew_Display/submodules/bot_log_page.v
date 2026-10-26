`timescale 1ns / 1ps
`default_nettype none
`include "trading_defs.vh"

// bot_log_page: the left OLED in the bot view (sw1 up), on the text_grid layout.
//
//   row 0     BOT TRADES          header (plum, as the bot view on the right OLED)
//   rows 1-5  09 B AMD   213.50   the bot's last 5 trades, newest first:
//                                 day, Buy / Sell (green / red), stock, price
//   row 6     RULE: 8-DAY AVG
//
// FLIP_180 = 1 turns the page for the upside-down left OLED, as the ticket does.
module bot_log_page #(
    parameter FLIP_180 = 0
) (
    input  wire [6:0]  pix_x,
    input  wire [5:0]  pix_y,
    input  wire [`DN_N*32-1:0] bcd,       // display_numbers (log prices and days)
    input  wire [4:0]  log_valid,
    input  wire [4:0]  log_side,
    input  wire [9:0]  log_stock,
    output wire [15:0] pixel
);
    localparam [15:0] BLACK  = 16'h0000,
                      WHITE  = 16'hFFFF,
                      CYAN   = 16'h07FF,
                      GREEN  = 16'h07E0,
                      RED    = 16'hF8A2,
                      GREY   = 16'h8C51,
                      BOTHDR = 16'h4808;

    wire [6:0] px = FLIP_180 ? 7'd95 - pix_x : pix_x;
    wire [5:0] py = FLIP_180 ? 6'd63 - pix_y : pix_y;

    function [7:0] str_ch;
        input [127:0] s;
        input [3:0]   c;
        begin
            str_ch = s[127 - 8*c -: 8];
        end
    endfunction

    function [7:0] ticker_ch;
        input [1:0] k;
        input [3:0] p;
        reg [31:0] t;
        begin
            case (k)
                2'd0:    t = "AMD ";
                2'd1:    t = "MCD ";
                2'd2:    t = "NVDA";
                default: t = "GME ";
            endcase
            ticker_ch = (p > 4'd3) ? " " : t[31 - 8*p -: 8];
        end
    endfunction

    // a BCD price, right-aligned in 6 cells: "213.50", "  9.95"
    function [7:0] price_ch;
        input [31:0] d;
        input [3:0]  p;
        begin
            case (p)
                4'd0:    price_ch = (d[19:16] == 4'd0) ? " " : "0" + d[19:16];
                4'd1:    price_ch = (d[19:12] == 8'd0) ? " " : "0" + d[15:12];
                4'd2:    price_ch = "0" + d[11:8];
                4'd3:    price_ch = ".";
                4'd4:    price_ch = "0" + d[7:4];
                default: price_ch = "0" + d[3:0];
            endcase
        end
    endfunction

    wire [2:0]  row;
    wire [3:0]  col;
    wire        is_big;
    reg  [7:0]  ch;
    reg  [15:0] fg, bg;

    text_grid grid (
        .x(px), .y(py), .big(1'b0),
        .row(row), .col(col), .is_big(is_big),
        .ch(ch), .fg(fg), .bg(bg), .color(pixel)
    );

    // log entry on this row (rows 1-5 = entries 0-4)
    wire [2:0]  n     = row - 3'd1;
    wire        e_v   = log_valid[n];
    wire        e_s   = log_side[n];
    wire [1:0]  e_k   = log_stock[2*n +: 2];
    wire [31:0] e_px  = bcd[32*(`DN_LOGPX0 + n)  +: 32];
    wire [31:0] e_day = bcd[32*(`DN_LOGDAY0 + n) +: 32];

    always @* begin
        ch = " ";
        fg = WHITE;
        bg = BLACK;
        if (row == 3'd0) begin
            bg = BOTHDR;
            ch = str_ch("BOT TRADES      ", col);
        end else if (row <= 3'd5) begin
            if (!e_v) begin
                if (row == 3'd1) begin ch = str_ch("NO TRADES YET   ", col); fg = GREY; end
            end else if (col <= 4'd1) begin                          // day
                ch = "0" + e_day[4*(1 - col) +: 4];
                fg = GREY;
            end else if (col == 4'd3) begin                          // B / S
                ch = e_s ? "S" : "B";
                fg = e_s ? RED : GREEN;
            end else if (col >= 4'd5 && col <= 4'd8) begin
                ch = ticker_ch(e_k, col - 4'd5);
                fg = CYAN;
            end else if (col >= 4'd10) begin
                ch = price_ch(e_px, col - 4'd10);
            end
        end else begin
            ch = str_ch("RULE: 8-DAY AVG ", col);
            fg = GREY;
        end
    end
endmodule

`default_nettype wire
