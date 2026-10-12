module top_camera720 #(parameter IMU_DEMO=0) (
    input        clk50m,
    output [7:0] state_led,
    output       rgmii_tx_clk,
    output [3:0] rgmii_txd,
    output       rgmii_tx_ctl,
    output       cam_scl,
    inout        cam_sda,
    output       cam_rst_n,
    input        cam_pclk,
    input        cam_href,
    input        cam_vsync,
    input  [7:0] cam_data,
    output       bmi_sclk,
    output       bmi_mosi,
    input        bmi_miso,
    output       bmi_csb1,
    output       bmi_csb2,
    input        bmi_int1,
    input        bmi_int3,
    output       imu_uart_tx,
    output wire signed [15:0] imu_roll_d10,
    output wire signed [15:0] imu_pitch_d10,
    output wire signed [15:0] imu_yaw_d10,
    output wire signed [15:0] bmi_ax_raw_out,
    output wire signed [15:0] bmi_ay_raw_out,
    output wire signed [15:0] bmi_az_raw_out,
    output wire signed [15:0] bmi_gx_raw_out,
    output wire signed [15:0] bmi_gy_raw_out,
    output wire signed [15:0] bmi_gz_raw_out,
    output wire bmi_sample_valid_out,
    output wire bmi_init_done_out
);
    wire [15:0] af_status;
    wire camera_init_done;
    wire cam_pwdn_unused;
    wire eth_mdc_unused;
    wire eth_mdio_unused;
    wire eth_rst_n_unused;
    reg [25:0] heartbeat;
    wire imu_reset_n,attitude_valid,attitude_ready;
    wire [50:0] attitude_payload;
    wire signed [15:0] imu_roll_d10_i,imu_pitch_d10_i,imu_yaw_d10_i;
    reg [1:0] imu_reset_sync;
    always @(posedge clk50m or negedge imu_reset_n)
        if(!imu_reset_n) imu_reset_sync<=0;
        else imu_reset_sync<={imu_reset_sync[0],1'b1};
    wire bmi_sample_valid, bmi_init_done;
    wire signed [15:0] bmi_ax_raw,bmi_ay_raw,bmi_az_raw,bmi_gx_raw,bmi_gy_raw,bmi_gz_raw;
    wire signed [31:0] bmi_ax,bmi_ay,bmi_az,bmi_wx,bmi_wy,bmi_wz;
    wire [31:0] bmi_dt_q24;
    wire [7:0] bmi_accel_id,bmi_gyro_id;
    bmi088_spi u_bmi088(.clk(clk50m),.rst_n(imu_reset_sync[1]),
        .spi_sclk(bmi_sclk),.spi_mosi(bmi_mosi),.spi_miso(bmi_miso),
        .spi_csb1(bmi_csb1),.spi_csb2(bmi_csb2),.int1(bmi_int1),.int3(bmi_int3),
        .sample_valid(bmi_sample_valid),.ax(bmi_ax_raw),.ay(bmi_ay_raw),.az(bmi_az_raw),
        .gx(bmi_gx_raw),.gy(bmi_gy_raw),.gz(bmi_gz_raw),.init_done(bmi_init_done),
        .accel_id(bmi_accel_id),.gyro_id(bmi_gyro_id));
    bmi088_q24 u_bmi_q24(.ax_raw(bmi_ax_raw),.ay_raw(bmi_ay_raw),.az_raw(bmi_az_raw),
        .gx_raw(bmi_gx_raw),.gy_raw(bmi_gy_raw),.gz_raw(bmi_gz_raw),
        .ax(bmi_ax),.ay(bmi_ay),.az(bmi_az),.wx(bmi_wx),.wy(bmi_wy),.wz(bmi_wz),
        .dt_q24(bmi_dt_q24));
    generate if(IMU_DEMO) begin : g_imu_demo
        wire sample_valid,sample_ready;
        wire signed [31:0] ax,ay,az,wx,wy,wz;
        wire [31:0] dt;
        imu_demo_source u_samples(.clk(clk50m),.rst_n(imu_reset_sync[1]),
            .valid(sample_valid),.ready(sample_ready),.ax(ax),.ay(ay),.az(az),
            .wx(wx),.wy(wy),.wz(wz),.dt_q24(dt));
        attitude_pipeline u_attitude(.clk(clk50m),.rst_n(imu_reset_sync[1]),
            .sample_valid(sample_valid),.sample_ready(sample_ready),.ax(ax),.ay(ay),.az(az),
            .wx(wx),.wy(wy),.wz(wz),.dt_q24(dt),.attitude_valid(attitude_valid),
            .attitude_ready(attitude_ready),.attitude_payload(attitude_payload),
            .roll_d10(imu_roll_d10_i),.pitch_d10(imu_pitch_d10_i),.yaw_d10(imu_yaw_d10_i));
    end else begin : g_imu_bmi088
        wire bmi_ready;
        attitude_pipeline u_attitude(.clk(clk50m),.rst_n(imu_reset_sync[1]),
            .sample_valid(bmi_sample_valid),.sample_ready(bmi_ready),
            .ax(bmi_ax),.ay(bmi_ay),.az(bmi_az),.wx(bmi_wx),.wy(bmi_wy),.wz(bmi_wz),
            .dt_q24(bmi_dt_q24),.attitude_valid(attitude_valid),
            .attitude_ready(attitude_ready),.attitude_payload(attitude_payload),
            .roll_d10(imu_roll_d10_i),.pitch_d10(imu_pitch_d10_i),.yaw_d10(imu_yaw_d10_i));
    end endgenerate

    generate if(IMU_DEMO) begin : g_uart_disabled
        assign imu_uart_tx = 1'b1;
    end else begin : g_uart_telemetry
        bmi088_telemetry_uart u_telemetry(
            .clk(clk50m),.rst_n(imu_reset_sync[1]),.sample_valid(bmi_sample_valid),
            .ax(bmi_ax_raw),.ay(bmi_ay_raw),.az(bmi_az_raw),
            .gx(bmi_gx_raw),.gy(bmi_gy_raw),.gz(bmi_gz_raw),
            .attitude_valid(attitude_valid),.attitude_ready(attitude_ready),
            .roll_d10(imu_roll_d10_i),.pitch_d10(imu_pitch_d10_i),.yaw_d10(imu_yaw_d10_i),
            .uart_tx(imu_uart_tx));
    end endgenerate

    ov5640_udp_rgmii #(
        .IMAGE_WIDTH(1280),
        .IMAGE_HEIGHT(720),
        .DST_MAC(48'hff_ff_ff_ff_ff_ff),
        .SRC_MAC(48'h00_0a_35_01_fe_c0),
        .DST_IP(32'hc0_a8_00_03),
        .SRC_IP(32'hc0_a8_00_02),
        .DST_PORT(16'd6102),
        .SRC_PORT(16'd5000),
        .OSD_DEMO(IMU_DEMO)
    ) u_camera (
        .af_status(af_status), .clk50m(clk50m), .reset_n(1'b1),
        .imu_reset_n(imu_reset_n),.attitude_valid(attitude_valid),
        .attitude_ready(attitude_ready),.attitude_payload(attitude_payload),
        .rgmii_gtxc(rgmii_tx_clk), .rgmii_txd(rgmii_txd), .rgmii_txen(rgmii_tx_ctl),
        .eth_mdc(eth_mdc_unused), .eth_mdio(eth_mdio_unused), .eth_rst_n(eth_rst_n_unused),
        .camera_sclk(cam_scl), .camera_sdat(cam_sda), .camera_vsync(cam_vsync),
        // DOUBLE-DVP-OV5640 U27 supplies XCLK locally. J17-13 is CAM1 D2.
        .camera_href(cam_href), .camera_pclk(cam_pclk), .camera_xclk(),
        .camera_data(cam_data), .camera_pwdn(cam_pwdn_unused), .camera_rst_n(cam_rst_n),
        .led(camera_init_done)
    );

    always @(posedge clk50m) heartbeat <= heartbeat + 1'b1;
    // Carrier schematic page 8: LEDs have grounded cathodes (active high).
    // LED0: initialization done; LED7: heartbeat; LED1..6: off.
    assign state_led = {heartbeat[25], 5'b00000, bmi_init_done, camera_init_done};
    // Export the already-calculated IMU values to the soft-core MMIO bridge.
    assign imu_roll_d10      = imu_roll_d10_i;
    assign imu_pitch_d10     = imu_pitch_d10_i;
    assign imu_yaw_d10       = imu_yaw_d10_i;
    assign bmi_ax_raw_out    = bmi_ax_raw;
    assign bmi_ay_raw_out    = bmi_ay_raw;
    assign bmi_az_raw_out    = bmi_az_raw;
    assign bmi_gx_raw_out    = bmi_gx_raw;
    assign bmi_gy_raw_out    = bmi_gy_raw;
    assign bmi_gz_raw_out    = bmi_gz_raw;
    assign bmi_sample_valid_out = bmi_sample_valid;
    assign bmi_init_done_out = bmi_init_done;
endmodule
