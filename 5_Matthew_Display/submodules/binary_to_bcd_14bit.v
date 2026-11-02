

module binary_to_bcd_14bit (
    input  [13:0] bin,
    output reg [3:0] thousands,
    output reg [3:0] hundreds,
    output reg [3:0] tens,
    output reg [3:0] ones
);

    reg [29:0] shift_reg;
    reg [13:0] value;
    integer i;

    always @(*) begin

        // Limit the maximum displayed value to 9999
        if (bin > 14'd9999)
            value = 14'd9999;
        else
            value = bin;

        shift_reg = 30'b0;

        // Store the 14-bit binary input
        shift_reg[13:0] = value;

        // Double-dabble conversion
        for (i = 0; i < 14; i = i + 1) begin

            if (shift_reg[17:14] >= 5)
                shift_reg[17:14] = shift_reg[17:14] + 3;

            if (shift_reg[21:18] >= 5)
                shift_reg[21:18] = shift_reg[21:18] + 3;

            if (shift_reg[25:22] >= 5)
                shift_reg[25:22] = shift_reg[25:22] + 3;

            if (shift_reg[29:26] >= 5)
                shift_reg[29:26] = shift_reg[29:26] + 3;

            shift_reg = shift_reg << 1;
        end

        // Four BCD output digits
        thousands = shift_reg[29:26];
        hundreds  = shift_reg[25:22];
        tens      = shift_reg[21:18];
        ones      = shift_reg[17:14];

    end

endmodule
