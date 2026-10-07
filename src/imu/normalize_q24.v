// Normalise a four-component signed Q8.24 vector, using a shared square
// multiplier, integer square root and serial unsigned long division.
// All inputs are latched on start. Zero/tiny magnitude produces zero vector.
module normalize_q24 #(
    parameter [32:0] MIN_MAGNITUDE = 33'd0
)(
    input wire clk, input wire rst_n, input wire start,
    input wire signed [31:0] v0, v1, v2, v3,
    output wire busy, output reg done, output reg zero,
    output reg [32:0] magnitude,
    output reg signed [31:0] n0, n1, n2, n3
);
    localparam IDLE=0, SQUARE=1, SUM=2, SQRT_START=3, SQRT_WAIT=4,
               DIV_START=5, DIV_STEP=6, DIV_STORE=7;
    reg [3:0] state;
    reg signed [31:0] vector [0:3];
    reg [1:0] index;
    reg [63:0] square;
    reg [65:0] sum;
    wire sqrt_done, sqrt_busy;
    wire [32:0] sqrt_root;
    isqrt_u66 u_sqrt (.clk(clk),.rst_n(rst_n),.start(state==SQRT_START),
        .radicand(sum),.busy(sqrt_busy),.done(sqrt_done),.root(sqrt_root));
    reg [63:0] numerator, quotient;
    reg [33:0] remainder;
    reg [6:0] bit_count;
    reg negative;
    wire [31:0] abs_component = vector[index][31] ? -vector[index] : vector[index];
    wire [33:0] div_trial = {remainder[32:0], numerator[63]};
    wire div_subtract = div_trial >= {1'b0, magnitude};
    wire signed [31:0] signed_result = negative ? -$signed(quotient[31:0]) : $signed(quotient[31:0]);
    assign busy = state != IDLE;
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            state<=IDLE; done<=0; zero<=0; n0<=0; n1<=0; n2<=0; n3<=0;
            index<=0; square<=0; sum<=0; magnitude<=0;
            numerator<=0; quotient<=0; remainder<=0; bit_count<=0; negative<=0;
            for(i=0;i<4;i=i+1) vector[i]<=0;
        end else begin
            done <= 0;
            case(state)
                IDLE: if(start) begin
                    vector[0]<=v0; vector[1]<=v1; vector[2]<=v2; vector[3]<=v3;
                    index<=0; sum<=0; zero<=0; state<=SQUARE;
                end
                SQUARE: begin square <= vector[index]*vector[index]; state<=SUM; end
                SUM: begin
                    sum <= sum + {2'd0,square};
                    if(index==3) state<=SQRT_START;
                    else begin index<=index+1'b1; state<=SQUARE; end
                end
                SQRT_START: state<=SQRT_WAIT;
                SQRT_WAIT: if(sqrt_done) begin
                    magnitude<=sqrt_root; index<=0;
                    if(sqrt_root<=MIN_MAGNITUDE) begin
                        zero<=1; n0<=0; n1<=0; n2<=0; n3<=0; done<=1; state<=IDLE;
                    end else state<=DIV_START;
                end
                DIV_START: begin
                    numerator <= {8'd0,abs_component,24'd0};
                    quotient<=0; remainder<=0; bit_count<=64;
                    negative<=vector[index][31]; state<=DIV_STEP;
                end
                DIV_STEP: begin
                    numerator<=numerator<<1;
                    quotient<=(quotient<<1) | {63'd0,div_subtract};
                    remainder<=div_subtract ? div_trial-{1'b0,magnitude} : div_trial;
                    bit_count<=bit_count-1'b1;
                    if(bit_count==1) state<=DIV_STORE;
                end
                DIV_STORE: begin
                    case(index) 0:n0<=signed_result; 1:n1<=signed_result;
                        2:n2<=signed_result; 3:n3<=signed_result; endcase
                    if(index==3) begin done<=1; state<=IDLE; end
                    else begin index<=index+1'b1; state<=DIV_START; end
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
