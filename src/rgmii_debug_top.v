// DDR-free bring-up top level.
// 1280x720 RGB565 test pattern -> UDP -> GMII -> RGMII -> RK3588 GMAC1.
// This module is intentionally named top while the project is in debug mode;
// the original DDR design remains in src/top.v but is excluded from gowin.gprj.
module top (
    input        clk,
    input        rst_n,
    output [7:0] state_led,
    output       rgmii_tx_clk,
    output [3:0] rgmii_txd,
    output       rgmii_tx_ctl
);
wire tp_de, tp_hs, tp_vs;
wire [7:0] tp_r, tp_g, tp_b;
wire [15:0] pixel_rgb565 = {tp_r[7:3], tp_g[7:2], tp_b[7:3]};
reg [25:0] heartbeat;

testpattern u_testpattern (
    .I_pxl_clk  (clk), .I_rst_n(rst_n), .I_mode(3'b000),
    .I_single_r(8'hff), .I_single_g(8'hff), .I_single_b(8'hff),
    .I_h_total(12'd1650), .I_h_sync(12'd40), .I_h_bporch(12'd220),
    .I_h_res(12'd1280), .I_v_total(12'd750), .I_v_sync(12'd5),
    .I_v_bporch(12'd20), .I_v_res(12'd720), .I_hs_pol(1'b1),
    .I_vs_pol(1'b1), .O_de(tp_de), .O_hs(tp_hs), .O_vs(tp_vs),
    .O_data_r(tp_r), .O_data_g(tp_g), .O_data_b(tp_b)
);

rgb565_udp_sender u_sender (
    .clk50(clk), .rst_n(rst_n), .pixel_data(pixel_rgb565),
    .pixel_valid(tp_de), .rgmii_tx_clk(rgmii_tx_clk),
    .rgmii_txd(rgmii_txd), .rgmii_tx_ctl(rgmii_tx_ctl)
);

always @(posedge clk or negedge rst_n)
    if (!rst_n) heartbeat <= 26'd0;
    else heartbeat <= heartbeat + 26'd1;

// LEDs are active-low on the ACG138 board.  LED7 is a heartbeat.
assign state_led = {~heartbeat[25], 7'b1111111};
endmodule
