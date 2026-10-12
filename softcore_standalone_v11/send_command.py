#!/usr/bin/env python3
"""Send one console command to the running Murax application."""

from __future__ import annotations

import argparse
import sys
import time

import serial


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("port", help="for example COM14")
    ap.add_argument("command", nargs="?", default="c", help="one command byte: c, i, k, r, or t")
    args = ap.parse_args()
    if len(args.command) != 1:
        raise SystemExit("command must be exactly one character")

    with serial.Serial(
        args.port,
        115200,
        timeout=0.2,
        write_timeout=2,
        xonxoff=False,
        rtscts=False,
        dsrdtr=False,
    ) as port:
        # Discard stale boot text, then send one byte. The application handles
        # commands immediately; Enter is not required.
        port.reset_input_buffer()
        port.write(args.command.encode("ascii"))
        port.flush()
        deadline = time.monotonic() + 2.0
        received = bytearray()
        while time.monotonic() < deadline:
            data = port.read(512)
            if data:
                received.extend(data)
        sys.stdout.write(received.decode("ascii", errors="replace"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
