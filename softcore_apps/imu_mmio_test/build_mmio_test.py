"""Build the read-only IMU MMIO application for the integrated bitstream."""
from pathlib import Path
import argparse, hashlib, struct, subprocess, zlib

ROOT = Path(__file__).resolve().parent

def run(cmd):
    print("+", " ".join(str(x) for x in cmd))
    subprocess.run([str(x) for x in cmd], check=True, cwd=ROOT)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zig", type=Path, default=ROOT.parent / "toolchain" / "zig-windows-x86_64-0.13.0" / "zig.exe")
    args = ap.parse_args()
    zig = args.zig.resolve()
    out = ROOT / "build"
    out.mkdir(exist_ok=True)
    flags = ["-target", "riscv32-freestanding", "-mcpu=generic_rv32+m+zicsr-a-c-d-f",
             "-mabi=ilp32", "-O2", "-ffreestanding", "-fno-builtin", "-fno-pic",
             "-fno-stack-protector", "-fno-asynchronous-unwind-tables", "-msmall-data-limit=0",
             "-mno-relax", "-nostdlib", "-Wall", "-Wextra", "-Werror"]
    objs = []
    for i, src in enumerate(["crt0.S", "main.c", "sdk.c"]):
        obj = out / (Path(src).stem + ".o")
        run([zig, "cc", *flags, "-c", ROOT / src, "-o", obj])
        objs.append(obj)
    elf = out / "imu_mmio_test.elf"
    run([zig, "cc", *flags, *objs, "-Wl,-T," + str(ROOT / "app.ld"), "-o", elf])
    raw = out / "imu_mmio_test.bin"
    run([zig, "objcopy", "-O", "binary", elf, raw])
    if raw.stat().st_size > 40960:
        raise SystemExit("image exceeds 40 KiB bootloader limit")
    framed = out / "imu_mmio_test_frame.bin"
    payload = raw.read_bytes()
    framed.write_bytes(b"\xAA\x56" + struct.pack("<I", len(payload)) + payload + struct.pack("<I", zlib.crc32(payload) & 0xFFFFFFFF))
    digest = hashlib.sha256(framed.read_bytes()).hexdigest()
    (framed.with_suffix(framed.suffix + ".sha256")).write_text(digest + "  " + framed.name + "\n", encoding="ascii")
    print(f"raw bytes   : {raw.stat().st_size}")
    print(f"frame bytes : {framed.stat().st_size}")
    print(f"frame sha256: {digest}")
    print(f"SEND THIS   : {framed}")

if __name__ == "__main__":
    main()
