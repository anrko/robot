#!/usr/bin/env python3
"""Diagnose a DJI C620/M3508 on a Damiao USB2CANFD adapter.

Default mode is receive-only for 15 seconds. Pass --send-zero to transmit
standard CAN 0x200 / DLC 8 / eight zero bytes at 10 Hz after the listen phase.
This is a zero-current command; it is not a motor spin test.
"""

from __future__ import annotations

import argparse
import os
import time
from pathlib import Path


EXPECTED_IDS = set(range(0x201, 0x209))


def main() -> int:
    parser = argparse.ArgumentParser(description="C620 + Damiao USB2CANFD diagnostic")
    parser.add_argument("--channel", type=int, default=0, help="USB-CAN channel (default: 0)")
    parser.add_argument("--listen", type=float, default=15.0, help="receive-only interval in seconds")
    parser.add_argument("--send-zero", action="store_true", help="send zero-current 0x200 frames after listening")
    parser.add_argument("--zero-seconds", type=float, default=3.0, help="zero-frame send duration")
    parser.add_argument("--rate", type=float, default=10.0, help="zero-frame send rate in Hz")
    args = parser.parse_args()

    if args.channel not in (0, 1):
        parser.error("--channel must be 0 or 1")
    if args.listen < 0 or args.zero_seconds <= 0 or args.rate <= 0:
        parser.error("listen must be >= 0; zero-seconds and rate must be > 0")

    # Locate the SDK backend shipped alongside this script.
    root = Path(__file__).resolve().parent
    dll_dir = root / "dlls"
    backend = dll_dir / "libdm_device.dll"
    libusb = root / "libusb-1.0.dll"
    if not backend.is_file() or not libusb.is_file():
        print("SDK DLL files are missing.")
        print(f"Expected backend: {backend}")
        print(f"Expected libusb: {libusb}")
        return 2

    try:
        from dmcan import DmCanContext
    except Exception as exc:
        print(f"Cannot import Damiao's dmcan Python SDK: {exc}")
        print("Use Python 3.13 x64 and install the bundled wheel:")
        print('  py -3.13 -m pip install "引脚约束以及资料\\dm-tools-master\\DM_DeviceSDK\\Python\\pack\\dmcan_sdk-1.0.4-py3-none-any.whl"')
        return 2

    # The SDK wheel resolves its backend relative to the current directory.
    os.chdir(root)
    dll_search_handles = []
    if hasattr(os, "add_dll_directory"):
        dll_search_handles.append(os.add_dll_directory(str(root)))
        dll_search_handles.append(os.add_dll_directory(str(dll_dir)))

    frames: list[tuple[int, int, bytes, int, int]] = []
    sent: list[tuple[int, int]] = []
    errors: list[str] = []
    context = None
    device = None

    def on_rx(_device, frame):
        h = frame.head
        dlc = int(h.dlc)
        data = bytes(frame.payload[:min(dlc, 8)])
        frames.append((int(h.can_id), dlc, data, int(h.canfd), int(h.ext)))
        print(f"RX {'EXT' if h.ext else 'STD'} {'FD' if h.canfd else 'CAN'} "
              f"ID=0x{h.can_id:03X} DLC={dlc} DATA={' '.join(f'{b:02X}' for b in data)} "
              f"ACK={int(h.ack)}")

    def on_tx(_device, frame):
        h = frame.head
        sent.append((int(h.can_id), int(h.ack)))
        print(f"TX callback ID=0x{h.can_id:03X} DLC={h.dlc} ACK={int(h.ack)}")

    def on_error(_device, frame):
        h = frame.head
        msg = f"SDK/CAN error callback: ID=0x{h.can_id:X} DLC={h.dlc} ACK={int(h.ack)}"
        errors.append(msg)
        print("ERROR " + msg)

    try:
        context = DmCanContext()
        context.print_version()
        count = context.find_devices()
        context.show_all_devices()
        if count < 1:
            print("FAIL: current DM Device SDK did not enumerate a USB2CANFD device.")
            return 3
        device = context.get_device(0)
        opened = device.open()
        print(f"Device open result: {opened}")
        if not opened:
            print("FAIL: SDK found the device but could not open it. Close the DM tool/other CAN apps and retry.")
            return 3
        device.print_version()

        info = device.get_channel_baudrate(args.channel)
        if info is None:
            print(f"FAIL: cannot read CAN channel {args.channel} configuration.")
            return 3
        print(f"Channel {args.channel} initial config: CAN-FD={bool(info.canfd)}, "
              f"nominal={info.can_baudrate} bit/s, data={info.canfd_baudrate} bit/s")

        if info.canfd or info.can_baudrate != 1_000_000:
            print("Applying C620-compatible classic CAN, 1 Mbps configuration...")
            info.canfd = False
            info.can_baudrate = 1_000_000
            if not device.set_channel_baudrate(args.channel, info):
                print("FAIL: could not set channel to classic CAN 1 Mbps.")
                return 4
            info = device.get_channel_baudrate(args.channel)
            if info is None or info.canfd or info.can_baudrate != 1_000_000:
                print("FAIL: readback did not confirm classic CAN at 1 Mbps.")
                return 4
        if not device.enable_channel(args.channel, True):
            print(f"FAIL: could not enable CAN channel {args.channel}.")
            print("Close the DM tuning tool and all other apps using the adapter, then retry.")
            return 4

        device.hook_recv_callback(on_rx)
        device.hook_sent_callback(on_tx)
        device.hook_err_callback(on_error)

        print(f"Listening on channel {args.channel} for {args.listen:.1f}s; no CAN frames sent.")
        time.sleep(args.listen)

        if args.send_zero:
            print("Sending zero-current DJI frame: STD CAN ID=0x200 DLC=8 DATA=00 00 00 00 00 00 00 00")
            print("Keep the motor unloaded and secured. This command requests zero current.")
            period = 1.0 / args.rate
            deadline = time.monotonic() + args.zero_seconds
            payload = bytes(8)
            while time.monotonic() < deadline:
                ok = device.send_can(args.channel, 0x200, 8, payload,
                                     canfd=False, ext=False, rtr=False, brs=False)
                if not ok:
                    print("FAIL: SDK rejected/enqueue failed for CAN ID 0x200.")
                time.sleep(period)

        feedback = sorted({frame[0] for frame in frames if frame[0] in EXPECTED_IDS})
        print("\n===== SUMMARY =====")
        print(f"CAN frames received: {len(frames)}")
        print(f"C620 feedback IDs 0x201..0x208 seen: "
              f"{', '.join(f'0x{x:03X}' for x in feedback) if feedback else 'none'}")
        print(f"TX callbacks: {len(sent)}; SDK error callbacks: {len(errors)}")
        if feedback:
            print("RESULT: C620 feedback is present. CAN wiring, bitrate, and at least one C620 node are communicating.")
        elif args.send_zero and sent:
            print("RESULT: SDK transmitted the test frame, but no C620 feedback was captured. Check C620 ID/status, "
                  "motor 7-pin and phase leads, CAN-vs-PWM selection, and the adapter's CAN error LED/counters.")
        elif not args.send_zero:
            print("RESULT: listen-only run found no C620 feedback. Re-run with --send-zero to test a bus transmission.")
        else:
            print("RESULT: no C620 feedback and no TX completion callback; inspect SDK callbacks and adapter error state.")
        return 0
    except KeyboardInterrupt:
        print("Stopped by user.")
        return 130
    except Exception as exc:
        print(f"FAIL: {type(exc).__name__}: {exc}")
        return 5
    finally:
        if context is not None:
            try:
                # Use the SDK's paired cleanup path once; do not close the
                # DmCanDevice separately because the context owns its handle.
                context.__exit__(None, None, None)
                context = None
            except Exception:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
