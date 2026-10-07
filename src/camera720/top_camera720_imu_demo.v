// Same board pins as top_camera720. Displays SYNTHETIC samples through real RTL.
module top_camera720_imu_demo (
    input clk50m,output [7:0] state_led,
    output rgmii_tx_clk,output [3:0] rgmii_txd,output rgmii_tx_ctl,
    output cam_scl,inout cam_sda,output cam_rst_n,output cam_xclk,
    input cam_pclk,input cam_href,input cam_vsync,input [7:0] cam_data
);
    top_camera720 #(.IMU_DEMO(1)) u_board(
        .clk50m(clk50m),.state_led(state_led),.rgmii_tx_clk(rgmii_tx_clk),
        .rgmii_txd(rgmii_txd),.rgmii_tx_ctl(rgmii_tx_ctl),.cam_scl(cam_scl),.cam_sda(cam_sda),
        .cam_rst_n(cam_rst_n),.cam_xclk(cam_xclk),.cam_pclk(cam_pclk),
        .cam_href(cam_href),.cam_vsync(cam_vsync),.cam_data(cam_data));
endmodule
