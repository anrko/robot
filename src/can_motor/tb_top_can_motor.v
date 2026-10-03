`timescale 1ns/1ps

module tb_top_can_motor;
    reg clk50m = 1'b0;
    always #10 clk50m = ~clk50m;

    wire can_bus;
    wire can_rx_dut;
    wire can_tx_dut;
    wire can_tx_sender;
    wire uart_tx;
    wire [7:0] state_led;
    reg sender_rstn = 1'b0;
    reg sender_tx_valid = 1'b0;
    reg [31:0] sender_tx_data = 32'hA1B2C3D4;

    assign can_bus = can_tx_dut & can_tx_sender;
    assign can_rx_dut = can_bus;

    top_can_motor dut (
        .clk50m   (clk50m),
        .can_rx   (can_rx_dut),
        .can_tx   (can_tx_dut),
        .uart_tx  (uart_tx),
        .state_led(state_led)
    );

    reg [2:0] sender_reset_shift = 3'd0;
    always @(posedge clk50m) begin
        {sender_rstn, sender_reset_shift} <= {sender_reset_shift, 1'b1};
    end

    can_top #(
        .LOCAL_ID           (11'h201),
        .RX_ID_SHORT_FILTER (11'h000),
        .RX_ID_SHORT_MASK   (11'h000),
        .default_c_PTS      (16'd34),
        .default_c_PBS1     (16'd5),
        .default_c_PBS2     (16'd10)
    ) sender (
        .rstn     (sender_rstn),
        .clk      (clk50m),
        .can_rx   (can_bus),
        .can_tx   (can_tx_sender),
        .tx_valid (sender_tx_valid),
        .tx_ready (),
        .tx_data  (sender_tx_data),
        .rx_valid (),
        .rx_last  (),
        .rx_data  (),
        .rx_id    (),
        .rx_ide   ()
    );

    initial begin
        #500;
        @(posedge clk50m);
        sender_tx_valid <= 1'b1;
        @(posedge clk50m);
        sender_tx_valid <= 1'b0;

        // A 4-byte frame at 1 Mbps completes well within this limit.
        #1_000_000;
        $display("ERROR: top_can_motor did not receive the synthetic frame");
        $finish;
    end

    always @(posedge clk50m) begin
        if (dut.rx_seen) begin
            $display("PASS: top_can_motor received frame data 0x%08x", dut.can_rx_data);
            $finish;
        end
    end
endmodule
