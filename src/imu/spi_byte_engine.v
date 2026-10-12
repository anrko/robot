// Small SPI mode-0 byte engine for BMI088.  The sensor accepts SPI modes 0/3;
// mode 0 is selected by keeping SCK low when CS falls.
module spi_byte_engine #(parameter DIV=12) (
    input clk, input rst_n,
    input start, input cs_gyro, input [3:0] length,
    input [63:0] tx_data, output reg [63:0] rx_data,
    output reg busy, output reg done,
    output reg sck, output reg mosi, input miso,
    output reg cs_accel, output reg cs_gyro_o
);
    reg [7:0] divcnt;
    reg [3:0] nbytes, byte_count;
    reg [5:0] bits;
    reg [63:0] tx_shift, rx_shift;
    wire tick = (divcnt == DIV-1);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            divcnt<=0; nbytes<=0; byte_count<=0; bits<=0; tx_shift<=0; rx_shift<=0;
            rx_data<=0; busy<=0; done<=0; sck<=0; mosi<=0; cs_accel<=1; cs_gyro_o<=1;
        end else begin
            done<=0;
            if (!busy) begin
                divcnt<=0; sck<=0; mosi<=0; cs_accel<=1; cs_gyro_o<=1;
                if (start && length!=0) begin
                    busy<=1; nbytes<=length; byte_count<=0; bits<=0;
                    tx_shift<=tx_data; rx_shift<=0; mosi<=tx_data[63];
                    if (cs_gyro) cs_gyro_o<=0; else cs_accel<=0;
                end
            end else if (tick) begin
                divcnt<=0;
                if (!sck) begin
                    sck<=1; rx_shift<={rx_shift[62:0],miso};
                end else begin
                    sck<=0;
                    tx_shift<={tx_shift[62:0],1'b0};
                    if (bits==7) begin
                        bits<=0;
                        if (byte_count==nbytes-1) begin
                            busy<=0; done<=1; rx_data<=rx_shift;
                            cs_accel<=1; cs_gyro_o<=1; mosi<=0;
                        end else begin
                            byte_count<=byte_count+1'b1;
                            mosi<=tx_shift[55];
                        end
                    end else begin
                        bits<=bits+1'b1; mosi<=tx_shift[62];
                    end
                end
            end else divcnt<=divcnt+1'b1;
        end
    end
endmodule
