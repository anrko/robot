// First CAN bring-up top for the GW5AT board.
// This image receives CAN frames and periodically sends a zero-current C620
// command frame while reporting received data bytes over UART.
module top_can_motor #(
    // Default is 100 Hz, which is sufficient for a zero-current bring-up
    // frame and leaves the bus idle between transmissions.
    parameter [31:0] TX_PERIOD_CYCLES = 32'd500_000
) (
    input        clk50m,
    input        can_rx,
    output       can_tx,
    output       uart_tx,
    output [7:0] state_led
);
    reg        rstn = 1'b0;
    reg [2:0]  rst_shift = 3'd0;
    reg [25:0] heartbeat = 26'd0;
    reg        rx_seen = 1'b0;
    reg        tx_seen = 1'b0;
    reg        tx_ack_seen = 1'b0;
    reg        tx_fail_seen = 1'b0;
    reg        tx_valid = 1'b0;
    reg [31:0] tx_period_counter = 32'd0;
    reg [63:0] tx_data = 64'd0;

    wire       can_rx_valid;
    wire       can_rx_last;
    wire [7:0] can_rx_data;
    wire [28:0] can_rx_id;
    wire        can_rx_ide;
    wire        can_tx_ready;
    wire        can_tx_ack_event;
    wire        can_tx_fail_event;

    // Release reset after a few 50 MHz cycles. The scheduler below only queues
    // an all-zero C620 command, so this bring-up image cannot request torque.
    always @(posedge clk50m) begin
        {rstn, rst_shift} <= {rst_shift, 1'b1};
        heartbeat <= heartbeat + 1'b1;
        tx_valid <= 1'b0;
        if (~rstn) begin
            tx_period_counter <= 32'd0;
            tx_seen <= 1'b0;
            rx_seen <= 1'b0;
            tx_ack_seen <= 1'b0;
            tx_fail_seen <= 1'b0;
        end else begin
            if (can_rx_valid)
                rx_seen <= 1'b1;
            if (can_tx_ack_event)
                tx_ack_seen <= 1'b1;
            if (can_tx_fail_event)
                tx_fail_seen <= 1'b1;

            if (tx_period_counter >= TX_PERIOD_CYCLES - 1'b1) begin
                tx_period_counter <= 32'd0;
                if (can_tx_ready) begin
                    // C620 command frame: ID 0x200, DLC 8, all four
                    // signed current commands equal to zero.
                    tx_data <= 64'd0;
                    tx_valid <= 1'b1;
                    tx_seen <= 1'b1;
                end
            end else begin
                tx_period_counter <= tx_period_counter + 1'b1;
            end
        end
    end

    can_top #(
        .LOCAL_ID           (11'h200),
        .TX_DLC             (4'd8),
        // Accept the C620 feedback ID window 0x200..0x207. The wrapper below
        // can later discard 0x200 and 0x205..0x207 if required.
        .RX_ID_SHORT_FILTER (11'h200),
        .RX_ID_SHORT_MASK   (11'h7f8),
        .RX_ID_LONG_FILTER  (29'h0),
        .RX_ID_LONG_MASK    (29'h1fffffff),
        .default_c_PTS      (16'd34),
        .default_c_PBS1     (16'd5),
        .default_c_PBS2     (16'd10)
    ) u_can_controller (
        .rstn       (rstn),
        .clk        (clk50m),
        .tx_id      (11'h200),
        .can_rx     (can_rx),
        .can_tx     (can_tx),
        .tx_valid   (tx_valid),
        .tx_ready   (can_tx_ready),
        .tx_data    (tx_data),
        .rx_valid   (can_rx_valid),
        .rx_last    (can_rx_last),
        .rx_data    (can_rx_data),
        .rx_id      (can_rx_id),
        .rx_ide     (can_rx_ide),
        .tx_ack_event  (can_tx_ack_event),
        .tx_fail_event (can_tx_fail_event)
    );

    // Raw received bytes are exposed at 115200 8-N-1. This is enough to
    // verify the PHY/controller path with a USB-CAN adapter before adding a
    // framed C620 decoder.
    uart_tx #(
        .CLK_FREQ       (50000000),
        .BAUD_RATE      (115200),
        .PARITY         ("NONE"),
        .STOP_BITS      (1),
        .BYTE_WIDTH     (1),
        .FIFO_EA        (6)
    ) u_uart (
        .rstn       (rstn),
        .clk        (clk50m),
        .i_tready   (),
        .i_tvalid   (can_rx_valid),
        .i_tdata    (can_rx_data),
        .i_tkeep    (1'b1),
        .i_tlast    (can_rx_last),
        .o_uart_tx  (uart_tx)
    );

    // This board's D0-D7 indicators are active-high: D0 heartbeat, D1 valid
    // CAN RX, D2 command queued, D3 at least one CAN ACK, D4 final TX failure.
    // D5-D6 are unused; D7 indicates that reset has been released.
    assign state_led = {rstn, 2'b00, tx_fail_seen, tx_ack_seen,
                        tx_seen, rx_seen, heartbeat[25]};
endmodule
