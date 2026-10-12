`timescale 1ns/1ps
module tb_bmi088_telemetry_uart;
    reg clk=0, rst_n=0, sample_valid=0, attitude_valid=0;
    wire uart_tx;
    always #5 clk=~clk;
    bmi088_telemetry_uart #(.CLK_HZ(40),.BAUD(10)) dut(
        .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),
        .ax(-16'sd1234),.ay(16'sd200),.az(16'sd16384),
        .gx(-16'sd50),.gy(16'sd25),.gz(16'sd7),
        .attitude_valid(attitude_valid),.attitude_ready(1'b1),
        .roll_d10(-16'sd101),.pitch_d10(16'sd22),.yaw_d10(-16'sd1799),
        .uart_tx(uart_tx));

    integer i,b,value;
    initial begin
        repeat(4) @(posedge clk); rst_n=1;
        @(posedge clk); sample_valid=1;
        @(posedge clk); sample_valid=0;
        repeat(2) @(posedge clk); attitude_valid=1;
        @(posedge clk); attitude_valid=0;
        for(i=0;i<26;i=i+1) begin
            @(negedge uart_tx);
            repeat(6) @(posedge clk); // center of data bit zero (4 clocks/bit)
            value=0;
            for(b=0;b<8;b=b+1) begin
                value[b]=uart_tx;
                repeat(4) @(posedge clk);
            end
            $write("%02x ",value[7:0]);
        end
        $display("");
        $finish;
    end
    initial begin #100000; $fatal(1,"UART frame timeout"); end
endmodule
