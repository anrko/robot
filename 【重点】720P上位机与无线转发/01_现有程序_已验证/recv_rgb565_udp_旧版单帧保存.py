"""Receive the DDR-free FPGA debug stream and save one RGB565 frame as PNG.

The FPGA sends one 2560-byte UDP payload per 1280-pixel line, 720 lines/frame.
Packets are intentionally treated in arrival order for the first link test.
"""
import argparse, socket
from pathlib import Path
from PIL import Image

W, H = 1280, 720
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bind", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=6102)
    ap.add_argument("--out", default="rgb565_test.png")
    ap.add_argument("--frames", type=int, default=1)
    args = ap.parse_args()
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16 * 1024 * 1024)
    s.bind((args.bind, args.port))
    print(f"listening UDP {args.bind}:{args.port}")
    for frame_no in range(args.frames):
        raw = bytearray()
        while len(raw) < W * H * 2:
            packet, addr = s.recvfrom(4096)
            if len(packet) != W * 2:
                print(f"skip {len(packet)} bytes from {addr}")
                continue
            raw.extend(packet)
        # The FIFO/UDP example emits the low byte first for each RGB565 word.
        im = Image.new("RGB", (W, H))
        px = im.load()
        for y in range(H):
            row = raw[y * W * 2:(y + 1) * W * 2]
            for x in range(W):
                lo, hi = row[2*x], row[2*x + 1]
                v = (hi << 8) | lo
                px[x, y] = ((v >> 11 & 31) * 255 // 31,
                            (v >> 5 & 63) * 255 // 63,
                            (v & 31) * 255 // 31)
        out = Path(args.out) if args.frames == 1 else Path(args.out).with_stem(f"{Path(args.out).stem}_{frame_no}")
        im.save(out)
        print(f"saved {out} ({W}x{H})")
if __name__ == "__main__":
    main()
