# CAN MMIO one-shot verification

Application for the integrated `camera720_imu_softcore_can2_mmio.fs` image.
It prints the latched RX status and only transmits after a serial key:

- `s`: show CAN0/CAN1 RX-seen bits and TX-ready bits;
- `0`: request exactly one standard CAN0 frame, ID `0x200`, DLC 8, all bytes zero;
- `1`: request exactly one standard CAN1 frame, ID `0x201`, DLC 8, all bytes zero;
- `ESC`: stop the app; reset the FPGA to return to its bootloader.

Nothing is queued automatically. Both transmitters are explicitly disabled
after a one-shot request. Disconnect motor power for the TX test; the frame
payload is zero-current, but this is still a motor command identifier.

Build from the workspace root:

```powershell
python .\softcore_apps\can_mmio_test\build_can_test.py
```

Send `build\can_mmio_test_frame.bin` through the bootloader using SecureCRT's
**Transfer -> Send Binary File...** menu. It is an AA56/CRC32 framed image.

USB-CAN settings: classic CAN, 1 Mbps, standard 11-bit ID, normal/active mode.
The integrated receivers accept IDs `0x200` through `0x207`. The selected
transceiver must connect FPGA TX to transceiver TXD and FPGA RX to transceiver
RXD, with common ground and CANH/CANL shared to the USB-CAN adapter. Keep only
the two physical end terminators on the bus; power off and measure about 60 Ω
between CANH and CANL when two 120 Ω terminations are present.
