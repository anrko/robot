`timescale 1ns/1ps

module tb_robotapb_dm_capture;
    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg reset = 1'b1;
    reg [11:0] addr = 12'd0;
    reg psel = 1'b0, penable = 1'b0, pwrite = 1'b0;
    reg [31:0] pwdata = 32'd0;
    wire [31:0] prdata;
    reg can0_rx_valid = 1'b0, can0_rx_last = 1'b0;
    reg [7:0] can0_rx_data = 8'd0;
    reg [28:0] can0_rx_id = 29'd0;
    reg can0_rx_ide = 1'b0;
    integer i, motor;
    reg [7:0] frame [0:7];

    RobotApb dut (
        .io_apb_PADDR(addr), .io_apb_PSEL(psel), .io_apb_PENABLE(penable),
        .io_apb_PREADY(), .io_apb_PWRITE(pwrite), .io_apb_PWDATA(pwdata),
        .io_apb_PRDATA(prdata), .io_apb_PSLVERROR(),
        .io_mainClk(clk), .resetCtrl_systemReset(reset),
        .io_imu_roll_d10(16'sd0), .io_imu_pitch_d10(16'sd0), .io_imu_yaw_d10(16'sd0),
        .io_imu_ax_raw(16'sd0), .io_imu_ay_raw(16'sd0), .io_imu_az_raw(16'sd0),
        .io_imu_gx_raw(16'sd0), .io_imu_gy_raw(16'sd0), .io_imu_gz_raw(16'sd0),
        .io_imu_sample_valid(1'b0), .io_imu_init_done(1'b0),
        .io_can0_tx_valid(), .io_can0_tx_data(), .io_can0_tx_id(),
        .io_can0_tx_enable(), .io_can0_tx_ready(1'b1), .io_can0_rx_seen(1'b0),
        .io_can0_rx_valid(can0_rx_valid), .io_can0_rx_last(can0_rx_last),
        .io_can0_rx_data(can0_rx_data), .io_can0_rx_id(can0_rx_id), .io_can0_rx_ide(can0_rx_ide),
        .io_can0_tx_ack_event(1'b0), .io_can0_tx_fail_event(1'b0),
        .io_can1_tx_valid(), .io_can1_tx_data(), .io_can1_tx_id(),
        .io_can1_tx_enable(), .io_can1_tx_ready(1'b1), .io_can1_rx_seen(1'b0),
        .io_can1_rx_valid(1'b0), .io_can1_rx_last(1'b0), .io_can1_rx_data(8'd0),
        .io_can1_rx_id(29'd0), .io_can1_rx_ide(1'b0),
        .io_can1_tx_ack_event(1'b0), .io_can1_tx_fail_event(1'b0)
    );

    task read_expect;
        input [11:0] register_addr;
        input [31:0] expected;
        begin
            addr = register_addr;
            #1;
            if (prdata !== expected) begin
                $display("FAIL addr=%03x expected=%08x got=%08x", register_addr, expected, prdata);
                $fatal(1);
            end
        end
    endtask

    initial begin
        frame[0] = 8'h00; // Master ID 0 parameter/feedback response
        frame[1] = 8'h00;
        frame[2] = 8'h33;
        frame[3] = 8'h08;
        frame[4] = 8'h00;
        frame[5] = 8'h00;
        frame[6] = 8'h00;
        frame[7] = 8'h00;
        repeat (3) @(posedge clk);
        reset <= 1'b0;
        @(posedge clk);

        for (motor = 1; motor <= 4; motor = motor + 1) begin
            frame[0] = motor[3:0];
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge clk);
                can0_rx_valid = 1'b1;
                can0_rx_last = (i == 7);
                can0_rx_data = frame[i];
                can0_rx_id = 29'h000;
                can0_rx_ide = 1'b0;
            end
            @(negedge clk);
            can0_rx_valid = 1'b0;
            can0_rx_last = 1'b0;
            @(posedge clk);
            read_expect(12'h0E0 + ((motor - 1) * 12), 32'd1);
            read_expect(12'h0E4 + ((motor - 1) * 12), {motor[7:0], 24'h00_33_08});
            read_expect(12'h0E8 + ((motor - 1) * 12), 32'h0000_0000);
        end

        // Extended frames and a different standard CAN ID must not be classified as DM replies.
        @(negedge clk);
        can0_rx_valid = 1'b1;
        can0_rx_last = 1'b1;
        can0_rx_data = 8'h00;
        can0_rx_id = 29'h000;
        can0_rx_ide = 1'b1;
        @(negedge clk);
        can0_rx_ide = 1'b0;
        can0_rx_id = 29'h123;
        @(negedge clk);
        can0_rx_valid = 1'b0;
        can0_rx_last = 1'b0;
        read_expect(12'h0E0, 32'd1);
        read_expect(12'h0EC, 32'd1);
        read_expect(12'h0F8, 32'd1);
        read_expect(12'h104, 32'd1);
        $display("PASS: CAN0 Master-ID-0 standard responses classify by D0[3:0] into DM IDs 1..4");
        $finish;
    end
endmodule
