module top_camera720 #(parameter IMU_DEMO=0) (
    input        clk50m,
    output [7:0] state_led,
    output       rgmii_tx_clk,
    output [3:0] rgmii_txd,
    output       rgmii_tx_ctl,
    output       cam_scl,
    inout        cam_sda,
    output       cam_rst_n,
    output       cam_xclk,
    input        cam_pclk,
    input        cam_href,
    input        cam_vsync,
    input  [7:0] cam_data
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
    reg [1:0] imu_reset_sync;
    always @(posedge clk50m or negedge imu_reset_n)
        if(!imu_reset_n) imu_reset_sync<=0;
        else imu_reset_sync<={imu_reset_sync[0],1'b1};
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
            .attitude_ready(attitude_ready),.attitude_payload(attitude_payload));
    end else begin : g_imu_placeholder
        assign attitude_valid=1'b0;
        assign attitude_payload=51'd0;
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
        .camera_href(cam_href), .camera_pclk(cam_pclk), .camera_xclk(cam_xclk),
        .camera_data(cam_data), .camera_pwdn(cam_pwdn_unused), .camera_rst_n(cam_rst_n),
        .led(camera_init_done)
    );

    always @(posedge clk50m) heartbeat <= heartbeat + 1'b1;
    // LED0: initialization done (active-low board LED); LED7 heartbeat.
    assign state_led = {~heartbeat[25], 6'b111111, ~camera_init_done};
endmodule
