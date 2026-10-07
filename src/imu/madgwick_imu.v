// Six-axis Madgwick: gyro derivative -> gravity objective -> J^T*f gradient
// -> normalise gradient -> beta correction -> integrate -> normalise quaternion.
// Adapted from the MQFU mathematical datapath; see vendor/mqfu/LICENSE and README.
// Reworked Q formats, normalisation and ready/valid semantics for portable RTL.
// Signed Q8.24 throughout. Gyro input: rad/s. Acceleration: g (or consistent units).
// Quaternion convention: Hamilton (w,x,y,z), body-to-world, gravity +Z at rest.
// One shared 32x32 multiply datapath, registered before accumulation.
module madgwick_imu #(
    parameter signed [31:0] BETA_Q24 = 32'sd1677722,
    parameter [32:0] GRAD_MIN_Q24 = 33'd128
)(
    input wire clk, input wire rst_n,
    input wire valid_in, output wire ready_in,
    input wire signed [31:0] ax, ay, az, wx, wy, wz,
    input wire [31:0] dt_q24,
    output reg valid_out, input wire ready_out,
    output reg signed [31:0] qw, qx, qy, qz
);
    localparam signed [31:0] ONE = 32'sd16777216;
    localparam IDLE=0, ACC_START=1, ACC_WAIT=2, SETUP=3, MULT=4, STORE=5,
               GRAD_START=6, GRAD_WAIT=7, Q_START=8, Q_WAIT=9, OUTPUT=10;
    reg [3:0] state;
    reg [5:0] pc;
    reg signed [31:0] gx,gy,gz,dt;
    reg signed [31:0] a[0:2], f[0:2], d[0:3], s[0:3], t[0:3];
    reg signed [31:0] mul_a,mul_b;
    reg signed [63:0] product,accumulator;
    // Microinstruction accumulator control: 0=load, 1=negative load,
    // 2=add, 3=subtract. Derivative shifts 25, objective/gradient shifts 23.
    reg [1:0] action;
    reg signed [31:0] operand_a,operand_b;
    wire signed [63:0] accumulated = action==0 ? product : action==1 ? -product :
        action==2 ? accumulator+product : accumulator-product;
    reg signed [31:0] nv0,nv1,nv2,nv3;
    wire signed [31:0] nn0,nn1,nn2,nn3;
    wire norm_done,norm_zero,norm_busy;
    wire [32:0] norm_magnitude;
    // The same normaliser serves all stages. Tiny-gradient rejection is applied
    // by testing the norm engine's integer magnitude on the gradient stage.
    normalize_q24 u_norm (.clk(clk),.rst_n(rst_n),
        .start(state==ACC_START || state==GRAD_START || state==Q_START),
        .v0(nv0),.v1(nv1),.v2(nv2),.v3(nv3),.busy(norm_busy),.done(norm_done),
        .zero(norm_zero),.magnitude(norm_magnitude),.n0(nn0),.n1(nn1),.n2(nn2),.n3(nn3));
    assign ready_in = state==IDLE && !valid_out;
    always @* begin
        nv0=0;nv1=0;nv2=0;nv3=0;
        if(state==ACC_START) begin nv0=a[0];nv1=a[1];nv2=a[2];end
        if(state==GRAD_START) begin nv0=s[0];nv1=s[1];nv2=s[2];nv3=s[3];end
        if(state==Q_START) begin nv0=t[0];nv1=t[1];nv2=t[2];nv3=t[3];end
        operand_a=0;operand_b=0;action=0;
        case(pc)
             0:begin operand_a=qx;operand_b=gx;action=1;end
             1:begin operand_a=qy;operand_b=gy;action=3;end
             2:begin operand_a=qz;operand_b=gz;action=3;end
             3:begin operand_a=qw;operand_b=gx;end
             4:begin operand_a=qy;operand_b=gz;action=2;end
             5:begin operand_a=qz;operand_b=gy;action=3;end
             6:begin operand_a=qw;operand_b=gy;end
             7:begin operand_a=qx;operand_b=gz;action=3;end
             8:begin operand_a=qz;operand_b=gx;action=2;end
             9:begin operand_a=qw;operand_b=gz;end
            10:begin operand_a=qx;operand_b=gy;action=2;end
            11:begin operand_a=qy;operand_b=gx;action=3;end
            12:begin operand_a=qx;operand_b=qz;end
            13:begin operand_a=qw;operand_b=qy;action=3;end
            14:begin operand_a=qw;operand_b=qx;end
            15:begin operand_a=qy;operand_b=qz;action=2;end
            16:begin operand_a=qx;operand_b=qx;end
            17:begin operand_a=qy;operand_b=qy;action=2;end
            18:begin operand_a=qy;operand_b=f[0];action=1;end
            19:begin operand_a=qx;operand_b=f[1];action=2;end
            20:begin operand_a=qz;operand_b=f[0];end
            21:begin operand_a=qw;operand_b=f[1];action=2;end
            22:begin operand_a=qx<<<1;operand_b=f[2];action=3;end
            23:begin operand_a=qw;operand_b=f[0];action=1;end
            24:begin operand_a=qz;operand_b=f[1];action=2;end
            25:begin operand_a=qy<<<1;operand_b=f[2];action=3;end
            26:begin operand_a=qx;operand_b=f[0];end
            27:begin operand_a=qy;operand_b=f[1];action=2;end
            28,30,32,34:begin operand_a=BETA_Q24;operand_b=s[(pc-28)>>1];end
            29,31,33,35:begin operand_a=d[(pc-29)>>1];operand_b=dt;end
        endcase
    end
    integer i;
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE;pc<=0;valid_out<=0;qw<=ONE;qx<=0;qy<=0;qz<=0;
            gx<=0;gy<=0;gz<=0;dt<=0;mul_a<=0;mul_b<=0;product<=0;accumulator<=0;
            for(i=0;i<3;i=i+1) begin a[i]<=0;f[i]<=0;end
            for(i=0;i<4;i=i+1) begin d[i]<=0;s[i]<=0;t[i]<=0;end
        end else case(state)
            IDLE:if(valid_in && ready_in) begin
                a[0]<=ax;a[1]<=ay;a[2]<=az;gx<=wx;gy<=wy;gz<=wz;dt<=dt_q24;
                state<=ACC_START;
            end
            ACC_START:state<=ACC_WAIT;
            ACC_WAIT:if(norm_done) begin
                a[0]<=nn0;a[1]<=nn1;a[2]<=nn2;pc<=0;state<=SETUP;
                // With missing acceleration, skip gravity correction entirely.
                if(norm_zero) begin s[0]<=0;s[1]<=0;s[2]<=0;s[3]<=0;end
            end
            SETUP:begin mul_a<=operand_a;mul_b<=operand_b;state<=MULT;end
            MULT:begin product<=mul_a*mul_b;state<=STORE;end
            STORE:begin
                accumulator<=accumulated;pc<=pc+1'b1;state<=SETUP;
                case(pc)
                     2:d[0]<=accumulated>>>25;
                     5:d[1]<=accumulated>>>25;
                     8:d[2]<=accumulated>>>25;
                    11:begin
                        d[3]<=accumulated>>>25;
                        if(a[0]==0 && a[1]==0 && a[2]==0) pc<=28;
                    end
                    13:f[0]<=(accumulated>>>23)-a[0];
                    15:f[1]<=(accumulated>>>23)-a[1];
                    17:f[2]<=ONE-(accumulated>>>23)-a[2];
                    19:s[0]<=accumulated>>>23;
                    22:s[1]<=accumulated>>>23;
                    25:s[2]<=accumulated>>>23;
                    27:begin s[3]<=accumulated>>>23;state<=GRAD_START;end
                    28:d[0]<=d[0]-(product>>>24);
                    29:t[0]<=qw+(product>>>24);
                    30:d[1]<=d[1]-(product>>>24);
                    31:t[1]<=qx+(product>>>24);
                    32:d[2]<=d[2]-(product>>>24);
                    33:t[2]<=qy+(product>>>24);
                    34:d[3]<=d[3]-(product>>>24);
                    35:begin t[3]<=qz+(product>>>24);state<=Q_START;end
                endcase
            end
            GRAD_START:state<=GRAD_WAIT;
            GRAD_WAIT:if(norm_done) begin
                if(norm_zero || norm_magnitude<=GRAD_MIN_Q24) begin
                    s[0]<=0;s[1]<=0;s[2]<=0;s[3]<=0;
                end else begin s[0]<=nn0;s[1]<=nn1;s[2]<=nn2;s[3]<=nn3;end
                pc<=28;state<=SETUP;
            end
            Q_START:state<=Q_WAIT;
            Q_WAIT:if(norm_done) begin
                qw<=norm_zero ? ONE : nn0;qx<=norm_zero ? 0 : nn1;
                qy<=norm_zero ? 0 : nn2;qz<=norm_zero ? 0 : nn3;
                valid_out<=1;state<=OUTPUT;
            end
            OUTPUT:if(ready_out) begin valid_out<=0;state<=IDLE;end
            default:state<=IDLE;
        endcase
    end
endmodule
