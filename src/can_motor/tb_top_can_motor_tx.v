`timescale 1ns/1ps

// Verifies the safe bring-up transmitter: standard ID 0x200, DLC 8,
// all-zero payload.  The second can_top instance acts as a CAN bus monitor
// and ACKs the frame, just as a real C620 node would.
module tb_top_can_motor_tx;
    reg clk50m = 1'b0;
    always #10 clk50m = ~clk50m;

    wire can_bus;
    wire can_tx_dut;
    wire can_tx_monitor;
    wire uart_tx;
    wire [7:0] state_led;
    wire monitor_rx_valid;
    wire monitor_rx_last;
    wire [7:0] monitor_rx_data;
    reg monitor_rstn = 1'b0;
    reg [2:0] monitor_reset_shift = 3'd0;
    reg [3:0] byte_count = 4'd0;
    reg frame_seen = 1'b0;

    assign can_bus = can_tx_dut & can_tx_monitor;

    always @(posedge clk50m)
        {monitor_rstn, monitor_reset_shift} <= {monitor_reset_shift, 1'b1};

    top_can_motor #(
        // Short period for simulation; the hardware default is 100 Hz.
        .TX_PERIOD_CYCLES(32'd500)
    ) dut (
        .clk50m   (clk50m),
        .can_rx   (can_bus),
        .can_tx   (can_tx_dut),
        .uart_tx  (uart_tx),
        .state_led(state_led)
    );

    can_top #(
        .LOCAL_ID           (11'h201),
        .RX_ID_SHORT_FILTER (11'h000),
        .RX_ID_SHORT_MASK   (11'h000),
        .default_c_PTS      (16'd34),
        .default_c_PBS1     (16'd5),
        .default_c_PBS2     (16'd10)
    ) monitor (
        .rstn     (monitor_rstn),
        .clk      (clk50m),
        .tx_id    (11'h201),
        .can_rx   (can_bus),
        .can_tx   (can_tx_monitor),
        .tx_valid (1'b0),
        .tx_ready (),
        .tx_data  (32'd0),
        .rx_valid (monitor_rx_valid),
        .rx_last  (monitor_rx_last),
        .rx_data  (monitor_rx_data),
        .rx_id    (),
        .rx_ide   ()
    );

    always @(posedge clk50m) begin
        if (dut.u_can_controller.pkt_tx_done)
            $display("TX attempt done: acked=%b retries=%0d", dut.u_can_controller.pkt_tx_acked,
                     dut.u_can_controller.t_retry_cnt);
        if (dut.can_tx_ack_event)
            $display("TX ACK EVENT: latched=%b", dut.tx_ack_seen);
        if (dut.can_tx_fail_event)
            $display("TX FAIL EVENT");
        if (monitor_rx_valid) begin
            if (monitor_rx_data != 8'd0) begin
                $display("ERROR: non-zero bring-up payload byte 0x%02x", monitor_rx_data);
                $finish;
            end
            if (monitor_rx_last) begin
                if (byte_count != 4'd7) begin
                    $display("ERROR: expected 8 payload bytes, got %0d", byte_count + 1'b1);
                    $finish;
                end
                $display("PASS: received safe C620 command frame, ID 0x200, DLC 8, zero payload");
                frame_seen <= 1'b1;
            end else begin
                byte_count <= byte_count + 1'b1;
            end
        end
        if (frame_seen && dut.tx_ack_seen) begin
            $display("PASS: DUT latched CAN ACK status on LED3");
            $finish;
        end
        if (dut.tx_fail_seen) begin
            $display("ERROR: DUT exhausted CAN transmit retries");
            $finish;
        end
    end

    initial begin
        #500_000;
        $display("ERROR: monitor did not receive the 8-byte TX frame");
        $finish;
    end
endmodule
