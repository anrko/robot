#!/usr/bin/env python3
"""Receive and display the 1280x720 RGB565 UDP stream forwarded over Wi-Fi.

Current camera packets are 2562 bytes: little-endian row number followed by
one 1280-pixel RGB565 row.  The old color-bar format (2560 bytes without a
row number) is accepted as a compatibility fallback.
"""
from __future__ import annotations

import argparse
import socket
import time
from pathlib import Path

from PIL import Image

WIDTH, HEIGHT = 1280, 720
LINE_BYTES = WIDTH * 2
CAMERA_PACKET_BYTES = LINE_BYTES + 2
FRAME_BYTES = LINE_BYTES * HEIGHT


def rgb565_image(frame: bytes) -> Image.Image:
    # FPGA sends RGB565 low byte first. Pillow's BGR;16 decoder gives RGB888.
    return Image.frombytes("RGB", (WIDTH, HEIGHT), frame, "raw", "BGR;16")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=6102)
    parser.add_argument("--headless", action="store_true", help="do not open a window")
    parser.add_argument("--save-dir", type=Path, help="also save received frames here")
    parser.add_argument("--save-every", type=int, default=0, help="save every Nth frame; 0 saves none")
    parser.add_argument("--max-frames", type=int, default=0, help="stop after N frames; 0 means forever")
    parser.add_argument("--title", default="ACG138 720P Wi-Fi 视频")
    args = parser.parse_args()
    if args.save_every < 0 or args.max_frames < 0:
        parser.error("--save-every and --max-frames must be non-negative")
    if args.headless is False and args.save_dir is None:
        # A GUI is the useful default on a Windows PC. --headless is available
        # for testing on a machine without Tk/display support.
        pass

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16 * 1024 * 1024)
    sock.settimeout(0.2)
    sock.bind((args.bind, args.port))
    print(f"listening UDP {args.bind}:{args.port} for 1280x720 RGB565", flush=True)

    root = label = None
    image_tk = None
    if not args.headless:
        try:
            import tkinter as tk
            from PIL import ImageTk

            root = tk.Tk()
            root.title(args.title)
            root.protocol("WM_DELETE_WINDOW", root.destroy)
            label = tk.Label(root)
            label.pack()
        except Exception as exc:
            print(f"GUI unavailable ({exc}); switching to headless mode", flush=True)
            root = label = None

    if args.save_dir:
        args.save_dir.mkdir(parents=True, exist_ok=True)

    frame = bytearray(FRAME_BYTES)
    seen = bytearray(HEIGHT)
    rows = 0
    legacy_row = 0
    packets = bad = displayed = 0
    started = time.monotonic()
    last_packet = started
    next_report = started + 1.0

    def clear_frame() -> None:
        nonlocal rows, legacy_row
        seen[:] = b"\0" * HEIGHT
        rows = 0
        legacy_row = 0

    def present() -> bool:
        nonlocal image_tk, displayed
        image = rgb565_image(bytes(frame))
        displayed += 1
        if root is not None and label is not None:
            from PIL import ImageTk

            image_tk = ImageTk.PhotoImage(image=image)
            label.configure(image=image_tk)
            root.update_idletasks()
            root.update()
        if args.save_dir and args.save_every and displayed % args.save_every == 0:
            image.save(args.save_dir / f"frame_{displayed:06d}.png")
        return args.max_frames > 0 and displayed >= args.max_frames

    try:
        while True:
            if root is not None:
                try:
                    root.update_idletasks()
                    root.update()
                except Exception:
                    root = label = None
            try:
                payload, address = sock.recvfrom(CAMERA_PACKET_BYTES)
            except socket.timeout:
                if rows and time.monotonic() - last_packet > 0.25:
                    # A lost UDP row must not freeze the next frame forever.
                    clear_frame()
                continue
            except KeyboardInterrupt:
                break

            now = time.monotonic()
            last_packet = now
            if len(payload) == CAMERA_PACKET_BYTES:
                row = payload[0] | (payload[1] << 8)
                if row >= HEIGHT:
                    bad += 1
                    continue
                # Row 0 is the only frame boundary available in this protocol.
                if row == 0 and seen[0] and rows:
                    clear_frame()
                offset = row * LINE_BYTES
                if not seen[row]:
                    frame[offset : offset + LINE_BYTES] = payload[2:]
                    seen[row] = 1
                    rows += 1
                packets += 1
                if rows == HEIGHT:
                    if present():
                        break
                    clear_frame()
            elif len(payload) == LINE_BYTES:
                # Legacy color-bar stream: rows arrive sequentially and carry
                # no row number. Its verified content is repeated by the old
                # RK receiver, so assemble one frame from 720 datagrams.
                offset = legacy_row * LINE_BYTES
                frame[offset : offset + LINE_BYTES] = payload
                legacy_row = (legacy_row + 1) % HEIGHT
                packets += 1
                if legacy_row == 0:
                    if present():
                        break
                    clear_frame()
            else:
                bad += 1

            if now >= next_report:
                elapsed = max(now - started, 1e-6)
                print(
                    f"packets={packets} bad_length={bad} displayed_frames={displayed} "
                    f"rate={packets / elapsed:.1f} packets/s last={address[0]}",
                    flush=True,
                )
                next_report = now + 1.0
    finally:
        sock.close()
        if root is not None:
            try:
                root.destroy()
            except Exception:
                pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
