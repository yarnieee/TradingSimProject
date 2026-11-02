`timescale 1ns / 1ps

/////////////
// instantiate via:
// get_mode get_mode_inst (
//     .clk(clk),
//     .btn(btn),
//     .sw(sw),
//     .rst(rst),
//     .mode(mode)
// )
/////////////

module get_mode(
    input clk,
    input [4:0] btn,
    input [15:0] sw,
    input rst,
    output reg [2:0] mode = 3'b0
    ); // can count 8 modes 0-7

    reg [2:0] next_state;

    // LOGIC TO MAKE A TIME DELAYED MODE
    // Keep the delay enabled while in mode 0
    wire enable_delay_1s;
    wire delay_1s_done;
    assign enable_delay_1s = (mode == 3'd0);

    delay #(.DELAY(99_999_999)) delay_inst (
        .clk(clk),
        .enable(enable_delay_1s),
        .done(delay_1s_done)
        );

    // LOGIC TO SET 1 BUTTON AS ENABLE MOVEMENT
    wire enable_movement;
    debouncer debouncer_inst (clk, btn[4], enable_movement);

    always @(*) begin
        next_state = mode;

        case(mode)
            3'd0: begin //startup delay
                if (delay_1s_done && sw[0]) next_state = 3'd1;
            end

            3'd1: begin //seg movement enabled; oled enabled
                if (!enable_movement) next_state = 3'd2;
            end
            
            3'd2: begin //seg movement paused; oled enabled
                if (enable_movement) next_state = 3'd1;
            end

            default: begin //how did u end up here ???
                next_state = 3'd0;
            end
        endcase
    end

    always @(posedge clk) begin //if async reset then add posedge rst
        if (rst) begin
            mode <= 3'b0;
        end else begin
            mode <= next_state;
        end
    end
        
endmodule
