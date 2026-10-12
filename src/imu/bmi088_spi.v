// BMI088 register controller, shared SPI bus with independent chip selects.
// clk is 50 MHz. The byte engine runs at about 2.08 MHz (SPI mode 0).
// CSB1 selects the accelerometer; CSB2 selects the gyroscope.
module bmi088_spi (
    input clk, input rst_n,
    output spi_sclk, output spi_mosi, input spi_miso,
    output spi_csb1, output spi_csb2,
    input int1, input int3,
    output reg sample_valid,
    output reg signed [15:0] ax, ay, az, gx, gy, gz,
    output reg init_done, output reg [7:0] accel_id, gyro_id
);
    localparam [4:0]
      S_GID_START=0, S_GID_WAIT=1, S_AID_START=2, S_AID_WAIT=3,
      S_ARST_START=4, S_ARST_WAIT=5, S_ARST_DELAY=6,
      S_APWR_START=7, S_APWR_WAIT=8, S_APWR_DELAY=9,
      S_ACONF_START=10, S_ACONF_WAIT=11, S_ARANGE_START=12,
      S_ARANGE_WAIT=13, S_GRANGE_START=14, S_GRANGE_WAIT=15,
      S_GBW_START=16, S_GBW_WAIT=17, S_READY=18,
      S_RUN_G_START=19, S_RUN_G_WAIT=20, S_RUN_A_START=21,
      S_RUN_A_WAIT=22, S_PERIOD=23;
    reg [4:0] state;
    reg launch, launch_gyro;
    reg [3:0] launch_len;
    reg [63:0] launch_tx;
    wire busy, done;
    wire [63:0] rx_data;
    reg [22:0] delay_count;
    reg [18:0] period_count;

    spi_byte_engine #(.DIV(12)) u_spi (
      .clk(clk), .rst_n(rst_n), .start(launch), .cs_gyro(launch_gyro),
      .length(launch_len), .tx_data(launch_tx), .rx_data(rx_data),
      .busy(busy), .done(done), .sck(spi_sclk), .mosi(spi_mosi),
      .miso(spi_miso), .cs_accel(spi_csb1), .cs_gyro_o(spi_csb2));

    // Transactions are MSB first. The first returned byte is a dummy byte;
    // read data therefore occupies the low bytes of rx_data.
    task automatic start_read(input [7:0] addr, input [3:0] len, input gyro);
      begin
        launch <= 1'b1; launch_gyro <= gyro; launch_len <= len;
        launch_tx <= {addr | 8'h80, 56'd0};
      end
    endtask
    task automatic start_write(input [7:0] addr, input [7:0] data, input gyro);
      begin
        launch <= 1'b1; launch_gyro <= gyro; launch_len <= 4'd2;
        launch_tx <= {addr, data, 48'd0};
      end
    endtask

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state <= S_GID_START;
        launch <= 1'b0; launch_gyro <= 1'b0; launch_len <= 0; launch_tx <= 0;
        delay_count <= 0; period_count <= 0;
        sample_valid <= 1'b0; init_done <= 1'b0;
        accel_id <= 0; gyro_id <= 0;
        ax <= 0; ay <= 0; az <= 0; gx <= 0; gy <= 0; gz <= 0;
      end else begin
        launch <= 1'b0; sample_valid <= 1'b0;
        case (state)
          S_GID_START: if (!busy) begin start_read(8'h00, 4'd2, 1'b1); state <= S_GID_WAIT; end
          S_GID_WAIT: if (done) begin
            gyro_id <= rx_data[7:0];
            state <= (rx_data[7:0] == 8'h0f) ? S_AID_START : S_GID_START;
          end
          // The first CSB1 transaction creates the required rising edge that
          // switches the accelerometer from its default I2C state to SPI.
          S_AID_START: if (!busy) begin start_read(8'h00, 4'd3, 1'b0); state <= S_AID_WAIT; end
          S_AID_WAIT: if (done) begin
            accel_id <= rx_data[7:0];
            state <= (rx_data[7:0] == 8'h1e) ? S_ARST_START : S_GID_START;
          end
          S_ARST_START: if (!busy) begin start_write(8'h7e, 8'hb6, 1'b0); state <= S_ARST_WAIT; end
          S_ARST_WAIT: if (done) begin delay_count <= 0; state <= S_ARST_DELAY; end
          S_ARST_DELAY: if (delay_count < 23'd100000) delay_count <= delay_count + 1'b1;
                        else state <= S_APWR_START;
          // ACC_PWR_CTRL=0x04: accelerometer normal measurement mode.
          S_APWR_START: if (!busy) begin start_write(8'h7d, 8'h04, 1'b0); state <= S_APWR_WAIT; end
          S_APWR_WAIT: if (done) begin delay_count <= 0; state <= S_APWR_DELAY; end
          S_APWR_DELAY: if (delay_count < 23'd25000) delay_count <= delay_count + 1'b1;
                        else state <= S_ACONF_START;
          // ACC_CONF=100 Hz, normal bandwidth; ACC_RANGE=+/-6 g.
          S_ACONF_START: if (!busy) begin start_write(8'h40, 8'ha8, 1'b0); state <= S_ACONF_WAIT; end
          S_ACONF_WAIT: if (done) state <= S_ARANGE_START;
          S_ARANGE_START: if (!busy) begin start_write(8'h41, 8'h01, 1'b0); state <= S_ARANGE_WAIT; end
          S_ARANGE_WAIT: if (done) state <= S_GRANGE_START;
          // GYR_RANGE=+/-1000 dps; GYR_BW=100 Hz / 32 Hz filter setting.
          S_GRANGE_START: if (!busy) begin start_write(8'h0f, 8'h01, 1'b1); state <= S_GRANGE_WAIT; end
          S_GRANGE_WAIT: if (done) state <= S_GBW_START;
          S_GBW_START: if (!busy) begin start_write(8'h10, 8'h07, 1'b1); state <= S_GBW_WAIT; end
          S_GBW_WAIT: if (done) begin init_done <= 1'b1; period_count <= 0; state <= S_READY; end
          S_READY: begin period_count <= 0; state <= S_RUN_G_START; end
          S_RUN_G_START: if (!busy) begin start_read(8'h02, 4'd7, 1'b1); state <= S_RUN_G_WAIT; end
          S_RUN_G_WAIT: if (done) begin
            gx <= {rx_data[39:32], rx_data[47:40]};
            gy <= {rx_data[23:16], rx_data[31:24]};
            gz <= {rx_data[7:0], rx_data[15:8]};
            state <= S_RUN_A_START;
          end
          // Accelerometer reads need address + dummy + six data bytes.
          S_RUN_A_START: if (!busy) begin start_read(8'h12, 4'd8, 1'b0); state <= S_RUN_A_WAIT; end
          S_RUN_A_WAIT: if (done) begin
            ax <= {rx_data[39:32], rx_data[47:40]};
            ay <= {rx_data[23:16], rx_data[31:24]};
            az <= {rx_data[7:0], rx_data[15:8]};
            sample_valid <= 1'b1; period_count <= 0; state <= S_PERIOD;
          end
          S_PERIOD: if (period_count < 19'd499999) period_count <= period_count + 1'b1;
                    else state <= S_RUN_G_START;
          default: state <= S_GID_START;
        endcase
      end
    end
endmodule
