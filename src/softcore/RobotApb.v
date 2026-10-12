// APB register block for the robot-facing part of the integrated target.
// The default state is read-only/safe: CAN output stays disabled until the
// firmware writes the enable key, then explicitly commits a queued frame.
module RobotApb (
    input wire [11:0] io_apb_PADDR, input wire io_apb_PSEL,
    input wire io_apb_PENABLE, output wire io_apb_PREADY,
    input wire io_apb_PWRITE, input wire [31:0] io_apb_PWDATA,
    output reg [31:0] io_apb_PRDATA, output wire io_apb_PSLVERROR,
    input wire io_mainClk, input wire resetCtrl_systemReset,
    input wire signed [15:0] io_imu_roll_d10, io_imu_pitch_d10, io_imu_yaw_d10,
    input wire signed [15:0] io_imu_ax_raw, io_imu_ay_raw, io_imu_az_raw,
    input wire signed [15:0] io_imu_gx_raw, io_imu_gy_raw, io_imu_gz_raw,
    input wire io_imu_sample_valid, io_imu_init_done,
    output wire io_can0_tx_valid, output wire [63:0] io_can0_tx_data,
    output wire [10:0] io_can0_tx_id,
    output wire io_can0_tx_enable, input wire io_can0_tx_ready,
    input wire io_can0_rx_seen,
    input wire io_can0_rx_valid, input wire io_can0_rx_last,
    input wire [7:0] io_can0_rx_data, input wire [28:0] io_can0_rx_id,
    input wire io_can0_rx_ide,
    input wire io_can0_tx_ack_event, input wire io_can0_tx_fail_event,
    output wire io_can1_tx_valid, output wire [63:0] io_can1_tx_data,
    output wire [10:0] io_can1_tx_id,
    output wire io_can1_tx_enable, input wire io_can1_tx_ready,
    input wire io_can1_rx_seen,
    input wire io_can1_rx_valid, input wire io_can1_rx_last,
    input wire [7:0] io_can1_rx_data, input wire [28:0] io_can1_rx_id,
    input wire io_can1_rx_ide,
    input wire io_can1_tx_ack_event, input wire io_can1_tx_fail_event
);
    wire do_write = io_apb_PSEL && io_apb_PENABLE && io_apb_PWRITE;
    assign io_apb_PREADY = 1'b1;
    assign io_apb_PSLVERROR = 1'b0;

    reg [63:0] can0_data, can1_data;
    reg [10:0] can0_tx_id, can1_tx_id;
    reg can0_enable, can1_enable, can0_pending, can1_pending;
    reg [31:0] sample_count;
    reg [15:0] age_count;
    reg [63:0] can1_rx_shift, can1_id1_data, can1_id2_data;
    reg [31:0] can1_id1_count, can1_id2_count;
    reg [63:0] can0_rx_shift, can0_dm_last_data;
    reg [28:0] can0_dm_last_id;
    reg [31:0] can0_dm_rx_count, can0_tx_ack_count, can0_tx_fail_count;
    reg [63:0] can0_dm_id1_data, can0_dm_id2_data, can0_dm_id3_data, can0_dm_id4_data;
    reg [31:0] can0_dm_id1_count, can0_dm_id2_count, can0_dm_id3_count, can0_dm_id4_count;
    reg [31:0] can1_tx_ack_count, can1_tx_fail_count;

    // Offsets are relative to 0xF0030000.
    // 0x00 status: [0] IMU init, [1] sample valid, [2] CAN0 RX seen,
    //              [3] CAN1 RX seen, [4] CAN0 TX ready, [5] CAN1 TX ready
    // 0x04..0x0c attitude: signed tenths of a degree (roll/pitch/yaw)
    // 0x10..0x24 raw BMI088: ax ay az gx gy gz, signed 16-bit values
    // 0x28 sample count, 0x2c sample age in 50 MHz cycles (saturating)
    // 0x80 CAN0 control/data, 0x90 CAN1 control/data
    // 0xa0..0xb4 C620 CAN1 feedback counters and latest payloads for IDs 1/2
    // 0xb8/0xbc CAN1 acknowledged / failed TX counters
    // 0xc0..0xd8 latest CAN0 DM reply and TX ACK/fail
    // 0xe0..0x10c DM4310 feedback data/counters for motor IDs 1..4;
    //           feedback CAN ID is Master ID 0, motor ID is payload D0[3:0]
    always @(*) begin
        io_apb_PRDATA = 32'h0;
        case (io_apb_PADDR)
            12'h000: begin
                io_apb_PRDATA[0] = io_imu_init_done;
                io_apb_PRDATA[1] = io_imu_sample_valid;
                io_apb_PRDATA[2] = io_can0_rx_seen;
                io_apb_PRDATA[3] = io_can1_rx_seen;
                io_apb_PRDATA[4] = io_can0_tx_ready;
                io_apb_PRDATA[5] = io_can1_tx_ready;
                io_apb_PRDATA[16] = can0_enable;
                io_apb_PRDATA[17] = can1_enable;
                io_apb_PRDATA[18] = can0_pending;
                io_apb_PRDATA[19] = can1_pending;
            end
            12'h004: io_apb_PRDATA = {{16{io_imu_roll_d10[15]}}, io_imu_roll_d10};
            12'h008: io_apb_PRDATA = {{16{io_imu_pitch_d10[15]}}, io_imu_pitch_d10};
            12'h00c: io_apb_PRDATA = {{16{io_imu_yaw_d10[15]}}, io_imu_yaw_d10};
            12'h010: io_apb_PRDATA = {{16{io_imu_ax_raw[15]}}, io_imu_ax_raw};
            12'h014: io_apb_PRDATA = {{16{io_imu_ay_raw[15]}}, io_imu_ay_raw};
            12'h018: io_apb_PRDATA = {{16{io_imu_az_raw[15]}}, io_imu_az_raw};
            12'h01c: io_apb_PRDATA = {{16{io_imu_gx_raw[15]}}, io_imu_gx_raw};
            12'h020: io_apb_PRDATA = {{16{io_imu_gy_raw[15]}}, io_imu_gy_raw};
            12'h024: io_apb_PRDATA = {{16{io_imu_gz_raw[15]}}, io_imu_gz_raw};
            12'h028: io_apb_PRDATA = sample_count;
            12'h02c: io_apb_PRDATA = {16'h0, age_count};
            12'h080: begin io_apb_PRDATA[0] = can0_enable; io_apb_PRDATA[1] = can0_pending; io_apb_PRDATA[31:16] = 16'hC620; end
            12'h084: io_apb_PRDATA = can0_data[31:0];
            12'h088: io_apb_PRDATA = can0_data[63:32];
            12'h08c: io_apb_PRDATA = {21'h0, can0_tx_id};
            12'h090: begin io_apb_PRDATA[0] = can1_enable; io_apb_PRDATA[1] = can1_pending; io_apb_PRDATA[31:16] = 16'hC620; end
            12'h094: io_apb_PRDATA = can1_data[31:0];
            12'h098: io_apb_PRDATA = can1_data[63:32];
            12'h0a0: io_apb_PRDATA = can1_id1_count;
            12'h0a4: io_apb_PRDATA = can1_id1_data[63:32];
            12'h0a8: io_apb_PRDATA = can1_id1_data[31:0];
            12'h0ac: io_apb_PRDATA = can1_id2_count;
            12'h0b0: io_apb_PRDATA = can1_id2_data[63:32];
            12'h0b4: io_apb_PRDATA = can1_id2_data[31:0];
            12'h0b8: io_apb_PRDATA = can1_tx_ack_count;
            12'h0bc: io_apb_PRDATA = can1_tx_fail_count;
            12'h0c0: io_apb_PRDATA = can0_dm_rx_count;
            12'h0c4: io_apb_PRDATA = can0_dm_last_id[10:0];
            12'h0c8: io_apb_PRDATA = can0_dm_last_data[31:0];
            12'h0cc: io_apb_PRDATA = can0_dm_last_data[63:32];
            12'hd0: io_apb_PRDATA = {3'b0, can0_dm_last_id};
            12'hd4: io_apb_PRDATA = can0_tx_ack_count;
            12'hd8: io_apb_PRDATA = can0_tx_fail_count;
            12'he0: io_apb_PRDATA = can0_dm_id1_count;
            12'he4: io_apb_PRDATA = can0_dm_id1_data[63:32];
            12'he8: io_apb_PRDATA = can0_dm_id1_data[31:0];
            12'hec: io_apb_PRDATA = can0_dm_id2_count;
            12'hf0: io_apb_PRDATA = can0_dm_id2_data[63:32];
            12'hf4: io_apb_PRDATA = can0_dm_id2_data[31:0];
            12'hf8: io_apb_PRDATA = can0_dm_id3_count;
            12'hfc: io_apb_PRDATA = can0_dm_id3_data[63:32];
            12'h100: io_apb_PRDATA = can0_dm_id3_data[31:0];
            12'h104: io_apb_PRDATA = can0_dm_id4_count;
            12'h108: io_apb_PRDATA = can0_dm_id4_data[63:32];
            12'h10c: io_apb_PRDATA = can0_dm_id4_data[31:0];
            default: io_apb_PRDATA = 32'h0;
        endcase
    end

    always @(posedge io_mainClk or posedge resetCtrl_systemReset) begin
        if (resetCtrl_systemReset) begin
            can0_data <= 64'd0; can1_data <= 64'd0;
            can0_tx_id <= 11'h7ff; can1_tx_id <= 11'h200;
            can0_enable <= 1'b0; can1_enable <= 1'b0;
            can0_pending <= 1'b0; can1_pending <= 1'b0;
            sample_count <= 32'd0; age_count <= 16'hffff;
            can1_rx_shift <= 64'd0;
            can1_id1_data <= 64'd0; can1_id2_data <= 64'd0;
            can1_id1_count <= 32'd0; can1_id2_count <= 32'd0;
            can1_tx_ack_count <= 32'd0; can1_tx_fail_count <= 32'd0;
            can0_rx_shift <= 64'd0; can0_dm_last_data <= 64'd0;
            can0_dm_last_id <= 29'd0; can0_dm_rx_count <= 32'd0;
            can0_dm_id1_data <= 64'd0; can0_dm_id2_data <= 64'd0;
            can0_dm_id3_data <= 64'd0; can0_dm_id4_data <= 64'd0;
            can0_dm_id1_count <= 32'd0; can0_dm_id2_count <= 32'd0;
            can0_dm_id3_count <= 32'd0; can0_dm_id4_count <= 32'd0;
            can0_tx_ack_count <= 32'd0; can0_tx_fail_count <= 32'd0;
        end else begin
            if (io_imu_sample_valid) begin
                sample_count <= sample_count + 1'b1;
                age_count <= 16'd0;
            end else if (age_count != 16'hffff) age_count <= age_count + 1'b1;

            if (can0_pending && io_can0_tx_ready) can0_pending <= 1'b0;
            if (can1_pending && io_can1_tx_ready) can1_pending <= 1'b0;

            if (io_can1_rx_valid) begin
                can1_rx_shift <= {can1_rx_shift[55:0], io_can1_rx_data};
                if (io_can1_rx_last && !io_can1_rx_ide) begin
                    if (io_can1_rx_id[10:0] == 11'h201) begin
                        can1_id1_data <= {can1_rx_shift[55:0], io_can1_rx_data};
                        can1_id1_count <= can1_id1_count + 1'b1;
                    end else if (io_can1_rx_id[10:0] == 11'h202) begin
                        can1_id2_data <= {can1_rx_shift[55:0], io_can1_rx_data};
                        can1_id2_count <= can1_id2_count + 1'b1;
                    end
                end
            end
            if (io_can0_rx_valid) begin
                can0_rx_shift <= {can0_rx_shift[55:0], io_can0_rx_data};
                if (io_can0_rx_last && !io_can0_rx_ide && io_can0_rx_id[10:0] == 11'h000) begin
                    can0_dm_last_data <= {can0_rx_shift[55:0], io_can0_rx_data};
                    can0_dm_last_id <= io_can0_rx_id;
                    can0_dm_rx_count <= can0_dm_rx_count + 1'b1;
                    // DM4310 feedback D0 packs motor ID in bits [3:0] and
                    // error state in bits [7:4]. D0 is at shift[55:48]
                    // immediately before the final (D7) byte arrives.
                    case (can0_rx_shift[51:48])
                        11'd1: begin can0_dm_id1_data <= {can0_rx_shift[55:0], io_can0_rx_data}; can0_dm_id1_count <= can0_dm_id1_count + 1'b1; end
                        11'd2: begin can0_dm_id2_data <= {can0_rx_shift[55:0], io_can0_rx_data}; can0_dm_id2_count <= can0_dm_id2_count + 1'b1; end
                        11'd3: begin can0_dm_id3_data <= {can0_rx_shift[55:0], io_can0_rx_data}; can0_dm_id3_count <= can0_dm_id3_count + 1'b1; end
                        11'd4: begin can0_dm_id4_data <= {can0_rx_shift[55:0], io_can0_rx_data}; can0_dm_id4_count <= can0_dm_id4_count + 1'b1; end
                        default: begin end
                    endcase
                end
            end
            if (io_can0_tx_ack_event) can0_tx_ack_count <= can0_tx_ack_count + 1'b1;
            if (io_can0_tx_fail_event) can0_tx_fail_count <= can0_tx_fail_count + 1'b1;
            if (io_can1_tx_ack_event) can1_tx_ack_count <= can1_tx_ack_count + 1'b1;
            if (io_can1_tx_fail_event) can1_tx_fail_count <= can1_tx_fail_count + 1'b1;

            if (do_write) case (io_apb_PADDR)
                // Keyed enable/disable. 0xC620 in the upper half prevents
                // accidental writes from turning on a motor bus.
                12'h080: begin
                    if (io_apb_PWDATA[31:16] == 16'hC620) can0_enable <= io_apb_PWDATA[0];
                    if (io_apb_PWDATA[31:16] == 16'hC620 && io_apb_PWDATA[1] &&
                        (can0_enable || io_apb_PWDATA[0])) can0_pending <= 1'b1;
                end
                12'h084: can0_data[31:0] <= io_apb_PWDATA;
                12'h088: can0_data[63:32] <= io_apb_PWDATA;
                12'h08c: if (io_apb_PWDATA[31:16] == 16'hC620) can0_tx_id <= io_apb_PWDATA[10:0];
                12'h090: begin
                    if (io_apb_PWDATA[31:16] == 16'hC620) can1_enable <= io_apb_PWDATA[0];
                    if (io_apb_PWDATA[31:16] == 16'hC620 && io_apb_PWDATA[1] &&
                        (can1_enable || io_apb_PWDATA[0])) can1_pending <= 1'b1;
                end
                12'h094: can1_data[31:0] <= io_apb_PWDATA;
                12'h098: can1_data[63:32] <= io_apb_PWDATA;
                default: begin end
            endcase
        end
    end

    assign io_can0_tx_data = can0_data;
    assign io_can0_tx_id = can0_tx_id;
    assign io_can1_tx_data = can1_data;
    assign io_can1_tx_id = can1_tx_id;
    assign io_can0_tx_enable = can0_enable;
    assign io_can1_tx_enable = can1_enable;
    assign io_can0_tx_valid = can0_pending && can0_enable;
    assign io_can1_tx_valid = can1_pending && can1_enable;
endmodule
