`timescale 1ns/1ps
module tb_spi_byte_engine;
  reg clk=0, rst_n=0, start=0, cs_gyro=0, miso=0;
  reg [3:0] length=0;
  reg [63:0] tx_data=0;
  wire [63:0] rx_data;
  wire busy, done, sck, mosi, cs_accel, cs_gyro_o;
  integer bit_index;
  reg [23:0] response = 24'hA55AC3;
  always #10 clk=~clk;
  spi_byte_engine #(.DIV(2)) dut(.*);

  // Mode-0 slave: first MISO bit is valid while CS is asserted, then the
  // slave advances its output on each falling edge of SCK.
  always @(negedge cs_accel) begin bit_index = 0; miso = response[23]; end
  always @(negedge sck) begin
    if (!cs_accel && bit_index < 23) begin
      bit_index = bit_index + 1;
      miso = response[23-bit_index];
    end
  end

  initial begin
    repeat (3) @(posedge clk); rst_n=1;
    @(posedge clk); length=3; tx_data=64'h1234560000000000; start=1;
    @(posedge clk); start=0;
    wait(done);
    if (rx_data[23:0] !== response) begin
      $display("FAIL rx=%h expected=%h",rx_data[23:0],response); $fatal;
    end
    $display("PASS SPI engine rx=%h",rx_data[23:0]);
    #100 $finish;
  end
endmodule
