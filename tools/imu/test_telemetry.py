"""RTL-level UART frame test, including field order and CRC validation."""
from pathlib import Path
import subprocess
import tempfile
import re

from read_uart import decode_frame

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    with tempfile.TemporaryDirectory() as temp:
        sim = Path(temp) / "telemetry.vvp"
        subprocess.run([
            "iverilog", "-g2012", "-Wall", "-s", "tb_bmi088_telemetry_uart",
            "-o", str(sim), str(ROOT / "src/imu/bmi088_telemetry_uart.v"),
            str(ROOT / "sim/imu/tb_bmi088_telemetry_uart.v"),
        ], check=True, cwd=ROOT)
        output = subprocess.check_output(["vvp", str(sim)], text=True, cwd=ROOT)
    payload = bytes(int(token, 16) for token in output.split() if re.fullmatch(r"[0-9a-fA-F]{2}", token))
    record = decode_frame(payload)
    expected = {
        "sequence": 0, "ax_raw": -1234, "ay_raw": 200, "az_raw": 16384,
        "gx_raw": -50, "gy_raw": 25, "gz_raw": 7,
        "roll_fpga_d10": -101, "pitch_fpga_d10": 22, "yaw_fpga_d10": -1799,
    }
    if record != expected:
        raise AssertionError(f"decoded telemetry mismatch: {record!r}")
    print("PASS: RTL UART framing, field encoding and CRC-16 decode")


if __name__ == "__main__":
    main()
