// Replace the sample producer with a calibrated BMI088 acquisition module.
// This interface contains physical units, not BMI088 register counts.
module attitude_pipeline (
    input wire clk,input wire rst_n,
    input wire sample_valid,output wire sample_ready,
    input wire signed [31:0] ax,ay,az,wx,wy,wz,
    input wire [31:0] dt_q24,
    output wire attitude_valid,input wire attitude_ready,
    output wire [50:0] attitude_payload,
    output wire signed [15:0] roll_d10,pitch_d10,yaw_d10
);
    wire qvalid,qready;
    wire signed [31:0] qw,qx,qy,qz;
    wire signed [15:0] roll,pitch,yaw;
    wire [15:0] rb,pb,yb;
    wire rn,pn,yn;
    madgwick_imu u_filter(.clk(clk),.rst_n(rst_n),.valid_in(sample_valid),.ready_in(sample_ready),
        .ax(ax),.ay(ay),.az(az),.wx(wx),.wy(wy),.wz(wz),.dt_q24(dt_q24),
        .valid_out(qvalid),.ready_out(qready),.qw(qw),.qx(qx),.qy(qy),.qz(qz));
    quaternion_euler u_euler(.clk(clk),.rst_n(rst_n),.valid_in(qvalid),.ready_in(qready),
        .qw(qw),.qx(qx),.qy(qy),.qz(qz),.valid_out(attitude_valid),.ready_out(attitude_ready),
        .roll_d10(roll),.pitch_d10(pitch),.yaw_d10(yaw));
    angle_bcd r(.angle_d10(roll),.negative(rn),.bcd(rb));
    angle_bcd p(.angle_d10(pitch),.negative(pn),.bcd(pb));
    angle_bcd y(.angle_d10(yaw),.negative(yn),.bcd(yb));
    assign attitude_payload={rn,rb,pn,pb,yn,yb};
    assign roll_d10=roll;
    assign pitch_d10=pitch;
    assign yaw_d10=yaw;
endmodule
