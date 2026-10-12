/* DM4310 runtime feedback probe.
 *
 * This application is deliberately manual: it never enables a motor at boot.
 * Press 'p' only with the selected motor mechanically secured and an emergency
 * power cut available. It sends one enable frame, waits briefly for the
 * feedback response, prints the decoded frame, and then sends disable.
 */
#include "murax.h"

#define CAN_KEY 0xC6200000u
#define DM_STATUS_ENABLED 1u

static void put_signed_milli(int32_t value)
{
    if (value < 0) { uart_putc('-'); value = -value; }
    uart_putu32((uint32_t)(value / 1000));
    uart_putc('.');
    uart_putu32((uint32_t)(value % 1000) / 100u);
    uart_putu32((uint32_t)(value % 100u) / 10u);
    uart_putu32((uint32_t)(value % 10u));
}

static int32_t map_position_mrad(uint32_t raw)
{
    return (int32_t)(((uint64_t)raw * 25000u) / 65535u) - 12500;
}

static int32_t map_12bit_milli(uint32_t raw, int32_t full_scale)
{
    return (int32_t)(((uint64_t)raw * (uint32_t)(2 * full_scale)) / 4095u) - full_scale;
}

static void print_feedback(uint8_t motor_id)
{
    uint32_t count;
    uint32_t hi;
    uint32_t lo;
    uint32_t d0;
    uint32_t p_raw;
    uint32_t v_raw;
    uint32_t t_raw;
    int32_t pos_mrad;
    int32_t vel_mrad_s;
    int32_t torque_mnm;

    if (motor_id == 1u) { count = CAN0_DM_ID1_COUNT; hi = CAN0_DM_ID1_HI; lo = CAN0_DM_ID1_LO; }
    else if (motor_id == 2u) { count = CAN0_DM_ID2_COUNT; hi = CAN0_DM_ID2_HI; lo = CAN0_DM_ID2_LO; }
    else if (motor_id == 3u) { count = CAN0_DM_ID3_COUNT; hi = CAN0_DM_ID3_HI; lo = CAN0_DM_ID3_LO; }
    else { count = CAN0_DM_ID4_COUNT; hi = CAN0_DM_ID4_HI; lo = CAN0_DM_ID4_LO; }

    d0 = (hi >> 24) & 0xffu;
    p_raw = (hi >> 8) & 0xffffu;
    v_raw = ((hi & 0xffu) << 4) | ((lo >> 28) & 0x0fu);
    t_raw = ((lo >> 16) & 0xffu) | (((lo >> 24) & 0x0fu) << 8);
    pos_mrad = map_position_mrad(p_raw);
    vel_mrad_s = map_12bit_milli(v_raw, 30000);
    torque_mnm = map_12bit_milli(t_raw, 10000);

    uart_puts("DM"); uart_putu32(motor_id);
    uart_puts(" count="); uart_putu32(count);
    uart_puts(" state=0x"); uart_puthex8((d0 >> 4) & 0x0fu);
    uart_puts(" id="); uart_putu32(d0 & 0x0fu);
    uart_puts(" pos_rad="); put_signed_milli(pos_mrad);
    uart_puts(" vel_rad_s="); put_signed_milli(vel_mrad_s);
    uart_puts(" torque_Nm="); put_signed_milli(torque_mnm);
    uart_puts(" Tmos="); uart_putu32((lo >> 8) & 0xffu);
    uart_puts(" Trotor="); uart_putu32(lo & 0xffu);
    uart_puts(" raw="); uart_puthex32(hi); uart_puthex32(lo);
    uart_puts("\r\n");
}

static uint32_t feedback_count(uint8_t motor_id)
{
    if (motor_id == 1u) return CAN0_DM_ID1_COUNT;
    if (motor_id == 2u) return CAN0_DM_ID2_COUNT;
    if (motor_id == 3u) return CAN0_DM_ID3_COUNT;
    return CAN0_DM_ID4_COUNT;
}

static int wait_for_feedback(uint8_t motor_id, uint32_t before, uint32_t timeout_us)
{
    while (timeout_us != 0u) {
        if (feedback_count(motor_id) != before) return 1;
        delay_us(100u);
        timeout_us -= (timeout_us >= 100u) ? 100u : timeout_us;
    }
    return feedback_count(motor_id) != before;
}

static void send_frame(uint8_t motor_id, uint32_t hi, uint32_t lo)
{
    CAN0_TX_ID = CAN_KEY | motor_id;
    CAN0_DATA_HI = hi;
    CAN0_DATA_LO = lo;
    CAN0_CTRL = CAN_KEY | 1u;
    CAN0_CTRL = CAN_KEY | 3u;
    delay_us(4000u);
    CAN0_CTRL = CAN_KEY;
}

static void probe_motor(uint8_t motor_id)
{
    uint32_t before;
    uint32_t after_enable;

    before = feedback_count(motor_id);
    uart_puts("Probe DM"); uart_putu32(motor_id);
    uart_puts(": ENABLE, wait for feedback, then DISABLE\r\n");
    send_frame(motor_id, 0xffffffffu, 0xffffff00u | 0xfcu);
    if (wait_for_feedback(motor_id, before, 30000u)) print_feedback(motor_id);
    else uart_puts("  no Master-ID-0 feedback; check mode, wiring and timeout\r\n");
    after_enable = feedback_count(motor_id);

    send_frame(motor_id, 0xffffffffu, 0xffffff00u | 0xfdu);
    if (wait_for_feedback(motor_id, after_enable, 30000u)) print_feedback(motor_id);
    else uart_puts("  no disable feedback\r\n");
}

/* A disable command requests status without enabling the motor. */
static void refresh_disabled(uint8_t motor_id)
{
    uint32_t before = feedback_count(motor_id);
    send_frame(motor_id, 0xffffffffu, 0xfffffffdu);
    if (wait_for_feedback(motor_id, before, 30000u)) print_feedback(motor_id);
    else {
        uart_puts("DM"); uart_putu32(motor_id);
        uart_puts(" NO FRESH DISABLE FEEDBACK\r\n");
    }
}

int main(void)
{
    board_init();
    CAN0_CTRL = CAN_KEY;
    CAN1_CTRL = CAN_KEY;
    uart_puts("\r\n--- DM4310 runtime feedback probe ---\r\n");
    uart_puts("TX is disabled at boot. Press p to probe DM1..DM4 one at a time.\r\n");
    uart_puts("r=fresh disabled feedback for IDs 1..4; s=cached data; p=enable/disable probe.\r\n");
    uart_puts("Scales assumed: PMAX=12.5 VMAX=30 TMAX=10; verify motor settings.\r\n");
    uart_puts("Secure the mechanism, use low motor power, and keep an emergency cut-off ready.\r\n");
    uart_puts("Feedback: state 1=enabled, 0=disabled; position rad, velocity rad/s, torque Nm.\r\n");

    for (;;) {
        if (uart_rx_count()) {
            int c = uart_getc();
            if (c == 'p' || c == 'P') {
                probe_motor(1u); delay_us(50000u);
                probe_motor(2u); delay_us(50000u);
                probe_motor(3u); delay_us(50000u);
                probe_motor(4u);
            } else if (c == 'r' || c == 'R') {
                refresh_disabled(1u); refresh_disabled(2u);
                refresh_disabled(3u); refresh_disabled(4u);
            } else if (c == 's' || c == 'S') {
                print_feedback(1u); print_feedback(2u);
                print_feedback(3u); print_feedback(4u);
            }
        }
    }
}
