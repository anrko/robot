// Convert BMI088 raw counts to the Q8.24 physical units expected by
// madgwick_imu: acceleration in g, angular rate in rad/s.
// Configuration in bmi088_spi is +/-6 g and +/-1000 dps.
module bmi088_q24 (
    input wire signed [15:0] ax_raw, ay_raw, az_raw,
    input wire signed [15:0] gx_raw, gy_raw, gz_raw,
    output wire signed [31:0] ax, ay, az, wx, wy, wz,
    output wire [31:0] dt_q24
);
    // 2^24 * 6 / 32768 = 3072 counts per accelerometer LSB.
    assign ax = $signed(ax_raw) * 32'sd3072;
    assign ay = $signed(ay_raw) * 32'sd3072;
    assign az = $signed(az_raw) * 32'sd3072;
    // round(2^24*pi/(180*32.768)) = 8936 counts per gyro LSB.
    assign wx = $signed(gx_raw) * 32'sd8936;
    assign wy = $signed(gy_raw) * 32'sd8936;
    assign wz = $signed(gz_raw) * 32'sd8936;
    // 100 Hz sample period, in Q0.24 seconds.
    assign dt_q24 = 32'd167772;
endmodule
