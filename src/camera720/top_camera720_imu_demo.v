// Same board pins as top_camera720. Displays SYNTHETIC samples through real RTL.
module top_camera720_imu_demo (
    input clk50m,output [7:0] state_led,
    output rgmii_tx_clk,output [3:0] rgmii_txd,output rgmii_tx_ctl,
    output cam_scl,inout cam_sda,output cam_rst_n,
    input cam_pclk,input cam_href,input cam_vsync,input [7:0] cam_data,
    output bmi_sclk,output bmi_mosi,input bmi_miso,output bmi_csb1,output bmi_csb2,
    input bmi_int1,input bmi_int3,output imu_uart_tx
);
    top_camera720 #(.IMU_DEMO(1)) u_board(
        .clk50m(clk50m),.state_led(state_led),.rgmii_tx_clk(rgmii_tx_clk),
        .rgmii_txd(rgmii_txd),.rgmii_tx_ctl(rgmii_tx_ctl),.cam_scl(cam_scl),.cam_sda(cam_sda),
        .cam_rst_n(cam_rst_n),.cam_pclk(cam_pclk),
        .cam_href(cam_href),.cam_vsync(cam_vsync),.cam_data(cam_data),
        .bmi_sclk(bmi_sclk),.bmi_mosi(bmi_mosi),.bmi_miso(bmi_miso),
        .bmi_csb1(bmi_csb1),.bmi_csb2(bmi_csb2),.bmi_int1(bmi_int1),.bmi_int3(bmi_int3),
        .imu_uart_tx(imu_uart_tx));
endmodule
