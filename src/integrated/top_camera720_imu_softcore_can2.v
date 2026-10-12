// Integrated ACG138 target:
//   * OV5640 720p UDP video with the existing attitude OSD
//   * BMI088 SPI acquisition and FPGA Madgwick pipeline
//   * Murax/VexRiscv RV32IM soft CPU on the USB_DEBUG UART
//   * two independent classic-CAN controllers on P7
//
// The CPU and CAN/IMU blocks are intentionally connected as separate bring-up
// blocks in this first integration.  The CPU still runs the validated demo
// image; no motor command is generated until a checked MMIO bridge is added.
module top_camera720_imu_softcore_can2 (
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
    output       uart_txd,
    input        uart_rxd,
    output       can0_tx,
    input        can0_rx,
    output       can1_tx,
    input        can1_rx
);
    wire [7:0] camera_led;
    wire imu_uart_unused;
    wire signed [15:0] imu_roll_d10, imu_pitch_d10, imu_yaw_d10;
    wire signed [15:0] bmi_ax_raw, bmi_ay_raw, bmi_az_raw;
    wire signed [15:0] bmi_gx_raw, bmi_gy_raw, bmi_gz_raw;
    wire bmi_sample_valid, bmi_init_done;

    // Existing camera/real-BMI088 path. Its telemetry UART is deliberately
    // left unused because USB_DEBUG is now owned by the soft CPU console.
    top_camera720 #(.IMU_DEMO(0)) u_camera (
        .clk50m(clk50m), .state_led(camera_led),
        .rgmii_tx_clk(rgmii_tx_clk), .rgmii_txd(rgmii_txd),
        .rgmii_tx_ctl(rgmii_tx_ctl), .cam_scl(cam_scl), .cam_sda(cam_sda),
        .cam_rst_n(cam_rst_n), .cam_pclk(cam_pclk), .cam_href(cam_href),
        .cam_vsync(cam_vsync), .cam_data(cam_data),
        .bmi_sclk(bmi_sclk), .bmi_mosi(bmi_mosi), .bmi_miso(bmi_miso),
        .bmi_csb1(bmi_csb1), .bmi_csb2(bmi_csb2),
        .bmi_int1(bmi_int1), .bmi_int3(bmi_int3),
        .imu_uart_tx(imu_uart_unused),
        .imu_roll_d10(imu_roll_d10), .imu_pitch_d10(imu_pitch_d10), .imu_yaw_d10(imu_yaw_d10),
        .bmi_ax_raw_out(bmi_ax_raw), .bmi_ay_raw_out(bmi_ay_raw), .bmi_az_raw_out(bmi_az_raw),
        .bmi_gx_raw_out(bmi_gx_raw), .bmi_gy_raw_out(bmi_gy_raw), .bmi_gz_raw_out(bmi_gz_raw),
        .bmi_sample_valid_out(bmi_sample_valid), .bmi_init_done_out(bmi_init_done)
    );

    // Murax has its own power-on reset. JTAG is tied to an idle TAP exactly as
    // in the standalone validated target. GPIO is kept local for now.
    wire [31:0] cpu_gpio_write;
    wire [31:0] cpu_gpio_oe;
    wire [11:0] robot_paddr;
    wire robot_psel, robot_penable, robot_pwrite, robot_pready, robot_pslverror;
    wire [31:0] robot_pwdata, robot_prdata;
    wire cpu_system_reset;
    wire can0_cpu_tx_valid, can1_cpu_tx_valid;
    wire [63:0] can0_cpu_tx_data, can1_cpu_tx_data;
    wire [10:0] can0_cpu_tx_id, can1_cpu_tx_id;
    wire can0_cpu_tx_enable, can1_cpu_tx_enable;
    wire can0_tx_ready, can1_tx_ready;
    wire can0_rx_valid, can1_rx_valid;
    wire can0_rx_last, can1_rx_last;
    wire [7:0] can0_rx_data, can1_rx_data;
    wire [28:0] can0_rx_id, can1_rx_id;
    wire can0_rx_ide, can1_rx_ide;
    wire can0_rx_seen, can1_rx_seen;
    wire can0_ack, can1_ack, can0_fail, can1_fail;
    Murax #(.ROBOT_APB_ENABLE(1)) u_cpu (
        .io_mainClk           (clk50m),
        .io_asyncReset        (1'b0),
        .io_jtag_tck          (clk50m),
        .io_jtag_tdi          (1'b0),
        .io_jtag_tms          (1'b0),
        .io_jtag_tdo          (),
        .io_gpioA_read        (32'h00000000),
        .io_gpioA_write       (cpu_gpio_write),
        .io_gpioA_writeEnable (cpu_gpio_oe),
        .io_uart_txd          (uart_txd),
        .io_uart_rxd          (uart_rxd),
        .io_robot_PADDR       (robot_paddr), .io_robot_PSEL(robot_psel),
        .io_robot_PENABLE    (robot_penable), .io_robot_PWRITE(robot_pwrite),
        .io_robot_PWDATA     (robot_pwdata), .io_robot_PREADY(robot_pready),
        .io_robot_PRDATA     (robot_prdata), .io_robot_PSLVERROR(robot_pslverror),
        .io_systemReset       (cpu_system_reset)
    );

    RobotApb u_robot_apb (
        .io_apb_PADDR(robot_paddr), .io_apb_PSEL(robot_psel), .io_apb_PENABLE(robot_penable),
        .io_apb_PREADY(robot_pready), .io_apb_PWRITE(robot_pwrite), .io_apb_PWDATA(robot_pwdata),
        .io_apb_PRDATA(robot_prdata), .io_apb_PSLVERROR(robot_pslverror),
        .io_mainClk(clk50m), .resetCtrl_systemReset(cpu_system_reset),
        .io_imu_roll_d10(imu_roll_d10), .io_imu_pitch_d10(imu_pitch_d10), .io_imu_yaw_d10(imu_yaw_d10),
        .io_imu_ax_raw(bmi_ax_raw), .io_imu_ay_raw(bmi_ay_raw), .io_imu_az_raw(bmi_az_raw),
        .io_imu_gx_raw(bmi_gx_raw), .io_imu_gy_raw(bmi_gy_raw), .io_imu_gz_raw(bmi_gz_raw),
        .io_imu_sample_valid(bmi_sample_valid), .io_imu_init_done(bmi_init_done),
        .io_can0_tx_valid(can0_cpu_tx_valid), .io_can0_tx_data(can0_cpu_tx_data), .io_can0_tx_id(can0_cpu_tx_id), .io_can0_tx_enable(can0_cpu_tx_enable), .io_can0_tx_ready(can0_tx_ready), .io_can0_rx_seen(can0_rx_seen),
        .io_can0_rx_valid(can0_rx_valid), .io_can0_rx_last(can0_rx_last), .io_can0_rx_data(can0_rx_data),
        .io_can0_rx_id(can0_rx_id), .io_can0_rx_ide(can0_rx_ide),
        .io_can0_tx_ack_event(can0_ack), .io_can0_tx_fail_event(can0_fail),
        .io_can1_tx_valid(can1_cpu_tx_valid), .io_can1_tx_data(can1_cpu_tx_data), .io_can1_tx_id(can1_cpu_tx_id), .io_can1_tx_enable(can1_cpu_tx_enable), .io_can1_tx_ready(can1_tx_ready), .io_can1_rx_seen(can1_rx_seen),
        .io_can1_rx_valid(can1_rx_valid), .io_can1_rx_last(can1_rx_last), .io_can1_rx_data(can1_rx_data),
        .io_can1_rx_id(can1_rx_id), .io_can1_rx_ide(can1_rx_ide),
        .io_can1_tx_ack_event(can1_ack), .io_can1_tx_fail_event(can1_fail)
    );

    reg [2:0] can_reset_shift;
    reg [25:0] heartbeat;
    reg can0_rx_seen_reg, can1_rx_seen_reg;
    // This top level has no external reset pin.  Give the bring-up state
    // deterministic FPGA power-up values; otherwise the CAN reset and LED
    // heartbeat would remain X in simulation and on devices without a
    // guaranteed register initialization value.
    initial begin
        can_reset_shift = 3'b000;
        heartbeat       = 26'd0;
        can0_rx_seen_reg = 1'b0;
        can1_rx_seen_reg = 1'b0;
    end
    always @(posedge clk50m) begin
        can_reset_shift <= {can_reset_shift[1:0], 1'b1};
        heartbeat <= heartbeat + 1'b1;
        if (!can_reset_shift[2]) begin
            can0_rx_seen_reg <= 1'b0;
            can1_rx_seen_reg <= 1'b0;
        end else begin
            if (can0_rx_valid) can0_rx_seen_reg <= 1'b1;
            if (can1_rx_valid) can1_rx_seen_reg <= 1'b1;
        end
    end
    wire can_rstn = can_reset_shift[2];

    // Both channels are receive-capable. Firmware leaves both TX queues
    // disabled until explicitly keyed; CAN1 is reserved here for the C620
    // bus, where 0x200 is the command frame for motor IDs 1-4.
    assign can0_rx_seen = can0_rx_seen_reg;
    assign can1_rx_seen = can1_rx_seen_reg;
    can_top #(
        // DM parameter access uses the broadcast request ID 0x7FF;
        // feedback replies use the configured Master ID (currently 0).
        .LOCAL_ID(11'h7ff), .TX_DLC(4'd8),
        .RX_ID_SHORT_FILTER(11'h000), .RX_ID_SHORT_MASK(11'h7ff),
        .RX_ID_LONG_FILTER(29'h0), .RX_ID_LONG_MASK(29'h1fffffff),
        .default_c_PTS(16'd34), .default_c_PBS1(16'd5), .default_c_PBS2(16'd10)
    ) u_can0 (
        .rstn(can_rstn), .clk(clk50m), .tx_id(can0_cpu_tx_id), .can_rx(can0_rx), .can_tx(can0_tx),
        .tx_valid(can0_cpu_tx_valid), .tx_ready(can0_tx_ready), .tx_data(can0_cpu_tx_data),
        .rx_valid(can0_rx_valid), .rx_last(can0_rx_last), .rx_data(can0_rx_data),
        .rx_id(can0_rx_id), .rx_ide(can0_rx_ide),
        .tx_ack_event(can0_ack), .tx_fail_event(can0_fail)
    );

    can_top #(
        .LOCAL_ID(11'h200), .TX_DLC(4'd8),
        .RX_ID_SHORT_FILTER(11'h200), .RX_ID_SHORT_MASK(11'h7f8),
        .RX_ID_LONG_FILTER(29'h0), .RX_ID_LONG_MASK(29'h1fffffff),
        .default_c_PTS(16'd34), .default_c_PBS1(16'd5), .default_c_PBS2(16'd10)
    ) u_can1 (
        .rstn(can_rstn), .clk(clk50m), .tx_id(can1_cpu_tx_id), .can_rx(can1_rx), .can_tx(can1_tx),
        .tx_valid(can1_cpu_tx_valid), .tx_ready(can1_tx_ready), .tx_data(can1_cpu_tx_data),
        .rx_valid(can1_rx_valid), .rx_last(can1_rx_last), .rx_data(can1_rx_data),
        .rx_id(can1_rx_id), .rx_ide(can1_rx_ide),
        .tx_ack_event(can1_ack), .tx_fail_event(can1_fail)
    );

    // LED0/1 retain camera and BMI init status; LED5/6 latch CAN RX activity;
    // LED7 is an independent heartbeat proving the integrated clock is alive.
    assign state_led = {heartbeat[25], can1_rx_seen, can0_rx_seen,
                        camera_led[4:2], camera_led[1], camera_led[0]};
endmodule
