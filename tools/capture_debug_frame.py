"""Capture one DDR readback crop from the FPGA CH340E USB_Debug port."""

import argparse
from pathlib import Path

import serial
from PIL import Image


def capture(port: str, destination: Path, scale: int) -> None:
    with serial.Serial(port, 115200, timeout=3) as link:
        print(f"Listening on {port}; reset the FPGA if nothing appears...")
        while True:
            line = link.readline().strip()
            if line.startswith(b"CAL="):
                print(line.decode("ascii", errors="replace"))
            if line.startswith(b"BUS "):
                print(line.decode("ascii", errors="replace"))
            if line == b"FRAME 64 64 RGB565":
                break

        rows = []
        for row in range(64):
            line = link.readline().strip()
            if len(line) != 256:
                raise ValueError(f"row {row}: expected 256 hex characters, got {len(line)}")
            try:
                rows.append([int(line[col:col + 4], 16) for col in range(0, 256, 4)])
            except ValueError as exc:
                raise ValueError(f"row {row}: invalid RGB565 data") from exc

        trailer = link.readline().strip()
        if not trailer.startswith(b"END ") or len(trailer) != 8:
            raise ValueError(f"invalid trailer: {trailer!r}")
        expected = int(trailer[4:], 16)
        actual = sum(map(sum, rows)) & 0xFFFF
        if actual != expected:
            raise ValueError(f"checksum mismatch: received {expected:04X}, computed {actual:04X}")

        pixels = [
            (((value >> 11) & 31) * 255 // 31,
             ((value >> 5) & 63) * 255 // 63,
             (value & 31) * 255 // 31)
            for row in rows for value in row
        ]
        image = Image.new("RGB", (64, 64))
        image.putdata(pixels)
        if scale != 1:
            image = image.resize((64 * scale, 64 * scale), Image.Resampling.NEAREST)
        image.save(destination)
        print(f"Saved {destination} (checksum {actual:04X})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", help="FPGA CH340E port, e.g. COM7")
    parser.add_argument("--output", type=Path, default=Path("debug_frame.png"))
    parser.add_argument("--scale", type=int, default=8)
    args = parser.parse_args()
    if args.scale < 1:
        parser.error("--scale must be positive")
    try:
        capture(args.port, args.output, args.scale)
    except (serial.SerialException, ValueError, TimeoutError) as exc:
        parser.exit(1, f"Capture failed: {exc}\n")
