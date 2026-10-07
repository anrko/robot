`timescale 1ns/1ps
module tb_madgwick_compare;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,valid_in=0,ready_out=0;
    reg signed [31:0] ax=0,ay=0,az=0,wx=0,wy=0,wz=0;
    reg [31:0] dt=0;
    wire ready_in,valid_out;
    wire signed [31:0] qw,qx,qy,qz;
    madgwick_imu dut(.clk(clk),.rst_n(rst_n),.valid_in(valid_in),.ready_in(ready_in),
        .ax(ax),.ay(ay),.az(az),.wx(wx),.wy(wy),.wz(wz),.dt_q24(dt),
        .valid_out(valid_out),.ready_out(ready_out),.qw(qw),.qx(qx),.qy(qy),.qz(qz));
    integer vectors,results,rc,reset_row,number=0,cycles,stall;
    reg [1023:0] input_path,output_path;
    reg [127:0] held;
    initial begin
        if(!$value$plusargs("INPUT=%s",input_path)) $fatal(1,"missing INPUT");
        if(!$value$plusargs("OUTPUT=%s",output_path)) $fatal(1,"missing OUTPUT");
        vectors=$fopen(input_path,"r");results=$fopen(output_path,"w");
        if(vectors==0 || results==0) $fatal(1,"cannot open vector files");
        repeat(4) @(negedge clk);rst_n=1;
        while(!$feof(vectors)) begin
            rc=$fscanf(vectors,"%d %d %d %d %d %d %d %d\n",reset_row,ax,ay,az,wx,wy,wz,dt);
            if(rc==8) begin
                if(reset_row) begin rst_n=0;repeat(3) @(negedge clk);rst_n=1;end
                wait(ready_in);valid_in=1;@(negedge clk);valid_in=0;
                // Inputs may change immediately after the accepted sample.
                ax=32'sh12345678;ay=-32'sd1;az=0;wx=0;wy=0;wz=0;dt=0;
                cycles=0;
                while(!valid_out && cycles<2000) begin @(negedge clk);cycles=cycles+1;end
                if(!valid_out) $fatal(1,"sample %0d timeout",number);
                if((^{qw,qx,qy,qz})===1'bx) $fatal(1,"unknown output");
                held={qw,qx,qy,qz};
                for(stall=0;stall<(number%5);stall=stall+1) begin
                    @(negedge clk);
                    if(!valid_out || ready_in || {qw,qx,qy,qz}!==held)
                        $fatal(1,"output changed under backpressure");
                end
                $fwrite(results,"%0d,%0d,%0d,%0d,%0d,%0d\n",number,qw,qx,qy,qz,cycles);
                ready_out=1;@(negedge clk);ready_out=0;
                if(valid_out) $fatal(1,"output did not retire");
                number=number+1;
            end else if(rc!=-1) $fatal(1,"malformed vector row");
        end
        $fclose(vectors);$fclose(results);
        $display("PASS: %0d samples, latched inputs, reset and output backpressure",number);
        $finish;
    end
    initial begin #2000000000;$fatal(1,"global timeout");end
endmodule
