// DDR/FIFO-free RGMII debug sender.  The 125 MHz domain generates one
// complete RGB565 color-bar line directly, so this first link test needs no
// frame buffer or large on-chip RAM.
module rgb565_udp_sender #(
    parameter [47:0] DST_MAC = 48'hffff_ffff_ffff,
    parameter [47:0] SRC_MAC = 48'h000a_3501_fec0,
    parameter [31:0] DST_IP  = 32'hc0a8_0003,
    parameter [31:0] SRC_IP  = 32'hc0a8_0002,
    parameter [15:0] DST_PORT = 16'd6102,
    parameter [15:0] SRC_PORT = 16'd5000
) (
    input clk50, input rst_n, input [15:0] pixel_data,
    input pixel_valid, output rgmii_tx_clk, output [3:0] rgmii_txd,
    output rgmii_tx_ctl
);
wire gmii_clk, pll_lock, tx_done, payload_req;
wire [7:0] gmii_txd;
wire gmii_txen;
reg tx_start, tx_done_d, started;
reg [11:0] payload_count;
reg [15:0] bar_pixel;
wire reset_p = ~rst_n | ~pll_lock;

rgmii_pll u_pll(.clkin(clk50), .reset(~rst_n), .clkout(gmii_clk), .lock(pll_lock));

// One UDP payload is one 1280-pixel line = 2560 bytes.  The receiver treats
// 720 consecutive packets as one 1280x720 frame.
always @(posedge gmii_clk or posedge reset_p) begin
    if (reset_p) begin
        tx_start <= 1'b0; tx_done_d <= 1'b0; started <= 1'b0;
        payload_count <= 12'd0;
    end else begin
        tx_done_d <= tx_done;
        tx_start <= 1'b0;
        if (!started) begin
            tx_start <= 1'b1;
            started <= 1'b1;
        end else if (tx_done_d) begin
            tx_start <= 1'b1;
        end
        if (payload_req) begin
            if (payload_count == 12'd2559) payload_count <= 12'd0;
            else payload_count <= payload_count + 1'b1;
        end else if (!tx_start) begin
            payload_count <= 12'd0;
        end
    end
end

always @* begin
    case (payload_count[11:1] / 8'd160)
        3'd0: bar_pixel = 16'hf800; // red
        3'd1: bar_pixel = 16'hfc60; // orange
        3'd2: bar_pixel = 16'hffe0; // yellow
        3'd3: bar_pixel = 16'h07e0; // green
        3'd4: bar_pixel = 16'h07ff; // cyan
        3'd5: bar_pixel = 16'h001f; // blue
        3'd6: bar_pixel = 16'h801f; // violet
        default: bar_pixel = 16'hffff; // white
    endcase
end

eth_udp_tx_gmii u_udp (
    .clk125m(gmii_clk), .reset_p(reset_p), .tx_en_pulse(tx_start),
    .tx_done(tx_done), .dst_mac(DST_MAC), .src_mac(SRC_MAC),
    .dst_ip(DST_IP), .src_ip(SRC_IP), .dst_port(DST_PORT), .src_port(SRC_PORT),
    .data_length(16'd2560), .payload_req_o(payload_req),
    .payload_dat_i(payload_count[0] ? bar_pixel[15:8] : bar_pixel[7:0]),
    .gmii_tx_clk(), .gmii_txen(gmii_txen), .gmii_txd(gmii_txd));

gmii_to_rgmii u_rgmii (
    .reset_n(rst_n & pll_lock), .gmii_tx_clk(gmii_clk), .gmii_txd(gmii_txd),
    .gmii_txen(gmii_txen), .gmii_txer(1'b0), .rgmii_tx_clk(rgmii_tx_clk),
    .rgmii_txd(rgmii_txd), .rgmii_txen(rgmii_tx_ctl));
endmodule
