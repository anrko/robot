/*
 * Bounded, encoder-counted C620/M3508 wheel test.
 * Boot is zero-current. One explicit key runs one wheel only.
 */
#include "murax.h"

#define CAN_KEY                 0xC6200000u
#define C620_CURRENT_RAW        400       /* 0.488 A using +/-20 A -> +/-16384 */
#define C620_START_ASSIST_RAW   550       /* 0.671 A, bounded startup kick */
#define C620_START_ASSIST_MS    120u
#define ENCODER_COUNTS_REV      8192u
#define GEAR_NUM                3591u
#define GEAR_DEN                187u
#define WHEEL_TURNS_TARGET     3u
#define COUNTS_PER_WHEEL_REV   157313u   /* round(8192 * 3591 / 187) */
#define RUN_MAX_MS              10000u
#define RX_STALE_US             50000u
#define SPEED_LIMIT_RPM         550
#define OVERSPEED_CONFIRM_SAMPLES 3u
#define LOOP_DELAY_US           4000u
#define REPORT_PERIOD_US        250000u
#define COAST_CAPTURE_US        500000u

typedef struct {
    uint32_t count;
    uint32_t hi;
    uint32_t lo;
    uint16_t angle;
    int16_t rpm;
    int16_t current;
} c620_sample_t;

static int16_t signed16(uint32_t value)
{
    value &= 0xffffu;
    return (value & 0x8000u) ? (int16_t)((int32_t)value - 65536) : (int16_t)value;
}

static c620_sample_t sample_motor(uint8_t id)
{
    c620_sample_t s;
    if (id == 1u) {
        s.count = CAN1_M3508_ID1_COUNT;
        s.hi = CAN1_M3508_ID1_HI;
        s.lo = CAN1_M3508_ID1_LO;
    } else {
        s.count = CAN1_M3508_ID2_COUNT;
        s.hi = CAN1_M3508_ID2_HI;
        s.lo = CAN1_M3508_ID2_LO;
    }
    s.angle = (uint16_t)(s.hi >> 16);
    s.rpm = signed16(s.hi);
    s.current = signed16(s.lo >> 16);
    return s;
}

static void send_group_current(int16_t id1, int16_t id2)
{
    CAN1_DATA_HI = ((uint32_t)(uint16_t)id1 << 16) | (uint16_t)id2;
    CAN1_DATA_LO = 0u;
    CAN1_CTRL = CAN_KEY | 1u;
    CAN1_CTRL = CAN_KEY | 3u;
    delay_us(3000u);
    CAN1_CTRL = CAN_KEY;
}

static void send_zero(void)
{
    send_group_current(0, 0);
    send_group_current(0, 0);
    send_group_current(0, 0);
}

static void print_sample(const char *tag, const c620_sample_t *s,
                         int32_t total_ticks, uint8_t id)
{
    int32_t wheel_turns_milli = (int32_t)(((int64_t)total_ticks * 1000) / COUNTS_PER_WHEEL_REV);
    uart_puts(tag);
    uart_puts(" motor="); uart_putu32(id);
    uart_puts(" rx="); uart_putu32(s->count);
    uart_puts(" angle_raw="); uart_putu32(s->angle);
    uart_puts(" rpm="); uart_puti32(s->rpm);
    uart_puts(" current_raw="); uart_puti32(s->current);
    uart_puts(" motor_ticks="); uart_puti32(total_ticks);
    uart_puts(" wheel_turns_x1000="); uart_puti32(wheel_turns_milli);
    uart_puts("\r\n");
}

static uint32_t motor_count(uint8_t id)
{
    return id == 1u ? CAN1_M3508_ID1_COUNT : CAN1_M3508_ID2_COUNT;
}

static int wait_fresh_sample(uint8_t id, c620_sample_t *s)
{
    uint32_t before = motor_count(id);
    for (uint32_t elapsed = 0u; elapsed < 500000u; elapsed += 1000u) {
        int c = uart_getc();
        /* Serial terminals commonly append CR/LF to a one-key command.
         * Those line endings must not cancel the motor test. */
        if (c == 27 || c == 'x' || c == 'X') return 0;
        *s = sample_motor(id);
        if (s->count != before && s->count != 0u) return 1;
        delay_us(1000u);
    }
    return 0;
}

static int32_t encoder_delta(uint16_t now, uint16_t prev)
{
    int32_t d = (int32_t)now - (int32_t)prev;
    if (d > 4096) d -= 8192;
    else if (d < -4096) d += 8192;
    return d;
}

static void run_spin(uint8_t id, int8_t direction)
{
    c620_sample_t s, last;
    int32_t total_ticks = 0;
    uint32_t fail_before = CAN1_TX_FAIL_COUNT;
    uint32_t overspeed_count = 0u;
    uint64_t start_us, last_rx_us, last_report_us;
    uint32_t target_ticks = COUNTS_PER_WHEEL_REV * WHEEL_TURNS_TARGET;
    const int16_t current = (int16_t)(direction * C620_CURRENT_RAW);
    const int16_t id1_current = id == 1u ? current : 0;
    const int16_t id2_current = id == 2u ? current : 0;

    uart_puts("PRECHECK: DM is not commanded by this app; secure frame and lift both wheels.\r\n");
    uart_puts("Wait for fresh C620 feedback; press x or ESC to cancel before current is applied. CR/LF are ignored.\r\n");
    if (!wait_fresh_sample(id, &s)) {
        send_zero();
        uart_puts("ABORT: no fresh feedback or cancelled; zero-current sent.\r\n");
        return;
    }
    if (s.rpm > 20 || s.rpm < -20) {
        send_zero();
        uart_puts("ABORT: selected wheel is still moving; wait until it stops, then retry.\r\n");
        return;
    }
    last = s;
    print_sample("START", &s, 0, id);

    /*
     * A small, time-bounded kick helps overcome gearbox/tyre static
     * friction.  It is deliberately separate from the normal current so
     * that a wheel which does not start is stopped instead of being driven
     * indefinitely.  Any encoder movement is carried into total_ticks.
     */
    uart_puts("START ASSIST: current_raw=");
    uart_puti32((int32_t)direction * C620_START_ASSIST_RAW);
    uart_puts(" (~0.671 A) for 120 ms; then normal raw=");
    uart_puti32(current);
    uart_puts(" (~0.488 A).\r\n");
    {
        uint64_t assist_start = micros64();
        int assist_started = 0;
        int assist_abort = 0;
        while ((micros64() - assist_start) < (uint64_t)C620_START_ASSIST_MS * 1000u) {
            int c = uart_getc();
            uint64_t now;
            if (c >= 0 && c != '\r' && c != '\n') {
                uart_puts("STOP: key pressed during startup assist.\r\n");
                assist_abort = 1;
                break;
            }
            if (CAN1_TX_FAIL_COUNT != fail_before) {
                uart_puts("STOP: CAN TX failure during startup assist.\r\n");
                assist_abort = 1;
                break;
            }
            send_group_current(id1_current ?
                               (int16_t)(direction * C620_START_ASSIST_RAW) : 0,
                               id2_current ?
                               (int16_t)(direction * C620_START_ASSIST_RAW) : 0);
            delay_us(LOOP_DELAY_US);
            s = sample_motor(id);
            now = micros64();
            if (s.count != last.count) {
                int32_t d = encoder_delta(s.angle, last.angle);
                int32_t directed_ticks;
                total_ticks += d;
                directed_ticks = (int32_t)direction * total_ticks;
                last = s;
                last_rx_us = now;
                if (directed_ticks < -256) {
                    uart_puts("STOP: encoder moved opposite during startup assist.\r\n");
                    assist_abort = 1;
                    break;
                }
                if (s.rpm > SPEED_LIMIT_RPM || s.rpm < -SPEED_LIMIT_RPM)
                    overspeed_count++;
                else
                    overspeed_count = 0u;
                if (overspeed_count >= OVERSPEED_CONFIRM_SAMPLES) {
                    uart_puts("STOP: confirmed motor speed exceeded 550 rpm during startup assist.\r\n");
                    print_sample("OVERSPEED", &s, total_ticks, id);
                    assist_abort = 1;
                    break;
                }
                if (d != 0) assist_started = 1;
            }
        }
        if (!assist_started && !assist_abort) {
            uart_puts("START ASSIST FAILED: no encoder movement; zero current sent.\r\n");
            assist_abort = 1;
        }
        if (assist_abort) {
            send_zero();
            return;
        }
        uart_puts("START ASSIST OK: encoder movement detected; switching to normal current.\r\n");
    }

    uart_puts("RUN: current_raw="); uart_puti32(current);
    uart_puts(" (~0.488 A), target=3 tire turns; 10 s limit; any non-CR/LF key stops.\r\n");

    start_us = micros64();
    last_rx_us = start_us;
    last_report_us = start_us;
    while ((micros64() - start_us) < (uint64_t)RUN_MAX_MS * 1000u) {
        uint64_t now;
        int c = uart_getc();
        /* Ignore terminal line endings; any other key is an explicit stop. */
        if (c >= 0 && c != '\r' && c != '\n') {
            uart_puts("STOP: key pressed.\r\n");
            break;
        }
        if (CAN1_TX_FAIL_COUNT != fail_before) {
            uart_puts("STOP: CAN TX failure.\r\n");
            break;
        }

        send_group_current(id1_current, id2_current);
        delay_us(LOOP_DELAY_US);
        s = sample_motor(id);
        now = micros64();
        if (s.count != last.count) {
            int32_t d = encoder_delta(s.angle, last.angle);
            int32_t directed_ticks;
            total_ticks += d;
            directed_ticks = (int32_t)direction * total_ticks;
            last = s;
            last_rx_us = now;
            if (s.rpm > SPEED_LIMIT_RPM || s.rpm < -SPEED_LIMIT_RPM)
                overspeed_count++;
            else
                overspeed_count = 0u;
            if (overspeed_count >= OVERSPEED_CONFIRM_SAMPLES) {
                uart_puts("STOP: confirmed motor speed exceeded 550 rpm limit.\r\n");
                print_sample("OVERSPEED", &s, total_ticks, id);
                break;
            }
            if (directed_ticks < -256) {
                uart_puts("STOP: encoder moved opposite to the requested direction; check motor sign.\r\n");
                break;
            }
            if (directed_ticks >= 0 && (uint32_t)directed_ticks >= target_ticks) {
                uart_puts("STOP: encoder-counted three tire turns reached.\r\n");
                break;
            }
            if ((now - last_report_us) >= REPORT_PERIOD_US) {
                print_sample("LIVE", &s, total_ticks, id);
                last_report_us = now;
            }
        } else if ((now - last_rx_us) > RX_STALE_US) {
            uart_puts("STOP: C620 feedback stale for 50 ms.\r\n");
            break;
        }
    }

    if ((micros64() - start_us) >= (uint64_t)RUN_MAX_MS * 1000u)
        uart_puts("STOP: 10 s time limit.\r\n");
    send_zero();

    /* Include coasting after the zero-current command in the travel measurement. */
    {
        uint64_t coast_start = micros64();
        uint64_t coast_last_rx = coast_start;
        while ((micros64() - coast_start) < COAST_CAPTURE_US) {
            s = sample_motor(id);
            if (s.count != last.count) {
                total_ticks += encoder_delta(s.angle, last.angle);
                last = s;
                coast_last_rx = micros64();
            } else if ((micros64() - coast_last_rx) > RX_STALE_US) {
                break;
            }
            delay_us(1000u);
        }
    }
    send_zero();
    s = sample_motor(id);
    print_sample("FINAL", &s, total_ticks, id);
    uart_puts("CAN1 ack/fail="); uart_putu32(CAN1_TX_ACK_COUNT);
    uart_putc('/'); uart_putu32(CAN1_TX_FAIL_COUNT);
    uart_puts(" (fail delta="); uart_putu32(CAN1_TX_FAIL_COUNT - fail_before);
    uart_puts(").\r\nZERO CURRENT sent to both C620 slots.\r\n");
}

int main(void)
{
    board_init();
    CAN0_CTRL = CAN_KEY;
    CAN1_CTRL = CAN_KEY;
    send_zero();
    uart_puts("\r\n--- C620 bounded wheel-rotation test ---\r\n");
    uart_puts("BOOT SAFE: DM untouched; both C620 currents zero. USB_DEBUG 115200 8-N-1.\r\n");
    uart_puts("a=ID1 encoder+; z=ID1 encoder-; k=ID2 encoder+; m=ID2 encoder-.\r\n");
    uart_puts("Each command requests 0.488 A until 3 tire turns, max 10 s; any non-CR/LF key aborts.\r\n");
    uart_puts("Feedback must be fresh; speed limit 550 motor rpm; zero current on every exit.\r\n");
    uart_puts("Keep wheels raised, mechanism supported, and motor-power cutoff reachable.\r\n");
    for (;;) {
        int c = uart_getc();
        if (c == 'a') run_spin(1u, 1);
        else if (c == 'z') run_spin(1u, -1);
        else if (c == 'k') run_spin(2u, 1);
        else if (c == 'm') run_spin(2u, -1);
        else if (c == 'd' || c == 'D' || c == 27) {
            send_zero();
            uart_puts("ZERO CURRENT sent.\r\n");
        } else if (c == 's' || c == 'S') {
            c620_sample_t s1 = sample_motor(1u), s2 = sample_motor(2u);
            print_sample("STATUS", &s1, 0, 1u);
            print_sample("STATUS", &s2, 0, 2u);
        } else if (c == '\r' || c == '\n' || c == ' ') { }
        else if (c >= 0) uart_puts("Use a/z (ID1), k/m (ID2), s=status, d=zero.\r\n");
    }
}
