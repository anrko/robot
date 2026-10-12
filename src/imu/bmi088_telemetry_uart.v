// Binary telemetry for the board's CH340E FPGA debug UART (USB_DEBUG/J2).
// 26-byte frame, 115200 baud, 8-N-1. Angles are signed tenths of a degree.
module bmi088_telemetry_uart #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200
) (
    input wire clk, input wire rst_n,
    input wire sample_valid,
    input wire signed [15:0] ax, ay, az, gx, gy, gz,
    input wire attitude_valid, input wire attitude_ready,
    input wire signed [15:0] roll_d10, pitch_d10, yaw_d10,
    output reg uart_tx
);
    localparam integer DIVISOR = CLK_HZ / BAUD;
    reg signed [15:0] ax_hold, ay_hold, az_hold, gx_hold, gy_hold, gz_hold;
    reg [207:0] frame;
    reg [31:0] seq_counter;
    reg frame_busy;
    reg [4:0] byte_index;
    reg [3:0] bit_index;
    reg [15:0] baud_count;
    reg [7:0] tx_byte;
    reg [1:0] tx_state;

    function [15:0] crc16_ccitt;
        input [191:0] payload;
        integer i, b;
        reg [15:0] crc;
        reg [7:0] data_byte;
        begin
            crc = 16'hffff;
            for (i = 0; i < 24; i = i + 1) begin
                data_byte = payload[i*8 +: 8];
                crc = crc ^ {data_byte, 8'h00};
                for (b = 0; b < 8; b = b + 1)
                    crc = crc[15] ? ((crc << 1) ^ 16'h1021) : (crc << 1);
            end
            crc16_ccitt = crc;
        end
    endfunction

    reg [191:0] frame_payload;
    reg [15:0] frame_crc;
    always @* begin
        frame_payload = 0;
        frame_payload[7:0] = 8'hA5;
        frame_payload[15:8] = 8'h5A;
        frame_payload[47:16] = seq_counter;
        frame_payload[63:48] = ax_hold;
        frame_payload[79:64] = ay_hold;
        frame_payload[95:80] = az_hold;
        frame_payload[111:96] = gx_hold;
        frame_payload[127:112] = gy_hold;
        frame_payload[143:128] = gz_hold;
        frame_payload[159:144] = roll_d10;
        frame_payload[175:160] = pitch_d10;
        frame_payload[191:176] = yaw_d10;
        frame_crc = crc16_ccitt(frame_payload);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ax_hold <= 0; ay_hold <= 0; az_hold <= 0;
            gx_hold <= 0; gy_hold <= 0; gz_hold <= 0;
            frame <= 0; seq_counter <= 0; frame_busy <= 0;
            byte_index <= 0; bit_index <= 0; baud_count <= 0;
            tx_byte <= 0; tx_state <= 0; uart_tx <= 1'b1;
        end else begin
            if (sample_valid) begin
                ax_hold <= ax; ay_hold <= ay; az_hold <= az;
                gx_hold <= gx; gy_hold <= gy; gz_hold <= gz;
            end

            if (attitude_valid && attitude_ready && !frame_busy) begin
                // Frame: A5 5A, sequence (u32 LE), accel (3 x i16 LE),
                // gyro (3 x i16 LE), Euler angles (3 x i16 LE), CRC16 LE.
                frame[7:0] <= 8'hA5;
                frame[15:8] <= 8'h5A;
                frame[47:16] <= seq_counter;
                frame[63:48] <= ax_hold;
                frame[79:64] <= ay_hold;
                frame[95:80] <= az_hold;
                frame[111:96] <= gx_hold;
                frame[127:112] <= gy_hold;
                frame[143:128] <= gz_hold;
                frame[159:144] <= roll_d10;
                frame[175:160] <= pitch_d10;
                frame[191:176] <= yaw_d10;
                frame[199:192] <= frame_crc[7:0];
                frame[207:200] <= frame_crc[15:8];
                seq_counter <= seq_counter + 1'b1;
                frame_busy <= 1'b1;
                byte_index <= 0;
            end

            if (frame_busy) begin
                if (tx_state == 0) begin
                    tx_byte <= frame[byte_index*8 +: 8];
                    uart_tx <= 1'b0;
                    baud_count <= DIVISOR - 1;
                    bit_index <= 0;
                    tx_state <= 1;
                end else if (baud_count != 0) begin
                    baud_count <= baud_count - 1'b1;
                end else begin
                    baud_count <= DIVISOR - 1;
                    case (tx_state)
                        1: begin uart_tx <= tx_byte[0]; tx_byte <= {1'b0,tx_byte[7:1]}; bit_index <= 1; tx_state <= 2; end
                        2: if (bit_index < 8) begin
                               uart_tx <= tx_byte[0]; tx_byte <= {1'b0,tx_byte[7:1]}; bit_index <= bit_index + 1'b1;
                           end else begin uart_tx <= 1'b1; tx_state <= 3; end
                        3: begin
                            tx_state <= 0;
                            if (byte_index == 25) begin frame_busy <= 0; byte_index <= 0; end
                            else byte_index <= byte_index + 1'b1;
                        end
                    endcase
                end
            end
        end
    end
endmodule
