// First CAN bring-up top for the GW5AT board.
// This image only receives CAN frames and reports their data bytes over UART.
// It deliberately does not send motor-current commands.
module top_can_motor (
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

    wire       can_rx_valid;
    wire       can_rx_last;
    wire [7:0] can_rx_data;
    wire [28:0] can_rx_id;
    wire        can_rx_ide;

    // Release reset after a few 50 MHz cycles. TX is intentionally disabled
    // until the C620 8-byte command path is added and tested.
    always @(posedge clk50m) begin
        {rstn, rst_shift} <= {rst_shift, 1'b1};
        heartbeat <= heartbeat + 1'b1;
        if (can_rx_valid)
            rx_seen <= 1'b1;
    end

    can_top #(
        .LOCAL_ID           (11'h200),
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
        .can_rx     (can_rx),
        .can_tx     (can_tx),
        .tx_valid   (1'b0),
        .tx_ready   (),
        .tx_data    (32'd0),
        .rx_valid   (can_rx_valid),
        .rx_last    (can_rx_last),
        .rx_data    (can_rx_data),
        .rx_id      (can_rx_id),
        .rx_ide     (can_rx_ide)
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

    // Board LEDs are active-low on the camera design. LED0 is heartbeat,
    // LED1 latches after the first accepted frame, LED7 shows reset.
    assign state_led = {~rstn, 5'b11111, ~rx_seen, ~heartbeat[25]};
endmodule
