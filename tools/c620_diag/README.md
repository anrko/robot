# C620 + DM USB-CAN diagnostic

The script uses Damiao's current DM Device SDK, not a raw COM8 serial protocol.
It listens for 15 seconds by default; it does not transmit unless `--send-zero`
is supplied. With `--send-zero`, it transmits DJI's standard frame `0x200`, DLC
8, payload `00 00 00 00 00 00 00 00` at 10 Hz for three seconds.

## Run

1. Close the DM tuning tool and any other program using the USB-CAN adapter.
2. Keep the motor secured and unloaded. Ensure the adapter is connected to the
   C620 CAN bus and configured with a 120-ohm terminator as appropriate.
3. Install the bundled Python binding with Python 3.13 x64:

   ```powershell
   py -3.13 -m pip install .\tools\c620_diag\dmcan_sdk-1.0.4-py3-none-any.whl
   ```

4. Run a receive-only diagnostic first:

   ```powershell
   py -3.13 .\tools\c620_diag\c620_usbcan_diag.py
   ```

5. If it finds the adapter and enables channel 0, run the zero-current CAN test:

   ```powershell
   py -3.13 .\tools\c620_diag\c620_usbcan_diag.py --send-zero
   ```

Use `--channel 1` only if the C620 is connected to the adapter's second channel.

The script reads the channel configuration and sets it to classic CAN at 1 Mbps
if needed. It reports received C620 feedback IDs `0x201` through `0x208`, SDK
send callbacks, and SDK error callbacks. It cannot measure bus resistance or
identify a physically open/shorted wire.

## Result interpretation

- `0x201` means C620 ID 1 feedback; `0x202` means ID 2, etc.
- No feedback during the receive-only phase means the C620 is not currently
  broadcasting a feedback frame, or the bus/adapter receive path is unavailable.
- If channel enable fails, close the DM tool and retry. The SDK needs exclusive
  access to the USB-CAN device.
- A TX callback only means the adapter processed the send request. Use the
  adapter's CAN error LED/counters and C620 feedback to assess bus response.

The bundled SDK runtime files are from Damiao's public DM Device SDK v1.1.0
Windows x64 backend and Python binding 1.0.4.
