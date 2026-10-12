"""Build a framed ACG138 C620 wheel-rotation test image."""
from pathlib import Path
import hashlib
import struct
import subprocess
import zlib

ROOT = Path(__file__).resolve().parent
ZIG = ROOT.parent / "toolchain" / "zig-windows-x86_64-0.13.0" / "zig.exe"


def run(command):
    print("+", " ".join(str(part) for part in command))
    subprocess.run([str(part) for part in command], check=True, cwd=ROOT)


def main():
    out = ROOT / "build"
    out.mkdir(exist_ok=True)
    flags = ["-target", "riscv32-freestanding", "-mcpu=generic_rv32+m+zicsr-a-c-d-f",
             "-mabi=ilp32", "-O2", "-ffreestanding", "-fno-builtin", "-fno-pic",
             "-fno-stack-protector", "-fno-asynchronous-unwind-tables",
             "-msmall-data-limit=0", "-mno-relax", "-nostdlib", "-Wall", "-Wextra", "-Werror"]
    objects = []
    for source in ("crt0.S", "main.c", "sdk.c"):
        obj = out / (Path(source).stem + ".o")
        run([ZIG, "cc", *flags, "-c", ROOT / source, "-o", obj])
        objects.append(obj)
    elf = out / "c620_wheel_spin.elf"
    run([ZIG, "cc", *flags, *objects, "-Wl,-T," + str(ROOT / "app.ld"), "-o", elf])
    raw = out / "c620_wheel_spin.bin"
    run([ZIG, "objcopy", "-O", "binary", elf, raw])
    payload = raw.read_bytes()
    if len(payload) > 40960:
        raise SystemExit(f"image is {len(payload)} bytes; bootloader limit is 40960 bytes")
    framed = out / "c620_wheel_spin_frame.bin"
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
