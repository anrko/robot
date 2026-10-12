"""Capture BMI088 raw samples and FPGA Euler angles from USB_DEBUG's FPGA COM port.

Install pyserial once with: python -m pip install pyserial
Example: python tools/imu/read_uart.py --port COM7 --output sim/imu/live_capture.csv
"""
from __future__ import annotations

import argparse
import csv
import math
import sys
from pathlib import Path

try:
    import serial
except ImportError as exc:
    raise SystemExit("pyserial missing; install with: python -m pip install pyserial") from exc

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "imu"))
from reference import SCALE, euler, step  # noqa: E402

FRAME_SIZE = 26
HEADER = b"\xA5\x5A"
DT_Q24 = 167772


def crc16_ccitt(data: bytes) -> int:
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def signed16(data: bytes) -> int:
    value = int.from_bytes(data, "little", signed=False)
    return value - 0x10000 if value & 0x8000 else value


def decode_frame(frame: bytes) -> dict[str, int]:
    if len(frame) != FRAME_SIZE or frame[:2] != HEADER:
        raise ValueError("bad frame size or sync header")
    expected = int.from_bytes(frame[24:26], "little")
    if crc16_ccitt(frame[:24]) != expected:
        raise ValueError("CRC mismatch")
    values = [signed16(frame[i:i + 2]) for i in range(6, 24, 2)]
    return {
        "sequence": int.from_bytes(frame[2:6], "little"),
        "ax_raw": values[0], "ay_raw": values[1], "az_raw": values[2],
        "gx_raw": values[3], "gy_raw": values[4], "gz_raw": values[5],
        "roll_fpga_d10": values[6], "pitch_fpga_d10": values[7], "yaw_fpga_d10": values[8],
    }


def frames_from_stream(port):
    buffer = bytearray()
    while True:
        chunk = port.read(128)
        if chunk:
            buffer.extend(chunk)
        while True:
            start = buffer.find(HEADER)
            if start < 0:
                if buffer[-1:] == HEADER[:1]:
                    del buffer[:-1]
                else:
                    buffer.clear()
                break
            if start:
                del buffer[:start]
            if len(buffer) < FRAME_SIZE:
                break
            candidate = bytes(buffer[:FRAME_SIZE])
            try:
                sample = decode_frame(candidate)
            except ValueError:
                del buffer[0]
                continue
            del buffer[:FRAME_SIZE]
            yield sample


def wrap_degrees(value: float) -> float:
    return (value + 180.0) % 360.0 - 180.0


def add_reference(sample: dict[str, int], q: tuple[float, ...]) -> tuple[tuple[float, ...], dict[str, float]]:
    # Match the exact integer-to-Q8.24 scaling constants used by bmi088_q24.v.
    acc = tuple(sample[k] * 3072 / SCALE for k in ("ax_raw", "ay_raw", "az_raw"))
    gyro = tuple(sample[k] * 8936 / SCALE for k in ("gx_raw", "gy_raw", "gz_raw"))
    q = step(q, acc, gyro, DT_Q24 / SCALE)
    angles = euler(q)
    fpga = tuple(sample[k] / 10.0 for k in ("roll_fpga_d10", "pitch_fpga_d10", "yaw_fpga_d10"))
    return q, {
        "roll_python_deg": angles[0], "pitch_python_deg": angles[1], "yaw_python_deg": angles[2],
        "roll_error_deg": wrap_degrees(fpga[0] - angles[0]),
        "pitch_error_deg": fpga[1] - angles[1],
        "yaw_error_deg": wrap_degrees(fpga[2] - angles[2]),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="FPGA COM port exposed by CH340E on USB_DEBUG")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--output", type=Path, default=Path("sim/imu/live_capture.csv"))
    parser.add_argument("--count", type=int, default=0, help="stop after this many valid records; 0 runs until Ctrl+C")
    args = parser.parse_args()
    output = args.output if args.output.is_absolute() else ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    fields = ["sequence", "ax_raw", "ay_raw", "az_raw", "gx_raw", "gy_raw", "gz_raw",
              "roll_fpga_d10", "pitch_fpga_d10", "yaw_fpga_d10", "roll_python_deg",
              "pitch_python_deg", "yaw_python_deg", "roll_error_deg", "pitch_error_deg", "yaw_error_deg"]
    q = (1.0, 0.0, 0.0, 0.0)
    count = 0
    with serial.Serial(args.port, args.baud, timeout=0.2) as port, output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        print(f"Capturing {args.port} at {args.baud} baud -> {output}")
        try:
            for sample in frames_from_stream(port):
                q, reference = add_reference(sample, q)
                writer.writerow({**sample, **reference})
                count += 1
                if count % 100 == 0:
                    stream.flush()
                    print(f"{count} frames; seq={sample['sequence']} yaw FPGA={sample['yaw_fpga_d10']/10:.1f} deg, "
                          f"Python={reference['yaw_python_deg']:.1f} deg, error={reference['yaw_error_deg']:.2f} deg")
                if args.count and count >= args.count:
                    break
        except KeyboardInterrupt:
            pass
    print(f"Saved {count} valid frames to {output}")


if __name__ == "__main__":
    main()
