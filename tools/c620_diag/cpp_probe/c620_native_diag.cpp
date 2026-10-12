#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <thread>

#include "dmcan.h"

static std::atomic<unsigned> rx_count{0};
static std::atomic<unsigned> tx_count{0};

static void print_frame(const char* direction, usb_rx_frame_t* frame) {
    const auto& h = frame->head;
    const int len = dmcan_utils_get_len_from_dlc(h.dlc);
    std::printf("%s ch=%u %s %s id=0x%03X dlc=%u ack=%u data=",
                direction, h.channel, h.ext ? "EXT" : "STD",
                h.canfd ? "CAN-FD" : "CAN2.0", h.can_id,
                static_cast<unsigned>(h.dlc), static_cast<unsigned>(h.ack));
    for (int i = 0; i < len && i < 64; ++i)
        std::printf("%02X ", frame->payload[i]);
    std::putchar('\n');
    std::fflush(stdout);
}

static void on_receive(dmcan_device_handle*, usb_rx_frame_t* frame) {
    ++rx_count;
    print_frame("RX", frame);
}

static void on_sent(dmcan_device_handle*, usb_rx_frame_t* frame) {
    ++tx_count;
    print_frame("TX", frame);
}

static void on_error(dmcan_device_handle*, usb_rx_frame_t* frame) {
    print_frame("ERR", frame);
}

int main(int argc, char** argv) {
    bool send_zero = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--send-zero") == 0) send_zero = true;
        else {
            std::printf("Usage: %s [--send-zero]\n", argv[0]);
            return 2;
        }
    }

    dmcan_context* ctx = nullptr;
    dmcan_context_create(&ctx);
    if (!ctx) {
        std::puts("FAIL: could not create SDK context");
        return 2;
    }

    int result = 1;
    dmcan_device_handle* dev = nullptr;
    bool opened = false;
    dmcan_print_version(ctx);
    const int count = dmcan_find_devices(ctx);
    std::printf("Devices found: %d\n", count);
    dmcan_show_all_devices(ctx);
    if (count < 1 || !dmcan_device_get(ctx, &dev, 0) || !dev) {
        std::puts("FAIL: no DM USB-CAN device found");
        goto cleanup;
    }
    opened = dmcan_device_open(dev);
    std::printf("Device open: %s\n", opened ? "OK" : "FAIL");
    if (!opened) goto cleanup;
    dmcan_device_print_version(dev);

    {
        dmcan_channel_can_info_t info{};
        if (!dmcan_device_get_channel_baudrate(dev, 0, &info)) {
            std::puts("FAIL: cannot read channel 0 configuration");
            goto cleanup;
        }
        std::printf("Channel 0: CAN-FD=%u nominal=%u data=%u\n",
                    static_cast<unsigned>(info.canfd), info.can_baudrate,
                    info.canfd_baudrate);
        if (info.canfd || info.can_baudrate != 1000000) {
            std::puts("FAIL: expected classic CAN at 1 Mbps; configure that in DM Tool, then retry");
            goto cleanup;
        }
    }

    if (!dmcan_device_enable_channel(dev, 0)) {
        std::puts("FAIL: SDK could not enable channel 0");
        goto cleanup;
    }
    std::puts("Channel 0 enable: OK");
    dmcan_device_hook_recv_callback(dev, on_receive);
    dmcan_device_hook_sent_callback(dev, on_sent);
    dmcan_device_hook_err_callback(dev, on_error);

    std::puts("Listening for 15 seconds. No CAN frames will be sent.");
    std::this_thread::sleep_for(std::chrono::seconds(15));
    std::printf("Listen result: RX frames=%u\n", rx_count.load());

    if (send_zero) {
        std::puts("Sending 0x200 zero-current command: STD, DLC=8, data=00 00 00 00 00 00 00 00, 10 Hz for 3 s.");
        std::puts("Only do this with the motor secured and unloaded.");
        uint8_t payload[8] = {};
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
        while (std::chrono::steady_clock::now() < deadline) {
            if (!dmcan_device_send_can(dev, 0, 0x200, false, false, false, false, 8, payload))
                std::puts("SDK rejected a send request");
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        std::this_thread::sleep_for(std::chrono::seconds(2));
        std::printf("After send: RX frames=%u TX callbacks=%u\n", rx_count.load(), tx_count.load());
    }

    result = 0;
cleanup:
    if (opened) dmcan_device_close(dev);
    dmcan_context_destroy(ctx);
    return result;
}
