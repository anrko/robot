"""Passive UART monitor for a C620 connected through a USB-UART bridge.

C620's configuration protocol and UART baud rate are not documented in the
available manuals. This script never transmits data.
"""

from __future__ import annotations

import argparse
import sys
import time

import serial
from serial.tools import list_ports


def show_ports() -> None:
    ports = list(list_ports.comports())
    if not ports:
        print("No serial ports found.")
        return
    for port in ports:
        print(f"{port.device}: {port.description} [{port.hwid}]")


def main() -> int:
    parser = argparse.ArgumentParser(description="Passive C620 UART monitor")
    parser.add_argument("--list", action="store_true", help="list serial ports and exit")
    parser.add_argument("--port", default="COM8", help="serial port (default: COM8)")
    parser.add_argument("--baud", type=int, default=115200, help="trial baud rate (default: 115200; not confirmed for C620)")
    parser.add_argument("--seconds", type=float, default=20.0, help="listen duration; 0 means until Ctrl+C")
    args = parser.parse_args()

    if args.list:
        show_ports()
        return 0

    print(f"Opening {args.port} at {args.baud} 8N1 in receive-only mode.")
    print("C620's UART baud rate and query frames are not documented; silence is inconclusive.")
    print("Press Ctrl+C to stop.")
    try:
        with serial.Serial(
            port=args.port,
            baudrate=args.baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.1,
            write_timeout=1.0,
        ) as ser:
            start = time.monotonic()
            received = 0
            while args.seconds <= 0 or time.monotonic() - start < args.seconds:
                chunk = ser.read(ser.in_waiting or 1)
                if chunk:
                    received += len(chunk)
                    stamp = time.strftime("%H:%M:%S")
                    ascii_view = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
                    print(f"{stamp} RX {len(chunk):3d} bytes: {chunk.hex(' ').upper()}  |{ascii_view}|")
            print(f"Finished. Received {received} byte(s).")
    except serial.SerialException as exc:
        print(f"Cannot open/read {args.port}: {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("\nStopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
