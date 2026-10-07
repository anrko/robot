`timescale 1ns/1ps

module tb_attitude_osd_rgb565;
    reg  [11:0] pixel_x;
    reg  [11:0] pixel_y;
    reg  [15:0] pixel_in;
    reg  [15:0] roll_bcd;
    reg         roll_negative;
    reg  [15:0] pitch_bcd;
    reg         pitch_negative;
    reg  [15:0] yaw_bcd;
    reg         yaw_negative;
    wire [15:0] pixel_out;

    attitude_osd_rgb565 dut (
        .pixel_x(pixel_x), .pixel_y(pixel_y), .pixel_in(pixel_in),
        .roll_bcd(roll_bcd), .roll_negative(roll_negative),
        .pitch_bcd(pitch_bcd), .pitch_negative(pitch_negative),
        .yaw_bcd(yaw_bcd), .yaw_negative(yaw_negative),
        .pixel_out(pixel_out)
    );

    initial begin
        pixel_x = 12'd0;
        pixel_y = 12'd0;
        pixel_in = 16'hF800;
        roll_bcd = 16'h1234;
        roll_negative = 1'b0;
        pitch_bcd = 16'h0000;
        pitch_negative = 1'b1;
        yaw_bcd = 16'h0000;
        yaw_negative = 1'b0;
        #1;
        if (pixel_out !== 16'hF800) $fatal(1, "camera pixel outside panel changed");

        pixel_x = 12'd30;
        pixel_y = 12'd30;
        #1;
        if (pixel_out !== 16'h7820) $fatal(1, "translucent panel blend mismatch");

        // Accent edge pixel at the top-left HUD corner.
        pixel_x = 12'd25;
        pixel_y = 12'd25;
        #1;
        if (pixel_out !== 16'h5EFF) $fatal(1, "HUD accent edge missing");

        // The hundreds digit is 1 for BCD 1234; its top-center pixel is lit.
        pixel_x = 12'd166;
        pixel_y = 12'd55;
        #1;
        if (pixel_out !== 16'hFFDF) $fatal(1, "dynamic angle digit missing");

        // Center stroke of the minus sign on the PITCH line.
        pixel_x = 12'd150;
        pixel_y = 12'd84;
        #1;
        if (pixel_out !== 16'hFFDF) $fatal(1, "negative sign glyph missing");

        $display("attitude_osd_rgb565 test passed");
        $finish;
    end
endmodule
