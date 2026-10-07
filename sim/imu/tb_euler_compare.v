`timescale 1ns/1ps
module tb_euler_compare;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,valid_in=0,ready_out=0;
    reg signed [31:0] qw=0,qx=0,qy=0,qz=0;
    wire ready_in,valid_out;
    wire signed [15:0] roll,pitch,yaw;
    wire [15:0] rb,pb,yb;
    wire rn,pn,yn;
    quaternion_euler dut(.clk(clk),.rst_n(rst_n),.valid_in(valid_in),.ready_in(ready_in),
        .qw(qw),.qx(qx),.qy(qy),.qz(qz),.valid_out(valid_out),.ready_out(ready_out),
        .roll_d10(roll),.pitch_d10(pitch),.yaw_d10(yaw));
    angle_bcd r(.angle_d10(roll),.negative(rn),.bcd(rb));
    angle_bcd p(.angle_d10(pitch),.negative(pn),.bcd(pb));
    angle_bcd y(.angle_d10(yaw),.negative(yn),.bcd(yb));
    integer fi,fo,rc,number=0,cycles,stall;
    reg [1023:0] input_path,output_path;
    reg [47:0] held;
    initial begin
        if(!$value$plusargs("INPUT=%s",input_path)) $fatal(1,"missing INPUT");
        if(!$value$plusargs("OUTPUT=%s",output_path)) $fatal(1,"missing OUTPUT");
        fi=$fopen(input_path,"r");fo=$fopen(output_path,"w");
        if(!fi || !fo) $fatal(1,"open failed");
        repeat(4) @(negedge clk);rst_n=1;
        while(!$feof(fi)) begin
            rc=$fscanf(fi,"%d %d %d %d\n",qw,qx,qy,qz);
            if(rc==4) begin
                wait(ready_in);valid_in=1;@(negedge clk);valid_in=0;
                qw=0;qx=0;qy=0;qz=0;
                cycles=0;
                while(!valid_out && cycles<300) begin @(negedge clk);cycles=cycles+1;end
                if(!valid_out) $fatal(1,"Euler timeout");
                held={roll,pitch,yaw};
                for(stall=0;stall<number%3;stall=stall+1) begin
                    @(negedge clk);
                    if(!valid_out || ready_in || {roll,pitch,yaw}!==held) $fatal(1,"Euler backpressure");
                end
                $fwrite(fo,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",roll,pitch,yaw,rb,pb,yb,rn,pn,yn,cycles);
                ready_out=1;@(negedge clk);ready_out=0;number=number+1;
            end else if(rc!=-1) $fatal(1,"bad row");
        end
        $fclose(fi);$fclose(fo);$display("PASS: %0d Euler/BCD vectors",number);$finish;
    end
    initial begin #1000000000;$fatal(1,"Euler global timeout");end
endmodule
