`timescale 1ns / 1ps

// Generic rotating buffer storage.
//
// The newest item is stored at index 0 of storage_out.  Older items move
// towards index X-1 whenever en is asserted.
module last_x_storage #(
    parameter integer X = 4,          // Number of items to store
    parameter integer WIDTH = 8        // Bit-width of each item
    )(
    input wire                   clk,
    input wire                   rst,        // Active-high synchronous reset
    input wire                   en,         // Enable signal to push a new item
    input wire [WIDTH-1:0]        data_in,
    output reg [(X*WIDTH)-1:0]    storage_out
    );

    reg [WIDTH-1:0] buffer [0:X-1];

    integer i;
    integer j;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < X; i = i + 1) begin
                buffer[i] <= {WIDTH{1'b0}};
            end
        end else if (en) begin
            for (i = X-1; i > 0; i = i - 1) begin
                buffer[i] <= buffer[i-1];
            end
            buffer[0] <= data_in;
        end
    end

    // Pack the internal array into a flat bus for Verilog compatibility.
    always @(*) begin
        storage_out = {(X*WIDTH){1'b0}};
        for (j = 0; j < X; j = j + 1) begin
            storage_out[j*WIDTH +: WIDTH] = buffer[j];
        end
    end

endmodule
