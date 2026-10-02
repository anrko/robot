#include <arpa/inet.h>
#include <errno.h>
#include <gst/app/gstappsrc.h>
#include <gst/gst.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define WIDTH 1280
#define HEIGHT 720
#define LINE_BYTES (WIDTH * 2)
#define CAMERA_PACKET_BYTES (LINE_BYTES + 2)
#define FRAME_BYTES (LINE_BYTES * HEIGHT)
#define UDP_PORT 6102

static volatile sig_atomic_t running = 1;

static void stop_running(int signal_number)
{
    (void)signal_number;
    running = 0;
}

static uint64_t monotonic_ns(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static int report_bus_error(GstElement *pipeline)
{
    GstBus *bus = gst_element_get_bus(pipeline);
    GstMessage *message = gst_bus_pop_filtered(
        bus, GST_MESSAGE_ERROR | GST_MESSAGE_EOS);

    gst_object_unref(bus);
    if (message == NULL)
        return 0;

    if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_ERROR) {
        GError *error = NULL;
        gchar *debug = NULL;

        gst_message_parse_error(message, &error, &debug);
        fprintf(stderr, "GStreamer error: %s\n", error->message);
        if (debug != NULL)
            fprintf(stderr, "GStreamer debug: %s\n", debug);
        g_clear_error(&error);
        g_free(debug);
    } else {
        fprintf(stderr, "GStreamer pipeline reached EOS\n");
    }
    gst_message_unref(message);
    return -1;
}

int main(int argc, char **argv)
{
    const char *pipeline_description =
        "appsrc name=source is-live=true format=time block=false "
        "caps=video/x-raw,format=RGB16,width=1280,height=720,framerate=30/1 "
        "! queue leaky=downstream max-size-buffers=2 "
        "! videoconvert ! waylandsink sync=false";
    GstElement *pipeline = NULL;
    GstElement *source = NULL;
    GError *gst_error = NULL;
    struct sockaddr_in address;
    uint8_t packet[CAMERA_PACKET_BYTES];
    uint8_t *frame = NULL;
    uint8_t row_seen[HEIGHT] = {0};
    uint64_t packets = 0;
    uint64_t bad_packets = 0;
    unsigned bad_samples = 0;
    uint64_t frames = 0;
    unsigned rows_in_frame = 0;
    unsigned sequential_row = 0;
    int sequential_mode = 0;
    uint64_t next_frame_ns;
    uint64_t next_report_ns;
    int receive_buffer = 8 * 1024 * 1024;
    int socket_fd = -1;
    int result = 1;

    (void)argc;
    (void)argv;
    signal(SIGINT, stop_running);
    signal(SIGTERM, stop_running);

    if (getenv("XDG_RUNTIME_DIR") == NULL)
        setenv("XDG_RUNTIME_DIR", "/run", 1);
    if (getenv("WAYLAND_DISPLAY") == NULL)
        setenv("WAYLAND_DISPLAY", "wayland-0", 1);

    socket_fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (socket_fd < 0) {
        perror("socket");
        goto cleanup;
    }
    if (setsockopt(socket_fd, SOL_SOCKET, SO_RCVBUF, &receive_buffer,
                   sizeof(receive_buffer)) < 0)
        perror("warning: SO_RCVBUF");

    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(UDP_PORT);
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(socket_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind UDP 6102");
        goto cleanup;
    }

    frame = malloc(FRAME_BYTES);
    if (frame == NULL) {
        perror("malloc frame");
        goto cleanup;
    }

    gst_init(NULL, NULL);
    pipeline = gst_parse_launch(pipeline_description, &gst_error);
    if (pipeline == NULL) {
        fprintf(stderr, "Cannot create GStreamer pipeline: %s\n",
                gst_error != NULL ? gst_error->message : "unknown error");
        g_clear_error(&gst_error);
        goto cleanup;
    }
    source = gst_bin_get_by_name(GST_BIN(pipeline), "source");
    if (source == NULL) {
        fprintf(stderr, "Cannot find appsrc in pipeline\n");
        goto cleanup;
    }
    if (gst_element_set_state(pipeline, GST_STATE_PLAYING) ==
        GST_STATE_CHANGE_FAILURE) {
        fprintf(stderr, "Cannot start GStreamer pipeline\n");
        goto cleanup;
    }

    fprintf(stderr,
            "Listening on UDP %d for 1280x720 RGB565; expected 2562-byte camera rows with 2-byte little-endian row index; Ctrl+C stops\n",
            UDP_PORT);
    next_frame_ns = monotonic_ns();
    next_report_ns = next_frame_ns + 1000000000ULL;

    while (running) {
        ssize_t received = recv(socket_fd, packet, sizeof(packet), 0);
        uint64_t now;
        int camera_frame_complete = 0;

        if (received < 0) {
            if (errno == EINTR)
                continue;
            perror("recv");
            break;
        }
        now = monotonic_ns();
        if (received == CAMERA_PACKET_BYTES) {
            unsigned camera_row = (unsigned)packet[0] |
                                  ((unsigned)packet[1] << 8);

            if (!sequential_mode && camera_row >= HEIGHT) {
                sequential_mode = 1;
                sequential_row = 0;
                rows_in_frame = 0;
                memset(row_seen, 0, sizeof(row_seen));
                fprintf(stderr,
                        "No valid row header detected; using packet-order compatibility mode\n");
            }
            if (!sequential_mode && camera_row == 0 && rows_in_frame != 0) {
                memset(row_seen, 0, sizeof(row_seen));
                rows_in_frame = 0;
            }

            /* The sensor sends RGB565 high byte first; appsrc's RGB16 caps
             * use native-endian 16-bit pixels on this little-endian RK3588. */
            unsigned output_row = sequential_mode ? sequential_row : camera_row;
            for (unsigned x = 0; x < LINE_BYTES; x += 2) {
                size_t dst = (size_t)output_row * LINE_BYTES + x;
                frame[dst] = packet[2 + x + 1];
                frame[dst + 1] = packet[2 + x];
            }
            if (!row_seen[output_row]) {
                row_seen[output_row] = 1;
                rows_in_frame++;
            }
            if (sequential_mode) {
                sequential_row++;
                if (sequential_row == HEIGHT)
                    sequential_row = 0;
            }
            packets++;
            if (rows_in_frame != HEIGHT) {
                if (now >= next_report_ns) {
                    fprintf(stderr,
                            "RX packets=%llu bad_length=%llu camera_rows=%u displayed_frames=%llu\n",
                            (unsigned long long)packets,
                            (unsigned long long)bad_packets, rows_in_frame,
                            (unsigned long long)frames);
                    next_report_ns = now + 1000000000ULL;
                    if (report_bus_error(pipeline) < 0)
                        break;
                }
                continue;
            }
            camera_frame_complete = 1;
        } else if (received == LINE_BYTES) {
            /* Keep the verified colorbar format working: one full pixel row
             * per datagram, repeated to fill a visible frame. */
            packets++;
            if (now < next_frame_ns)
                continue;
            for (int row = 0; row < HEIGHT; row++)
                memcpy(frame + (size_t)row * LINE_BYTES, packet, LINE_BYTES);
        } else {
            bad_packets++;
            if (bad_samples < 5) {
                fprintf(stderr,
                        "Rejected datagram: len=%zd first_bytes=%02x %02x (expected %d camera / %d legacy)\n",
                        received, received > 0 ? packet[0] : 0,
                        received > 1 ? packet[1] : 0,
                        CAMERA_PACKET_BYTES, LINE_BYTES);
                bad_samples++;
            }
            if (now >= next_report_ns) {
                fprintf(stderr,
                        "RX packets=%llu bad_length=%llu camera_rows=%u displayed_frames=%llu\n",
                        (unsigned long long)packets,
                        (unsigned long long)bad_packets, rows_in_frame,
                        (unsigned long long)frames);
                next_report_ns = now + 1000000000ULL;
            }
            continue;
        }

        GstBuffer *buffer = gst_buffer_new_allocate(NULL, FRAME_BYTES, NULL);
        GstFlowReturn flow;

        if (buffer == NULL) {
            fprintf(stderr, "Cannot allocate GStreamer frame buffer\n");
            break;
        }
        gst_buffer_fill(buffer, 0, frame, FRAME_BYTES);
        GST_BUFFER_PTS(buffer) = frames * GST_SECOND / 30;
        GST_BUFFER_DURATION(buffer) = GST_SECOND / 30;
        flow = gst_app_src_push_buffer(GST_APP_SRC(source), buffer);
        if (flow != GST_FLOW_OK) {
            fprintf(stderr, "appsrc stopped with flow status %d\n", flow);
            break;
        }
        frames++;
        next_frame_ns = now + 33333333ULL;
        if (camera_frame_complete) {
            rows_in_frame = 0;
            memset(row_seen, 0, sizeof(row_seen));
        }

        if (now >= next_report_ns) {
            fprintf(stderr,
                    "RX packets=%llu bad_length=%llu camera_rows=%u displayed_frames=%llu\n",
                    (unsigned long long)packets,
                    (unsigned long long)bad_packets, rows_in_frame,
                    (unsigned long long)frames);
            next_report_ns = now + 1000000000ULL;
            if (report_bus_error(pipeline) < 0)
                break;
        }
    }

    result = 0;

cleanup:
    if (source != NULL) {
        gst_app_src_end_of_stream(GST_APP_SRC(source));
        gst_object_unref(source);
    }
    if (pipeline != NULL) {
        gst_element_set_state(pipeline, GST_STATE_NULL);
        gst_object_unref(pipeline);
    }
    free(frame);
    if (socket_fd >= 0)
        close(socket_fd);
    return result;
}
