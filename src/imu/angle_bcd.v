// Parallel double-dabble: signed tenths of degrees -> sign and four BCD digits.
module angle_bcd (
    input wire signed [15:0] angle_d10,
    output wire negative,
    output reg [15:0] bcd
);
    wire [15:0] magnitude=angle_d10<0 ? -angle_d10 : angle_d10;
    reg [15:0] digits;
    integer i,j;
    assign negative=angle_d10<0;
    always @* begin
        digits=0;
        for(i=15;i>=0;i=i-1) begin
            for(j=0;j<4;j=j+1)
                if(digits[j*4+:4]>=5) digits[j*4+:4]=digits[j*4+:4]+4'd3;
            digits={digits[14:0],magnitude[i]};
        end
        bcd=digits;
    end
endmodule
