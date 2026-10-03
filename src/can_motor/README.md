# CAN motor bring-up image

This is a separate Gowin target for the GW5AT board. It keeps the working
camera target unchanged.

The first image is receive-only at the application level:

- Classic CAN, 11-bit standard frames, 1 Mbps.
- Receives the `0x200..0x207` ID window.
- Sends received data bytes to `uart_tx` at 115200 8-N-1.
- Does not send C620 current commands.

The CAN controller files originate from `FPGA-CAN-main`. Its original TX
interface is fixed at four data bytes, so the C620 eight-byte command path must
be extended before any motor current is sent.

## Physical connections

```text
FPGA can_tx -> SN65HVD230 TXD/TX
FPGA can_rx <- SN65HVD230 RXD/RX
FPGA 3.3 V  -> SN65HVD230 3.3 V
FPGA GND    -> SN65HVD230 GND
SN65 CANH/CANL -> C620 and USB-CAN CANH/CANL
```

The current constraints use P7 candidates V15/T15/U16. Verify the board
connector and bank voltage before wiring.
