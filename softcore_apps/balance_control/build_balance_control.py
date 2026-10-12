"""Build the safe wheel-legged balance-control framework image."""
from pathlib import Path
import argparse
import hashlib
import struct
import subprocess
import zlib

ROOT = Path(__file__).resolve().parent

def run(command):
    print("+", " ".join(str(x) for x in command))
    subprocess.run([str(x) for x in command], check=True, cwd=ROOT)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--zig", type=Path,
                        default=ROOT.parent / "toolchain" /
                        "zig-windows-x86_64-0.13.0" / "zig.exe")
    args = parser.parse_args()
    zig = args.zig.resolve()
    out = ROOT / "build"
    out.mkdir(exist_ok=True)
    flags = ["-target", "riscv32-freestanding",
             "-mcpu=generic_rv32+m+zicsr-a-c-d-f", "-mabi=ilp32", "-O2",
             "-ffreestanding", "-fno-builtin", "-fno-pic", "-fno-stack-protector",
             "-fno-asynchronous-unwind-tables", "-msmall-data-limit=0", "-mno-relax",
             "-nostdlib", "-Wall", "-Wextra", "-Werror"]
    objects = []
    for source in ("crt0.S", "main.c", "sdk.c"):
        obj = out / (Path(source).stem + ".o")
        run([zig, "cc", *flags, "-c", ROOT / source, "-o", obj])
        objects.append(obj)
    elf = out / "balance_control.elf"
    run([zig, "cc", *flags, *objects,
         "-Wl,-T," + str(ROOT / "app.ld"), "-o", elf])
    raw = out / "balance_control.bin"
    run([zig, "objcopy", "-O", "binary", elf, raw])
    payload = raw.read_bytes()
    if len(payload) > 40960:
        raise SystemExit(f"image is {len(payload)} bytes; bootloader limit is 40960 bytes")
    framed = out / "balance_control_frame.bin"
    framed.write_bytes(b"\xAA\x56" + struct.pack("<I", len(payload)) + payload +
                       struct.pack("<I", zlib.crc32(payload) & 0xffffffff))
    digest = hashlib.sha256(framed.read_bytes()).hexdigest()
    framed.with_suffix(framed.suffix + ".sha256").write_text(
        digest + "  " + framed.name + "\n", encoding="ascii")
    print(f"raw bytes   : {len(payload)}")
    print(f"frame bytes : {framed.stat().st_size}")
    print(f"frame sha256: {digest}")
    print(f"SEND THIS   : {framed}")

if __name__ == "__main__":
    main()
