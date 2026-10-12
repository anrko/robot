/*
 * ACG138 RK3588 UDP relay: FPGA/RGMII eth0 -> Wi-Fi -> PC.
 *
 * Usage on the Buildroot board:
 *   ./rk3588_udp_wifi_relay 192.168.1.100 6102 6102 wlan0
 *
 * The FPGA packets are forwarded byte-for-byte.  6102 is the verified
 * 1280x720 RGB565 camera port; both 2562-byte camera rows and 2560-byte
 * legacy rows are accepted.
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <net/if.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define LINE_BYTES (1280U * 2U)
#define MAX_PACKET (LINE_BYTES + 2U)
#define DEFAULT_PORT 6102

static volatile sig_atomic_t running = 1;
static void stop_relay(int sig) { (void)sig; running = 0; }

static int parse_port(const char *text, unsigned short *port)
{
    char *end = NULL;
    unsigned long value = strtoul(text, &end, 10);
    if (text[0] == '\0' || end == NULL || *end != '\0' || value > 65535U)
        return -1;
    *port = (unsigned short)value;
    return 0;
}

int main(int argc, char **argv)
{
    const char *target_ip;
    const char *device = NULL;
    unsigned short target_port = DEFAULT_PORT, listen_port = DEFAULT_PORT;
    struct sockaddr_in target, local;
    int in_fd = -1, out_fd = -1;
    int receive_buffer = 16 * 1024 * 1024;
    unsigned char packet[MAX_PACKET];
    unsigned long long packets = 0, bytes = 0, bad = 0;
    time_t next_report;

    if (argc < 2 || argc > 5) {
        fprintf(stderr, "usage: %s PC_IP [PC_PORT] [LISTEN_PORT] [WIFI_IFACE]\n", argv[0]);
        return 2;
    }
    target_ip = argv[1];
    if (argc >= 3 && parse_port(argv[2], &target_port) < 0) {
        fprintf(stderr, "invalid PC port: %s\n", argv[2]); return 2;
    }
    if (argc >= 4 && parse_port(argv[3], &listen_port) < 0) {
        fprintf(stderr, "invalid listen port: %s\n", argv[3]); return 2;
    }
    if (argc == 5) device = argv[4];

    memset(&target, 0, sizeof(target));
    target.sin_family = AF_INET;
    target.sin_port = htons(target_port);
    if (inet_pton(AF_INET, target_ip, &target.sin_addr) != 1) {
        fprintf(stderr, "invalid PC IPv4 address: %s\n", target_ip); return 2;
    }
    memset(&local, 0, sizeof(local));
    local.sin_family = AF_INET;
    local.sin_port = htons(listen_port);
    local.sin_addr.s_addr = htonl(INADDR_ANY);

    in_fd = socket(AF_INET, SOCK_DGRAM, 0);
    out_fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (in_fd < 0 || out_fd < 0) { perror("socket"); goto fail; }
    if (setsockopt(in_fd, SOL_SOCKET, SO_RCVBUF, &receive_buffer,
                   sizeof(receive_buffer)) < 0)
        perror("warning: SO_RCVBUF");
    if (bind(in_fd, (struct sockaddr *)&local, sizeof(local)) < 0) {
        perror("bind UDP input"); goto fail;
    }
#ifdef SO_BINDTODEVICE
    if (device != NULL && setsockopt(out_fd, SOL_SOCKET, SO_BINDTODEVICE,
                                     device, strlen(device) + 1) < 0) {
        perror("SO_BINDTODEVICE (continue with route-selected interface)");
    }
#else
    (void)device;
#endif

    signal(SIGINT, stop_relay);
    signal(SIGTERM, stop_relay);
    next_report = time(NULL) + 1;
    fprintf(stderr, "relay UDP 0.0.0.0:%u -> %s:%u",
            (unsigned)listen_port, target_ip, (unsigned)target_port);
    if (device != NULL) fprintf(stderr, " via %s", device);
    fprintf(stderr, "\n");

    while (running) {
        ssize_t received = recvfrom(in_fd, packet, sizeof(packet), 0, NULL, NULL);
        if (received < 0) {
            if (errno == EINTR) continue;
            perror("recvfrom"); break;
        }
        if (received != (ssize_t)LINE_BYTES && received != (ssize_t)MAX_PACKET) {
            bad++;
            continue;
        }
        if (sendto(out_fd, packet, (size_t)received, 0,
                   (struct sockaddr *)&target, sizeof(target)) != received) {
            perror("sendto");
            continue;
        }
        packets++;
        bytes += (unsigned long long)received;
        if (time(NULL) >= next_report) {
            fprintf(stderr, "RX/forward packets=%llu bytes=%llu bad_length=%llu\n",
                    packets, bytes, bad);
            next_report = time(NULL) + 1;
        }
    }

    close(in_fd); close(out_fd);
    return 0;
fail:
    if (in_fd >= 0) close(in_fd);
    if (out_fd >= 0) close(out_fd);
    return 1;
}
