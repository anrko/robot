`timescale 1ns/1ps
module tb_bmi088_spi;
  reg clk=0, rst_n=0, miso=0, int1=0, int3=0;
  wire sck,mosi,cs1,cs2,sample_valid,init_done;
  wire signed [15:0] ax,ay,az,gx,gy,gz;
  wire [7:0] aid,gid;
  integer txn=0, bit_index=0;
  reg [63:0] response;
  always #10 clk=~clk;
  bmi088_spi dut(.clk(clk),.rst_n(rst_n),.spi_sclk(sck),.spi_mosi(mosi),.spi_miso(miso),
    .spi_csb1(cs1),.spi_csb2(cs2),.int1(int1),.int3(int3),.sample_valid(sample_valid),
    .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.init_done(init_done),
    .accel_id(aid),.gyro_id(gid));

  always @(negedge cs1 or negedge cs2) begin
    bit_index = 0;
    // Top seven/eight bytes are returned MSB first. Writes ignore MISO.
    case (txn)
      0: response = 64'h000F000000000000;             // gyro ID
      1: response = 64'h00001E0000000000;             // accel ID
      8: response = 64'h0034127856BC9A00;             // gyro: 00,34,12,78,56,bc,9a
      9: response = 64'h0000111122223333;             // accel: 00,00,11,11,22,22,33,33
      default: response = 64'd0;
    endcase
    txn = txn + 1;
    miso = response[63];
  end
  always @(negedge sck) begin
    if ((!cs1 || !cs2) && bit_index < 63) begin
      bit_index = bit_index + 1;
      miso = response[63-bit_index];
    end
  end

  initial begin
    repeat(3) @(posedge clk); rst_n=1;
    wait(init_done);
    if (gid !== 8'h0f || aid !== 8'h1e) begin
      $display("FAIL IDs gyro=%h accel=%h",gid,aid); $fatal;
    end
    wait(sample_valid);
    if (gx !== 16'h1234 || gy !== 16'h5678 || gz !== 16'h9abc ||
        ax !== 16'h1111 || ay !== 16'h2222 || az !== 16'h3333) begin
      $display("FAIL data ax=%h %h %h gx=%h %h %h",ax,ay,az,gx,gy,gz); $fatal;
    end
    $display("PASS BMI088 SPI IDs and raw data");
    #100 $finish;
  end
endmodule
