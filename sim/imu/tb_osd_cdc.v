`timescale 1ns/1ps
module tb_osd_cdc;
    reg src_clk=0,dst_clk=0,src_rst_n=0,dst_rst_n=0,enable_dst=1;
    always #10 src_clk=~src_clk;
    always #7 if(enable_dst) dst_clk=~dst_clk;else dst_clk=0;
    reg valid=0,frame_start=0;
    reg [50:0] payload=0;
    wire ready;
    wire [50:0] displayed;
    osd_attitude_cdc dut(.src_clk(src_clk),.src_rst_n(src_rst_n),.src_valid(valid),
        .src_ready(ready),.src_payload(payload),.dst_clk(dst_clk),.dst_rst_n(dst_rst_n),
        .frame_start(frame_start),.frame_payload(displayed));
    reg [50:0] expected=0,latest=0;
    integer i;
    task send;
        input [50:0] value;
        begin
            @(negedge src_clk);while(!ready) @(negedge src_clk);
            payload=value;valid=1;@(negedge src_clk);valid=0;payload=0;
            while(!ready) @(negedge src_clk);
            latest=value;
        end
    endtask
    task frame;
        begin
            @(negedge dst_clk);frame_start=1;@(negedge dst_clk);frame_start=0;
            expected=latest;
            if(displayed!==expected) $fatal(1,"frame payload is incoherent");
        end
    endtask
    always @(negedge dst_clk)
        if(dst_rst_n && !frame_start && displayed!==expected) $fatal(1,"mid-frame angle change");
    initial begin
        repeat(4) @(negedge src_clk);src_rst_n=1;dst_rst_n=1;
        for(i=1;i<=60;i=i+1) begin
            send((51'h123456789abcd*i) ^ (51'h72abcdef01234>>i%17));
            if(i%3==0) frame;
        end
        // A stopped destination clock must hold the source mailbox busy.
        @(negedge src_clk);enable_dst=0;payload=51'h71abcdeffedcb;valid=1;
        @(negedge src_clk);valid=0;
        repeat(20) @(negedge src_clk);
        if(ready) $fatal(1,"mailbox acknowledged without destination clock");
        enable_dst=1;while(!ready) @(negedge src_clk);latest=payload;payload=0;frame;
        @(negedge src_clk);src_rst_n=0;dst_rst_n=0;expected=0;
        repeat(4) @(negedge src_clk);src_rst_n=1;dst_rst_n=1;
        repeat(8) @(negedge dst_clk);if(displayed!==0) $fatal(1,"CDC reset failed");
        $display("PASS: CDC coherent mailbox, frame latching, stopped clock and reset");$finish;
    end
    initial begin #1000000;$fatal(1,"CDC timeout");end
endmodule
