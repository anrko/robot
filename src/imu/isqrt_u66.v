// Restoring integer square root: floor(sqrt(radicand)), 33 iterations.
// No vendor primitives and no combinational division/square-root operators.
module isqrt_u66 (
    input wire clk, input wire rst_n, input wire start,
    input wire [65:0] radicand,
    output reg busy, output reg done, output reg [32:0] root
);
    reg [65:0] bits_left;
    reg [67:0] remainder;
    reg [5:0] count;
    wire [67:0] shifted = (remainder << 2) | {66'd0, bits_left[65:64]};
    wire [67:0] trial = ({35'd0, root} << 2) | 68'd1;
    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 0; done <= 0; root <= 0;
            bits_left <= 0; remainder <= 0; count <= 0;
        end else begin
            done <= 0;
            if (start && !busy) begin
                busy <= 1; root <= 0; remainder <= 0;
                bits_left <= radicand; count <= 33;
            end else if (busy) begin
                bits_left <= bits_left << 2;
                if (shifted >= trial) begin
                    remainder <= shifted - trial;
                    root <= (root << 1) | 33'd1;
                end else begin
                    remainder <= shifted;
                    root <= root << 1;
                end
                count <= count - 1'b1;
                if (count == 1) begin busy <= 0; done <= 1; end
            end
        end
    end
endmodule
