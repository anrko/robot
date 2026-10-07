// Vectoring CORDIC, atan2(y,x), degrees with 16 fractional bits.
// Twenty-three iterations, quadrant correction, widened vector registers.
module atan2_cordic (
    input wire clk,input wire rst_n,input wire start,
    input wire signed [31:0] x_in,y_in,
    output reg busy,output reg done,output reg signed [31:0] angle_q16
);
    reg signed [35:0] x,y;
    reg [4:0] index;
    reg signed [31:0] increment;
    always @* case(index)
         0:increment=2949120; 1:increment=1740967; 2:increment=919879;
         3:increment=466945; 4:increment=234379; 5:increment=117304;
         6:increment=58666; 7:increment=29335; 8:increment=14668;
         9:increment=7334;10:increment=3667;11:increment=1833;
        12:increment=917;13:increment=458;14:increment=229;
        15:increment=115;16:increment=57;17:increment=29;
        18:increment=14;19:increment=7;20:increment=4;
        21:increment=2;22:increment=1;default:increment=0;
    endcase
    always @(posedge clk) begin
        if(!rst_n) begin busy<=0;done<=0;angle_q16<=0;x<=0;y<=0;index<=0;end
        else begin
            done<=0;
            if(start && !busy) begin
                busy<=1;index<=0;
                if(x_in<0) begin
                    x<=-$signed({{4{x_in[31]}},x_in});y<=-$signed({{4{y_in[31]}},y_in});
                    angle_q16<=y_in<0 ? -32'sd11796480 : 32'sd11796480;
                end else begin x<=x_in;y<=y_in;angle_q16<=0;end
            end else if(busy) begin
                if(y>0) begin x<=x+(y>>>index);y<=y-(x>>>index);angle_q16<=angle_q16+increment;end
                else if(y<0) begin x<=x-(y>>>index);y<=y+(x>>>index);angle_q16<=angle_q16-increment;end
                index<=index+1'b1;
                if(index==22) begin busy<=0;done<=1;end
            end
        end
    end
endmodule
