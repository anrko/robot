module debug_uart_tx #(
    parameter CLOCK_HZ = 75000000,
    parameter BAUD = 115200
)(
    input wire clk,
    input wire rst_n,
    input wire send,
    input wire [7:0] data,
    output reg tx,
    output reg busy
);
    localparam DIVIDER = (CLOCK_HZ + BAUD / 2) / BAUD;
    localparam COUNT_WIDTH = $clog2(DIVIDER);
    reg [COUNT_WIDTH-1:0] count;
    reg [3:0] bit_index;
    reg [9:0] shift;

    initial begin
        tx = 1'b1;
        busy = 1'b0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx <= 1'b1;
            busy <= 1'b0;
            count <= 0;
            bit_index <= 0;
            shift <= 10'h3ff;
        end else if (!busy) begin
            if (send) begin
                shift <= {1'b1, data, 1'b0};
                tx <= 1'b0;
                busy <= 1'b1;
                count <= DIVIDER - 1;
                bit_index <= 0;
            end
        end else if (count != 0) begin
            count <= count - 1'b1;
        end else if (bit_index == 9) begin
            tx <= 1'b1;
            busy <= 1'b0;
        end else begin
            shift <= {1'b1, shift[9:1]};
            tx <= shift[1];
            bit_index <= bit_index + 1'b1;
            count <= DIVIDER - 1;
        end
    end
endmodule
