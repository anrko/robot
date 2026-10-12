/*
 * FPGA wheel-legged balance-control framework.
 *
 * This is the software skeleton for the Murax/VexRiscv CPU.  It deliberately
 * starts in SAFE and never enables a motor automatically.  The BMI088 input
 * is present in RobotApb, but BALANCE_IMU_STUB keeps the controller disarmed
 * until the installed sensor mapping and calibration have been confirmed.
 *
 * Control-rate plan (1 kHz): one CAN frame is scheduled per tick.  The five
 * slots are C620 group-current, then DM4310 IDs 1..4.  This avoids blocking in
 * the timer ISR while still refreshing every device at 200 Hz.  The final
 * controller can replace balance_compute() without changing the CAN packing.
 */
#include "murax.h"

#define CAN_KEY 0xC6200000u
#define BALANCE_IMU_STUB 1
#define BALANCE_OUTPUT_ENABLE 0

#define DM_COUNT 4u
#define TX_SLOTS 5u
#define FRESH_TICKS 20u

typedef enum {
    CTRL_SAFE = 0,
    CTRL_ARMING = 1,
    CTRL_ACTIVE = 2,
    CTRL_DISARMING = 3
} control_state_t;

typedef struct {
    q16_t pos;
    q16_t vel;
    q16_t torque;
    uint32_t count;
    uint32_t age;
    uint8_t state;
    uint8_t id;
} dm_feedback_t;

typedef struct {
    int32_t angle;
    int32_t rpm;
    int32_t current;
    uint32_t count;
    uint32_t age;
    uint8_t temp;
} wheel_feedback_t;

typedef struct {
    q16_t pitch_deg;
    q16_t pitch_rate_dps;
    q16_t wheel_speed;
    q16_t wheel_position;
    q16_t joint_position[DM_COUNT];
    q16_t joint_velocity[DM_COUNT];
    int valid;
} balance_input_t;

typedef struct {
    q16_t wheel_current;
    q16_t joint_torque[DM_COUNT];
} balance_output_t;

/* These are intentionally conservative placeholders.  Do not tune them
 * from the endpoint values: endpoint values are mechanical limits, not the
 * balance pose.  Press 'q' while disarmed to capture the actual standing pose. */
static q16_t stand_ref[DM_COUNT];
static int stand_ref_valid;

static volatile control_state_t control_state = CTRL_SAFE;
static volatile uint32_t control_ticks;
static volatile uint32_t skipped_tx;
static volatile uint32_t safety_trips;
static volatile uint32_t tx_phase;

static dm_feedback_t dm[DM_COUNT];
static wheel_feedback_t wheel[2];
static balance_input_t balance_in;
static balance_output_t balance_out;

static uint32_t dm_count(uint32_t i)
{
    if (i == 0u) return CAN0_DM_ID1_COUNT;
    if (i == 1u) return CAN0_DM_ID2_COUNT;
    if (i == 2u) return CAN0_DM_ID3_COUNT;
    return CAN0_DM_ID4_COUNT;
}

static uint32_t dm_hi(uint32_t i)
{
    if (i == 0u) return CAN0_DM_ID1_HI;
    if (i == 1u) return CAN0_DM_ID2_HI;
    if (i == 2u) return CAN0_DM_ID3_HI;
    return CAN0_DM_ID4_HI;
}

static uint32_t dm_lo(uint32_t i)
{
    if (i == 0u) return CAN0_DM_ID1_LO;
    if (i == 1u) return CAN0_DM_ID2_LO;
    if (i == 2u) return CAN0_DM_ID3_LO;
    return CAN0_DM_ID4_LO;
}

static q16_t dm_position(uint32_t raw)
{
    int32_t mrad = (int32_t)(((uint64_t)(raw & 0xffffu) * 25000u) / 65535u) - 12500;
    return q16_from_milli(mrad);
}

static q16_t dm_signed12(uint32_t raw, int32_t full_scale)
{
    int32_t milli = (int32_t)(((uint64_t)(raw & 0xfffu) * (uint32_t)(2 * full_scale)) / 4095u) - full_scale;
    return q16_from_milli(milli);
}

static int32_t signed16(uint32_t v)
{
    int32_t x = (int32_t)(v & 0xffffu);
    return (x & 0x8000) ? x - 0x10000 : x;
}

static void sample_feedback(void)
{
    uint32_t i;
    for (i = 0u; i < DM_COUNT; i++) {
        uint32_t hi = dm_hi(i);
        uint32_t lo = dm_lo(i);
        uint32_t count = dm_count(i);
        uint32_t p_raw = (hi >> 8) & 0xffffu;
        uint32_t v_raw = ((hi & 0xffu) << 4) | ((lo >> 28) & 0xfu);
        uint32_t t_raw = ((lo >> 16) & 0xffu) | (((lo >> 24) & 0xfu) << 8);
        if (count != dm[i].count) dm[i].age = 0u;
        else if (dm[i].age < 0xffffffffu) dm[i].age++;
        dm[i].count = count;
        dm[i].pos = dm_position(p_raw);
        dm[i].vel = dm_signed12(v_raw, 30000);
        dm[i].torque = dm_signed12(t_raw, 10000);
        dm[i].state = (uint8_t)((hi >> 28) & 0xfu);
        dm[i].id = (uint8_t)((hi >> 24) & 0xfu);
    }

    {
        uint32_t hi = CAN1_M3508_ID1_HI;
        uint32_t lo = CAN1_M3508_ID1_LO;
        uint32_t count = CAN1_M3508_ID1_COUNT;
        if (count != wheel[0].count) wheel[0].age = 0u;
        else if (wheel[0].age < 0xffffffffu) wheel[0].age++;
        wheel[0].count = count;
        wheel[0].angle = (int32_t)((hi >> 16) & 0xffffu);
        wheel[0].rpm = signed16(hi);
        wheel[0].current = signed16(lo >> 16);
        wheel[0].temp = (uint8_t)((lo >> 8) & 0xffu);
    }
    {
        uint32_t hi = CAN1_M3508_ID2_HI;
        uint32_t lo = CAN1_M3508_ID2_LO;
        uint32_t count = CAN1_M3508_ID2_COUNT;
        if (count != wheel[1].count) wheel[1].age = 0u;
        else if (wheel[1].age < 0xffffffffu) wheel[1].age++;
        wheel[1].count = count;
        wheel[1].angle = (int32_t)((hi >> 16) & 0xffffu);
        wheel[1].rpm = signed16(hi);
        wheel[1].current = signed16(lo >> 16);
        wheel[1].temp = (uint8_t)((lo >> 8) & 0xffu);
    }
}

static int imu_is_valid(void)
{
#if BALANCE_IMU_STUB
    return 0;
#else
    return ((ROBOT_STATUS & 0x3u) == 0x3u) && ROBOT_SAMPLE_AGE < 250000u;
#endif
}

static void sample_imu(void)
{
    /* The exact BMI088 axis/sign and gyro scale belong here after the next
     * calibration capture.  Keeping this explicit prevents a wrong axis from
     * driving a live controller. */
#if BALANCE_IMU_STUB
    balance_in.pitch_deg = 0;
    balance_in.pitch_rate_dps = 0;
    balance_in.valid = 0;
#else
    balance_in.pitch_deg = q16_from_milli(ROBOT_PITCH_D10 * 100);
    balance_in.pitch_rate_dps = q16_from_milli(ROBOT_GYRO_Y); /* replace scale */
    balance_in.valid = imu_is_valid();
#endif
}

static void build_input(void)
{
    uint32_t i;
    sample_feedback();
    sample_imu();
    for (i = 0u; i < DM_COUNT; i++) {
        balance_in.joint_position[i] = dm[i].pos;
        balance_in.joint_velocity[i] = dm[i].vel;
    }
    balance_in.wheel_speed = q16_from_int(wheel[0].rpm + wheel[1].rpm) / 2;
    balance_in.wheel_position = 0;
}

static int all_feedback_fresh(void)
{
    uint32_t i;
    for (i = 0u; i < DM_COUNT; i++) {
        if (dm[i].count == 0u || dm[i].age > FRESH_TICKS || dm[i].id != (uint8_t)(i + 1u)) return 0;
    }
    if (wheel[0].count == 0u || wheel[1].count == 0u) return 0;
    if (wheel[0].age > FRESH_TICKS || wheel[1].age > FRESH_TICKS) return 0;
    return 1;
}

static uint16_t map_q16(q16_t x, q16_t lo, q16_t hi, uint32_t max)
{
    int64_t n;
    x = q16_clamp(x, lo, hi);
    n = (int64_t)(x - lo) * (int64_t)max;
    return (uint16_t)(n / (int64_t)(hi - lo));
}

static void pack_mit(q16_t pos, q16_t vel, q16_t kp, q16_t kd, q16_t torque,
                     uint32_t *hi, uint32_t *lo)
{
    uint16_t p = map_q16(pos, q16_from_milli(-12500), q16_from_milli(12500), 65535u);
    uint16_t v = map_q16(vel, q16_from_int(-30), q16_from_int(30), 4095u);
    uint16_t kpv = map_q16(kp, 0, q16_from_int(500), 4095u);
    uint16_t kdv = map_q16(kd, 0, q16_from_int(5), 4095u);
    uint16_t tv = map_q16(torque, q16_from_int(-10), q16_from_int(10), 4095u);
    uint8_t b0 = (uint8_t)(p >> 8), b1 = (uint8_t)p;
    uint8_t b2 = (uint8_t)(v >> 4);
    uint8_t b3 = (uint8_t)(((v & 0xfu) << 4) | (kpv >> 8));
    uint8_t b4 = (uint8_t)kpv;
    uint8_t b5 = (uint8_t)(kdv >> 4);
    uint8_t b6 = (uint8_t)(((kdv & 0xfu) << 4) | (tv >> 8));
    uint8_t b7 = (uint8_t)tv;
    *hi = ((uint32_t)b0 << 24) | ((uint32_t)b1 << 16) | ((uint32_t)b2 << 8) | b3;
    *lo = ((uint32_t)b4 << 24) | ((uint32_t)b5 << 16) | ((uint32_t)b6 << 8) | b7;
}

static void pack_dm_mode(uint8_t mode, uint32_t *hi, uint32_t *lo)
{
    *hi = 0xffffffffu;
    *lo = 0xffffff00u | mode;
}

static void pack_c620_zero(uint32_t *hi, uint32_t *lo)
{
    *hi = 0u;
    *lo = 0u;
}

static int can0_submit(uint32_t id, uint32_t hi, uint32_t lo)
{
    if (((ROBOT_STATUS >> 4) & 1u) == 0u) return 0;
    CAN0_TX_ID = id;
    CAN0_DATA_HI = hi;
    CAN0_DATA_LO = lo;
    CAN0_CTRL = CAN_KEY | 1u;
    CAN0_CTRL = CAN_KEY | 3u;
    return 1;
}

static int can1_submit(uint32_t hi, uint32_t lo)
{
    if (((ROBOT_STATUS >> 5) & 1u) == 0u) return 0;
    CAN1_DATA_HI = hi;
    CAN1_DATA_LO = lo;
    CAN1_CTRL = CAN_KEY | 1u;
    CAN1_CTRL = CAN_KEY | 3u;
    return 1;
}

/* Replace this function with the validated LQR/VMC implementation.  It is
 * intentionally zero-output until leg geometry, IMU axis signs, wheel radius,
 * mass and gains have been measured. */
static void balance_compute(const balance_input_t *in, balance_output_t *out)
{
    uint32_t i;
    out->wheel_current = 0;
    for (i = 0u; i < DM_COUNT; i++) out->joint_torque[i] = 0;
    if (!in->valid || !stand_ref_valid) return;
    /* Future structure:
     *   pitch_err = 0 - in->pitch_deg;
     *   wheel torque = Ktheta*pitch_err + Kd*in->pitch_rate_dps + ...;
     *   leg force -> VMC Jacobian -> out->joint_torque[];
     *   clamp every command before CAN packing.
     */
}

static void send_active_slot(void)
{
    uint32_t hi, lo;
    uint32_t slot = tx_phase;
    if (control_state == CTRL_SAFE) {
        if (slot == 0u) { pack_c620_zero(&hi, &lo); (void)can1_submit(hi, lo); }
        else { pack_dm_mode(0xfdu, &hi, &lo); (void)can0_submit(slot, hi, lo); }
        return;
    }
    if (control_state == CTRL_ARMING) {
        if (slot == 0u) { pack_c620_zero(&hi, &lo); (void)can1_submit(hi, lo); }
        else { pack_dm_mode(0xfcu, &hi, &lo); (void)can0_submit(slot, hi, lo); }
        return;
    }
    if (control_state == CTRL_DISARMING) {
        if (slot == 0u) { pack_c620_zero(&hi, &lo); (void)can1_submit(hi, lo); }
        else { pack_dm_mode(0xfdu, &hi, &lo); (void)can0_submit(slot, hi, lo); }
        return;
    }
    if (!BALANCE_OUTPUT_ENABLE || !balance_in.valid || !all_feedback_fresh()) {
        control_state = CTRL_DISARMING;
        safety_trips++;
        return;
    }
    if (slot == 0u) {
        /* Current encoding is signed int16 in each C620 slot.  Keep this zero
         * until the wheel current scale and direction are measured. */
        pack_c620_zero(&hi, &lo);
        (void)can1_submit(hi, lo);
    } else {
        pack_mit(balance_in.joint_position[slot - 1u], 0, 0, 0,
                 balance_out.joint_torque[slot - 1u], &hi, &lo);
        (void)can0_submit(slot, hi, lo);
    }
}

void control_tick(void)
{
    build_input();
    if (control_state == CTRL_ARMING && !imu_is_valid()) {
        control_state = CTRL_SAFE;
        safety_trips++;
    }
    if (control_state == CTRL_ARMING && tx_phase == 4u && all_feedback_fresh())
        control_state = CTRL_ACTIVE;
    if (control_state == CTRL_DISARMING && tx_phase == 4u)
        control_state = CTRL_SAFE;
    balance_compute(&balance_in, &balance_out);
    send_active_slot();
    tx_phase = (tx_phase + 1u) % TX_SLOTS;
    control_ticks++;
}

static void capture_stand(void)
{
    uint32_t i;
    if (control_state != CTRL_SAFE || !all_feedback_fresh()) {
        uart_puts("stand capture refused: keep motors SAFE and wait for fresh feedback\r\n");
        return;
    }
    for (i = 0u; i < DM_COUNT; i++) stand_ref[i] = dm[i].pos;
    stand_ref_valid = 1;
    uart_puts("standing reference captured in RAM (not a mechanical limit)\r\n");
}

static void print_status(void)
{
    uint32_t i;
    uart_puts("state="); uart_putu32((uint32_t)control_state);
    uart_puts(" imu="); uart_putu32((uint32_t)balance_in.valid);
    uart_puts(" fresh="); uart_putu32((uint32_t)all_feedback_fresh());
    uart_puts(" ticks="); uart_putu32(control_ticks);
    uart_puts(" skipped_tx="); uart_putu32(skipped_tx);
    uart_puts(" safety="); uart_putu32(safety_trips);
    uart_puts(" pitch_deg="); uart_putq16(balance_in.pitch_deg);
    uart_puts(" DM=");
    for (i = 0u; i < DM_COUNT; i++) { uart_putq16(dm[i].pos); if (i != 3u) uart_putc(','); }
    uart_puts("\r\n");
}

int main(void)
{
    uint32_t last_print;
    uint32_t i;
    board_init();
    CAN0_CTRL = CAN_KEY;
    CAN1_CTRL = CAN_KEY;
    for (i = 0u; i < DM_COUNT; i++) { dm[i].age = 0xffffffffu; stand_ref[i] = 0; }
    wheel[0].age = wheel[1].age = 0xffffffffu;
    stand_ref_valid = 0;
    control_state = CTRL_SAFE;
    timer_start_us(1000u);
    last_print = cycles();
    uart_puts("\r\n--- FPGA wheel-legged balance framework ---\r\n");
    uart_puts("SAFE at boot; IMU stub is active; no motor enable is automatic.\r\n");
    uart_puts("a=arm request, d=disarm, q=capture standing pose, s=status\r\n");
    uart_puts("IMU and LQR/VMC outputs are placeholders; BALANCE_OUTPUT_ENABLE=0.\r\n");
    for (;;) {
        if (uart_rx_count()) {
            int c = uart_getc();
            if (c == 'a' || c == 'A') {
                if (imu_is_valid() && all_feedback_fresh()) control_state = CTRL_ARMING;
                else uart_puts("arm refused: IMU/fresh feedback not valid\r\n");
            } else if (c == 'd' || c == 'D') {
                control_state = CTRL_DISARMING;
                uart_puts("disarm requested\r\n");
            } else if (c == 'q' || c == 'Q') capture_stand();
            else if (c == 's' || c == 'S') print_status();
        }
        if ((uint32_t)(cycles() - last_print) >= (CPU_HZ / 2u)) {
            last_print = cycles();
            print_status();
        }
    }
}
