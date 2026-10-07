`timescale 1ns/1ps
`include "madgwickDefines.vh"
module review_mqfu_smoke;
reg clk=0; always #10 clk=~clk;
reg rst_n=0,valid_in=0,ready_out=1;
wire ready_in,valid_out;
reg signed [`ACC_WIDTH-1:0] ax=0,ay=0,az=4096;
reg signed [`GYRO_WIDTH-1:0] wx=0,wy=0,wz=0;
wire signed [`Q_WIDTH-1:0] qw,qx,qy,qz;
integer i;
madgwick dut(.clk(clk),.rst_n(rst_n),.valid_in(valid_in),.ready_in(ready_in),.a_x(ax),.a_y(ay),.a_z(az),.w_x(wx),.w_y(wy),.w_z(wz),.valid_out(valid_out),.ready_out(ready_out),.q_w_norm_output(qw),.q_x_norm_output(qx),.q_y_norm_output(qy),.q_z_norm_output(qz));
task update;
begin
wait(ready_in); @(negedge clk); valid_in=1;
@(negedge clk); valid_in=0;
wait(valid_out); @(negedge clk);
if ((^{qw,qx,qy,qz}) === 1'bx) $fatal(1,"unknown quaternion");
$display("sample=%0d q=%0d,%0d,%0d,%0d gyro_z=%0d half_qw=%0d qdot_z=%0d",i,qw,qx,qy,qz,wz,dut.q_w_half_q_dot,dut.q_dot_z);
wait(!valid_out);
end
endtask
initial begin
repeat(4) @(negedge clk); rst_n=1;
for(i=0;i<8;i=i+1) update;
wz=65536;
for(i=8;i<16;i=i+1) update;
$finish;
end
initial begin #2000000; $fatal(1,"transaction timeout"); end
endmodule
