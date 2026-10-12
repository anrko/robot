#!/usr/bin/env python3
"""Relay FPGA camera UDP rows from RK3588 eth0 to a PC over Wi-Fi.

The FPGA sends camera rows to RK3588 eth0:192.168.0.3:6102.  This process
receives those datagrams and sends the bytes unchanged to the PC address on
wlan0.  It does not decode or re-encode video, so the FPGA bitstream stays
unchanged during the link test.
"""
from __future__ import annotations

import argparse
import socket
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listen", default="0.0.0.0", help="RK listen address")
    parser.add_argument("--listen-port", type=int, default=6102)
    parser.add_argument("--target", required=True, help="PC Wi-Fi IPv4 address")
    parser.add_argument("--target-port", type=int, default=6102)
    parser.add_argument(
        "--bind-device",
        default="",
        help="optional Linux interface, normally wlan0; requires permission",
    )
    args = parser.parse_args()

    receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    receiver.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16 * 1024 * 1024)
    sender.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4 * 1024 * 1024)
    receiver.bind((args.listen, args.listen_port))

    if args.bind_device and hasattr(socket, "SO_BINDTODEVICE"):
        # This keeps the forwarding leg on Wi-Fi when eth0 and wlan0 both have
        # routes.  Linux restricts this option to a privileged process.
        sender.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, args.bind_device.encode() + b"\0")

    target = (args.target, args.target_port)
    print(f"relay UDP {args.listen}:{args.listen_port} -> {target[0]}:{target[1]}", flush=True)
    if args.bind_device:
        print(f"egress interface: {args.bind_device}", flush=True)

    packets = bytes_forwarded = bad = 0
    next_report = time.monotonic() + 1.0
    try:
        while True:
            payload, source = receiver.recvfrom(4096)
            if len(payload) not in (1280 * 2, 1280 * 2 + 2):
                bad += 1
                continue
            try:
                sender.sendto(payload, target)
            except OSError as exc:
                print(f"forward failed: {exc}", flush=True)
                continue
            packets += 1
            bytes_forwarded += len(payload)
            now = time.monotonic()
            if now >= next_report:
                print(
                    f"RX/forward packets={packets} bytes={bytes_forwarded} "
                    f"bad_length={bad} last_source={source[0]}:{source[1]}",
                    flush=True,
                )
                next_report = now + 1.0
    except KeyboardInterrupt:
        print("stopped", flush=True)
    finally:
        receiver.close()
        sender.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
