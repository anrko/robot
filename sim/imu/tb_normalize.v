`timescale 1ns/1ps
module tb_normalize;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,start=0;
    reg signed [31:0] a=0,b=0,c=0,d=0;
    wire signed [31:0] n0,n1,n2,n3;
    wire busy,done,zero;
    wire [32:0] magnitude;
    normalize_q24 dut(.clk(clk),.rst_n(rst_n),.start(start),
        .v0(a),.v1(b),.v2(c),.v3(d),.busy(busy),.done(done),.zero(zero),
        .magnitude(magnitude),.n0(n0),.n1(n1),.n2(n2),.n3(n3));
    integer fi,fo,rc,count=0,cycles;
    reg [1023:0] ip,op;
    initial begin
        if(!$value$plusargs("INPUT=%s",ip) || !$value$plusargs("OUTPUT=%s",op)) $fatal(1,"missing paths");
        fi=$fopen(ip,"r");fo=$fopen(op,"w");
        repeat(3) @(negedge clk);rst_n=1;
        while(!$feof(fi)) begin
            rc=$fscanf(fi,"%d %d %d %d\n",a,b,c,d);
            if(rc==4) begin
                start=1;@(negedge clk);start=0;a=0;b=0;c=0;d=0;
                cycles=0;
                while(!done && cycles<400) begin @(negedge clk);cycles=cycles+1;end
                if(!done) $fatal(1,"norm timeout");
                $fwrite(fo,"%0d,%0d,%0d,%0d,%0d,%0d\n",magnitude,zero,n0,n1,n2,n3);
                count=count+1;@(negedge clk);
            end else if(rc!=-1) $fatal(1,"bad norm input");
        end
        $fclose(fi);$fclose(fo);$display("PASS: %0d normalisation vectors",count);$finish;
    end
    initial begin #10000000;$fatal(1,"norm global timeout");end
endmodule
