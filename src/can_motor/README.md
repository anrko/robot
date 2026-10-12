# CAN motor bring-up image

This is a separate Gowin target for the GW5AT board. It keeps the working
camera target unchanged.

The current bring-up image has a safe application-level transmitter:

- Classic CAN, 11-bit standard frames, 1 Mbps.
- Receives the `0x200..0x207` ID window.
- Sends received data bytes to `uart_tx` at 115200 8-N-1.
- Periodically sends `0x200`, DLC 8, with all eight data bytes equal to zero.
- The periodic frame is a zero-current C620 command and does not drive torque.
- Latches LED status for received CAN frames, command queueing, CAN ACK, and
  final transmit failure after retries.

The transmitter is intentionally fixed to zero data for the first hardware
test. A later control layer can replace `tx_data` after the CAN path and C620
feedback decoder have been verified.

The CAN controller files originate from `FPGA-CAN-main`. The packet layer was
extended to support an eight-byte transmit payload for C620 while retaining the
four-byte default used by the original examples.

## Physical connections

```text
P7 pin 1 (GPIO0/V15, can_tx) -> SN65HVD230 TX
P7 pin 3 (GPIO2/T15, can_rx) <- SN65HVD230 RX
P7 pin 29 (3.3 V)            -> SN65HVD230 VCC
P7 pin 30 (GND)              -> SN65HVD230 GND
SN65HVD230 CANH/CANL         -> C620 CANH/CANL
```

The SN65HVD230 board has a fitted 120-ohm terminator. The C620 is the other
bus endpoint; with power off, the connected CANH-to-CANL resistance should be
about 60 ohms. Disconnect the USB-CAN adapter during this direct FPGA test so
it does not add a third terminator.

UART debug is routed to the FPGA-side CH340E on board connector J2 (package
pin C13). Connect J2 to the PC and open the CH340E COM port at 115200 baud,
8-N-1. The current UART stream contains raw received payload bytes, not
formatted text; D1 and the status LEDs are easier for the first check.

The user LEDs are active-high on the tested board: D0 heartbeat, D1 a valid
received frame, D2 command queued, D3 at least one CAN ACK, D4 final transmit
failure after retries, D7 reset released. D2 alone does not mean the C620
acknowledged a frame.

The earlier receive-only programming file is
`release/can_motor_1mb_rx_uart.fs`. The current zero-current transmitter file
is `release/can_motor_1mb_zero_tx.fs`; its SHA-256 is recorded in the adjacent
`.sha256` file. The implementation report is under
`impl/pnr/can_motor.rpt.txt` after running `tools/build_can_motor.tcl` through
Gowin `gw_sh`.

For the zero-current transmitter build, use `release/can_motor_1mb_zero_tx.fs`
only if its PNR was generated after the current `can_motor.cst` change to J2.
The source project is `can_motor.gprj`; regenerate the bitstream after changing
constraints or RTL. The FPGA produces standard `0x200`, DLC 8, all-zero frames
about every 10 ms. Non-zero motor commands are not implemented.
