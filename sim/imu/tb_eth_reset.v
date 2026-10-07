`timescale 1ns/1ps
// FIFO stub is only for the reset/state-machine check, not FIFO validation.
module eth_tx_fifo(input [15:0] Data,input Reset,WrClk,RdClk,WrEn,RdEn,
    output [13:0] Rnum,output Almost_Empty,Almost_Full,output [7:0] Q,output Empty,Full);
    assign Rnum=14'd8;assign Q=0;
    assign Almost_Empty=0;assign Almost_Full=0;assign Empty=0;assign Full=0;
endmodule
module tb_eth_reset;
    reg clk=0,reset=1;always #4 clk=~clk;
    wire tx;
    wire [7:0] data;
    eth_tx_ctrl #(.PAYLOAD_LENGTH(4)) dut(.reset_p(reset),.clk(clk),.data_i(16'd0),.data_valid_i(1'b0),
        .eth_txfifo_rd_clk(clk),.tx_en_pulse(tx),.tx_done(1'b1),.eth_txfifo_rden(1'b0),.eth_txfifo_dout(data));
    integer i;
    initial begin
        repeat(4) @(negedge clk);#1;reset=0;
        for(i=0;i<3;i=i+1) begin
            @(negedge clk);if(tx!==0 || dut.curr_state!==0) $fatal(1,"early reset release");
        end
        wait(tx);#1;reset=1;#1;if(tx!==0) $fatal(1,"reset did not assert asynchronously");
        repeat(4) @(negedge clk);#1;reset=0;wait(tx);
        $display("PASS: Ethernet read-clock reset release and asynchronous assertion");$finish;
    end
    initial begin #1000;$fatal(1,"reset timeout");end
endmodule
