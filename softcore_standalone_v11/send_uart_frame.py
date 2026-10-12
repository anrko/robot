#!/usr/bin/env python3
"""Send the prepared v1.1 Murax frame over the board's USB UART."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

try:
    import serial
except ImportError as exc:
    raise SystemExit("pyserial is required; install it with: python -m pip install pyserial") from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", help="USB UART COM port, for example COM14")
    parser.add_argument("--wait", type=float, default=8.0, help="seconds to print startup output")
    args = parser.parse_args()

    frame_path = Path(__file__).with_name("main_frame_v11.bin")
    frame = frame_path.read_bytes()
    if len(frame) < 10 or frame[:2] != b"\xAA\x56":
        raise SystemExit(f"Unexpected frame format: {frame_path}")

    payload_len = int.from_bytes(frame[2:6], "little")
    if len(frame) != payload_len + 10:
        raise SystemExit(
            f"Frame length mismatch: header says {payload_len} payload bytes, "
            f"file has {len(frame)} total bytes"
        )

    print(f"Opening {args.port} at 115200 8N1; close PuTTY first.")
    print("The FPGA bootloader must already show 'waiting for image'.")
    with serial.Serial(
        args.port,
        baudrate=115200,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=0.2,
        write_timeout=5,
        xonxoff=False,
        rtscts=False,
        dsrdtr=False,
    ) as port:
        time.sleep(0.15)
        sent = port.write(frame)
        port.flush()
        print(f"Sent {sent} bytes from {frame_path.name}; listening for startup output...")

        deadline = time.monotonic() + max(0.5, args.wait)
        while time.monotonic() < deadline:
            chunk = port.read(512)
            if chunk:
                sys.stdout.write(chunk.decode("ascii", errors="replace"))
                sys.stdout.flush()

    print("\nTransfer finished. Reopen PuTTY on the same COM port to continue using the console.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
