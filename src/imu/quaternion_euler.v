// Q8.24 quaternion -> ZYX Euler angles, signed tenths of a degree.
// atan2 is used for roll/yaw; pitch = atan2(sin(pitch),sqrt(1-sin^2)).
// Quaternion must already be unit length. No software or vendor math IP.
module quaternion_euler (
    input wire clk,input wire rst_n,
    input wire valid_in,output wire ready_in,
    input wire signed [31:0] qw,qx,qy,qz,
    output reg valid_out,input wire ready_out,
    output reg signed [15:0] roll_d10,pitch_d10,yaw_d10
);
    localparam signed [31:0] ONE=32'sd16777216;
    localparam IDLE=0,SETUP=1,MULT=2,STORE=3,SQUARE=4,SQRT_START=5,
        SQRT_WAIT=6,ANGLE_START=7,ANGLE_WAIT=8,OUTPUT=9,RADICAND=10;
    reg [3:0] state,pc;
    reg [1:0] axis;
    reg signed [31:0] w,x,y,z,ma,mb,oa,ob;
    reg signed [31:0] roll_num,roll_den,pitch_sin,pitch_cos,yaw_num,yaw_den;
    reg signed [63:0] product,accumulator;
    wire signed [63:0] sum=pc==5 ? accumulator-product : accumulator+product;
    wire signed [63:0] doubled_sum=sum>>>23;
    reg [65:0] pitch_radicand;
    wire sqrt_busy,sqrt_done;
    wire [32:0] root;
    isqrt_u66 u_sqrt(.clk(clk),.rst_n(rst_n),.start(state==SQRT_START),
        .radicand(pitch_radicand),.busy(sqrt_busy),.done(sqrt_done),.root(root));
    wire signed [31:0] angle;
    wire atan_busy,atan_done;
    wire signed [31:0] cx=axis==0 ? roll_den : axis==1 ? pitch_cos : yaw_den;
    wire signed [31:0] cy=axis==0 ? roll_num : axis==1 ? pitch_sin : yaw_num;
    atan2_cordic u_atan(.clk(clk),.rst_n(rst_n),.start(state==ANGLE_START),
        .x_in(cx),.y_in(cy),.busy(atan_busy),.done(atan_done),.angle_q16(angle));
    // Round symmetrically to 0.1 degrees; -0.0 is not displayed.
    wire signed [31:0] abs_angle=angle<0 ? -angle : angle;
    wire signed [31:0] rounded_magnitude=(abs_angle*32'sd10+32'sd32768)>>>16;
    wire signed [15:0] rounded=angle<0 ? -rounded_magnitude : rounded_magnitude;
    assign ready_in=state==IDLE && !valid_out;
    always @* begin
        oa=0;ob=0;
        case(pc)
            0:begin oa=w;ob=x;end 1:begin oa=y;ob=z;end
            2:begin oa=x;ob=x;end 3:begin oa=y;ob=y;end
            4:begin oa=w;ob=y;end 5:begin oa=z;ob=x;end
            6:begin oa=w;ob=z;end 7:begin oa=x;ob=y;end
            8:begin oa=y;ob=y;end 9:begin oa=z;ob=z;end
        endcase
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE;pc<=0;axis<=0;w<=0;x<=0;y<=0;z<=0;ma<=0;mb<=0;
            product<=0;accumulator<=0;roll_num<=0;roll_den<=0;pitch_sin<=0;pitch_cos<=0;
            yaw_num<=0;yaw_den<=0;pitch_radicand<=0;
            valid_out<=0;roll_d10<=0;pitch_d10<=0;yaw_d10<=0;
        end else case(state)
            IDLE:if(valid_in && ready_in) begin w<=qw;x<=qx;y<=qy;z<=qz;pc<=0;state<=SETUP;end
            SETUP:begin ma<=oa;mb<=ob;state<=MULT;end
            MULT:begin product<=ma*mb;state<=STORE;end
            STORE:begin
                pc<=pc+1'b1;state<=SETUP;
                if(!pc[0]) accumulator<=product;
                else case(pc)
                    1:roll_num<=doubled_sum;
                    3:roll_den<=ONE-doubled_sum;
                    5:pitch_sin<=doubled_sum>ONE ? ONE : doubled_sum<-ONE ? -ONE : doubled_sum;
                    7:yaw_num<=doubled_sum;
                    9:begin yaw_den<=ONE-doubled_sum;state<=SQUARE;end
                endcase
            end
            SQUARE:begin product<=pitch_sin*pitch_sin;state<=RADICAND;end
            // SQUARE registers the product; this separate state forms radicand
            // before starting sqrt, so no stale value is consumed.
            RADICAND:begin pitch_radicand<=66'd281474976710656-{2'd0,product[63:0]};state<=SQRT_START;end
            SQRT_START:state<=SQRT_WAIT;
            SQRT_WAIT:if(sqrt_done) begin pitch_cos<=root;axis<=0;state<=ANGLE_START;end
            ANGLE_START:state<=ANGLE_WAIT;
            ANGLE_WAIT:if(atan_done) begin
                case(axis) 0:roll_d10<=rounded;1:pitch_d10<=rounded;2:yaw_d10<=rounded;endcase
                if(axis==2) begin valid_out<=1;state<=OUTPUT;end
                else begin axis<=axis+1'b1;state<=ANGLE_START;end
            end
            OUTPUT:if(ready_out) begin valid_out<=0;state<=IDLE;end
            default:state<=IDLE;
        endcase
    end
endmodule
