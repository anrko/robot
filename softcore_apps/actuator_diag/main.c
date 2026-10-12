/*
 * Deliberately bounded actuator diagnostic for the ACG138 softcore.
 * Boot is read-only. Motion is always a single, explicit key press.
 */
#include "murax.h"

#define CAN_KEY             0xC6200000u
#define DM_PARAM_CAN_ID     0x7ffu
#define DM_MASTER_ID        0u
#define DM_REG_TIMEOUT      0x09u
#define DM_REG_IMAX         0x3bu
#define DM_TIMEOUT_MIN      400u       /* 20 ms, must be read back on every drive */
#define C620_TEST_RAW       200        /* about 0.244 A at 20 A / 16384 */
#define C620_TEST_RAW_MED   400        /* about 0.488 A at 20 A / 16384 */
#define C620_PULSE_MS       100u
#define TELEMETRY_MS        10000u
#define TELEMETRY_PERIOD_MS 200u
#define DM_TEST_TORQUE_MNM  50         /* 0.05 Nm feed-forward torque */
#define DM_PULSE_MS         150u

static uint8_t param_seen[4];
static uint8_t timeout_safe[4];
static uint32_t imax_milli[4];
static uint32_t timeout_value[4];

static uint32_t bswap32(uint32_t x)
{
    return ((x & 0x000000ffu) << 24) | ((x & 0x0000ff00u) << 8) |
           ((x & 0x00ff0000u) >> 8) | ((x & 0xff000000u) >> 24);
}

static uint32_t ieee754_to_milli(uint32_t bits)
{
    uint32_t exp = (bits >> 23) & 0xffu;
    uint32_t mant = bits & 0x7fffffu;
    uint64_t value;
    int shift;
    if (exp == 0u) {
        if (mant == 0u) return 0u;
        shift = 1 - 127 - 23;
        value = (uint64_t)mant * 1000u;
    } else if (exp == 0xffu) {
        return 0xffffffffu;
    } else {
        shift = (int)exp - 127 - 23;
        value = (uint64_t)(mant | 0x800000u) * 1000u;
    }
    if (shift < 0) {
        unsigned n = (unsigned)(-shift);
        if (n >= 64u) return 0u;
        value = (value + ((uint64_t)1u << (n - 1u))) >> n;
    } else {
        if (shift > 31) return 0xffffffffu;
        value <<= (unsigned)shift;
    }
    return value > 0xffffffffu ? 0xffffffffu : (uint32_t)value;
}

static void print_milli(uint32_t value)
{
    uart_putu32(value / 1000u);
    uart_putc('.');
    uart_putu32((value % 1000u) / 100u);
    uart_putu32((value % 100u) / 10u);
    uart_putu32(value % 10u);
}

static void print_signed_milli(int32_t value)
{
    uint32_t magnitude;
    if (value < 0) { uart_putc('-'); magnitude = (uint32_t)(-(int64_t)value); }
    else magnitude = (uint32_t)value;
    print_milli(magnitude);
}

static int32_t signed16(uint32_t raw)
{
    raw &= 0xffffu;
    return (raw & 0x8000u) ? (int32_t)raw - 65536 : (int32_t)raw;
}

static uint32_t dm_count(uint8_t id)
{
    switch (id) {
    case 1u: return CAN0_DM_ID1_COUNT;
    case 2u: return CAN0_DM_ID2_COUNT;
    case 3u: return CAN0_DM_ID3_COUNT;
    default: return CAN0_DM_ID4_COUNT;
    }
}

static uint32_t dm_hi(uint8_t id)
{
    switch (id) {
    case 1u: return CAN0_DM_ID1_HI;
    case 2u: return CAN0_DM_ID2_HI;
    case 3u: return CAN0_DM_ID3_HI;
    default: return CAN0_DM_ID4_HI;
    }
}

static uint32_t dm_lo(uint8_t id)
{
    switch (id) {
    case 1u: return CAN0_DM_ID1_LO;
    case 2u: return CAN0_DM_ID2_LO;
    case 3u: return CAN0_DM_ID3_LO;
    default: return CAN0_DM_ID4_LO;
    }
}

static int wait_dm_count(uint8_t id, uint32_t before, uint32_t timeout_us)
{
    while (timeout_us != 0u) {
        if (dm_count(id) != before) return 1;
        delay_us(100u);
        timeout_us -= timeout_us >= 100u ? 100u : timeout_us;
    }
    return dm_count(id) != before;
}

static int send_dm(uint8_t id, uint32_t hi, uint32_t lo)
{
    uint32_t fail = CAN0_DM_TX_FAIL_COUNT;
    /* RobotApb only accepts dynamic-ID writes when the 0xC620 key is present. */
    CAN0_TX_ID = CAN_KEY | id;
    CAN0_DATA_HI = hi;
    CAN0_DATA_LO = lo;
    CAN0_CTRL = CAN_KEY | 1u;
    CAN0_CTRL = CAN_KEY | 3u;
    delay_us(3000u);
    CAN0_CTRL = CAN_KEY;
    return CAN0_DM_TX_FAIL_COUNT == fail;
}

static void dm_mode(uint8_t id, uint8_t mode)
{
    (void)send_dm(id, 0xffffffffu, 0xffffff00u | mode);
}

static void print_dm(uint8_t id)
{
    uint32_t hi = dm_hi(id), lo = dm_lo(id);
    uint32_t d0 = hi >> 24;
    if (((hi >> 8) & 0xffffu) == 0x0033u) {
        uart_puts("DM"); uart_putu32(id);
        uart_puts(" latest frame is PARAM reply, not motion feedback; raw=");
        uart_puthex32(hi); uart_puthex32(lo); uart_puts("\r\n");
        return;
    }
    uint32_t p_raw = (hi >> 8) & 0xffffu;
    uint32_t v_raw = ((hi & 0xffu) << 4) | ((lo >> 28) & 0xfu);
    int32_t vel_milli = (int32_t)((v_raw * 60000u) / 4095u) - 30000;
    uart_puts("DM"); uart_putu32(id);
    uart_puts(" count="); uart_putu32(dm_count(id));
    uart_puts(" state=0x"); uart_puthex8((d0 >> 4) & 0xfu);
    uart_puts(" id="); uart_putu32(d0 & 0xfu);
    uart_puts(" pos_raw=0x"); uart_puthex32(p_raw);
    uart_puts(" vel_rad_s="); print_signed_milli(vel_milli);
    uart_puts(" raw="); uart_puthex32(hi); uart_puthex32(lo);
    uart_puts("\r\n");
}

static void print_c620_one(const char *name, uint32_t count, uint32_t hi, uint32_t lo)
{
    uart_puts(name); uart_puts(" frames="); uart_putu32(count);
    uart_puts(" angle_raw="); uart_putu32((hi >> 16) & 0xffffu);
    uart_puts(" rpm="); uart_puti32(signed16(hi));
    uart_puts(" current_raw="); uart_puti32(signed16(lo >> 16));
    uart_puts(" temp="); uart_putu32((lo >> 8) & 0xffu);
    uart_puts("C payload="); uart_puthex32(hi); uart_puthex32(lo);
    uart_puts("\r\n");
}

static void print_imu(void)
{
    int32_t roll = ROBOT_ROLL_D10, pitch = ROBOT_PITCH_D10, yaw = ROBOT_YAW_D10;
    uart_puts("IMU flags=0x"); uart_puthex32(ROBOT_STATUS);
    uart_puts(" samples="); uart_putu32(ROBOT_SAMPLE_CNT);
    uart_puts(" age_us="); uart_putu32(ROBOT_SAMPLE_AGE / 50u);
    uart_puts(" rpy_d10="); uart_puti32(roll); uart_putc(',');
    uart_puti32(pitch); uart_putc(','); uart_puti32(yaw);
    uart_puts(" acc_raw="); uart_puti32((int16_t)ROBOT_ACCEL_X); uart_putc(',');
    uart_puti32((int16_t)ROBOT_ACCEL_Y); uart_putc(','); uart_puti32((int16_t)ROBOT_ACCEL_Z);
    uart_puts(" gyro_raw="); uart_puti32((int16_t)ROBOT_GYRO_X); uart_putc(',');
    uart_puti32((int16_t)ROBOT_GYRO_Y); uart_putc(','); uart_puti32((int16_t)ROBOT_GYRO_Z);
    uart_puts("\r\n");
}

static void print_status(void)
{
    uart_puts("STATUS flags=0x"); uart_puthex32(ROBOT_STATUS);
    uart_puts(" CAN0_rx="); uart_putu32(CAN0_DM_RX_COUNT);
    uart_puts(" CAN0_ack/fail="); uart_putu32(CAN0_DM_TX_ACK_COUNT);
    uart_putc('/'); uart_putu32(CAN0_DM_TX_FAIL_COUNT);
    uart_puts(" CAN1_ack/fail="); uart_putu32(CAN1_TX_ACK_COUNT);
    uart_putc('/'); uart_putu32(CAN1_TX_FAIL_COUNT); uart_puts("\r\n");
    print_imu();
    for (uint8_t id = 1u; id <= 4u; ++id) print_dm(id);
    print_c620_one("C620-ID1(side-A)", CAN1_M3508_ID1_COUNT,
                   CAN1_M3508_ID1_HI, CAN1_M3508_ID1_LO);
    print_c620_one("C620-ID2(side-B)", CAN1_M3508_ID2_COUNT,
                   CAN1_M3508_ID2_HI, CAN1_M3508_ID2_LO);
}

/* Read-only telemetry burst; any received key ends the capture early. */
static void capture_telemetry(void)
{
    uart_puts("TELEMETRY start: read-only, 10 s max, one row every 200 ms; any key stops.\r\n");
    for (uint32_t elapsed = 0u; elapsed < TELEMETRY_MS; elapsed += TELEMETRY_PERIOD_MS) {
        if (uart_getc() >= 0) break;
        uart_puts("T+"); uart_putu32(elapsed); uart_puts("ms ");
        print_imu();
        for (uint8_t id = 1u; id <= 4u; ++id) print_dm(id);
        print_c620_one("C620-ID1", CAN1_M3508_ID1_COUNT, CAN1_M3508_ID1_HI, CAN1_M3508_ID1_LO);
        print_c620_one("C620-ID2", CAN1_M3508_ID2_COUNT, CAN1_M3508_ID2_HI, CAN1_M3508_ID2_LO);
        delay_us(TELEMETRY_PERIOD_MS * 1000u);
    }
    uart_puts("TELEMETRY end.\r\n");
}

/* Request one DM register. Reply D4..D7 are delivered in wire order. */
static int read_dm_parameter(uint8_t id, uint8_t reg, uint32_t *wire_data)
{
    uint32_t rx_before = CAN0_DM_RX_COUNT;
    CAN0_TX_ID = CAN_KEY | DM_PARAM_CAN_ID;
    CAN0_DATA_HI = ((uint32_t)id << 24) | (0x33u << 8) | reg;
    CAN0_DATA_LO = 0u;
    CAN0_CTRL = CAN_KEY | 1u;
    CAN0_CTRL = CAN_KEY | 3u;
    delay_us(20000u);
    CAN0_CTRL = CAN_KEY;
    if (CAN0_DM_RX_COUNT == rx_before ||
        (CAN0_DM_LAST_ID & 0x7ffu) != DM_MASTER_ID ||
        (CAN0_DM_DATA_HI >> 24) != id ||
        ((CAN0_DM_DATA_HI >> 8) & 0xffu) != 0x33u ||
        (CAN0_DM_DATA_HI & 0xffu) != reg) return 0;
    *wire_data = CAN0_DM_DATA_LO;
    return 1;
}

static void query_one(uint8_t id, uint8_t reg)
{
    uint32_t wire = 0u;
    uart_puts("DM"); uart_putu32(id); uart_puts(" read RID=0x"); uart_puthex8(reg);
    if (!read_dm_parameter(id, reg, &wire)) {
        uart_puts(" NO MATCHING REPLY\r\n");
        return;
    }
    uart_puts(" data[D4..D7]=0x"); uart_puthex32(wire);
    if (reg == DM_REG_IMAX) {
        uint32_t milli = ieee754_to_milli(bswap32(wire));
        imax_milli[id - 1u] = milli;
        uart_puts(" Imax="); print_milli(milli); uart_puts(" A");
        param_seen[id - 1u] |= 1u;
    } else if (reg == DM_REG_TIMEOUT) {
        uint32_t value = bswap32(wire);
        timeout_value[id - 1u] = value;
        timeout_safe[id - 1u] = (uint8_t)(value >= DM_TIMEOUT_MIN);
        uart_puts(" TIMEOUT="); uart_putu32(value);
        uart_puts(" ticks x 50 us)");
        param_seen[id - 1u] |= 2u;
    }
    uart_puts("\r\n");
}

static void query_all_parameters(void)
{
    uart_puts("Read-only DM parameters: Imax(0x3B,float), TIMEOUT(0x09,u32).\r\n");
    for (uint8_t i = 0u; i < 4u; ++i) param_seen[i] = 0u;
    for (uint8_t id = 1u; id <= 4u; ++id) {
        query_one(id, DM_REG_IMAX); delay_us(30000u);
        query_one(id, DM_REG_TIMEOUT); delay_us(30000u);
    }
    uart_puts("DM motion gate: ");
    uint8_t safe = 1u;
    for (uint8_t i = 0u; i < 4u; ++i)
        if (param_seen[i] != 3u || imax_milli[i] == 0u || !timeout_safe[i]) safe = 0u;
    if (safe) uart_puts("READY (all 4 IDs replied; Imax>0; TIMEOUT>=400)\r\n");
    else uart_puts("LOCKED; each ID must reply, Imax>0, and TIMEOUT>=400 (20 ms). This program does not change parameters.\r\n");
}

/* A disable frame requests a fresh feedback packet without enabling torque. */
static void refresh_disabled_dm(uint8_t id)
{
    uint32_t before = dm_count(id);
    uint32_t ack_before = CAN0_DM_TX_ACK_COUNT;
    uint32_t fail_before = CAN0_DM_TX_FAIL_COUNT;
    uart_puts("DM"); uart_putu32(id); uart_puts(" poll disabled feedback\r\n");
    dm_mode(id, 0xfdu);
    if (wait_dm_count(id, before, 30000u)) print_dm(id);
    else {
        uart_puts("DM"); uart_putu32(id); uart_puts(" NO FRESH DISABLE FEEDBACK\r\n");
    }
    uart_puts("  CAN0 TX ack/fail delta="); uart_putu32(CAN0_DM_TX_ACK_COUNT - ack_before);
    uart_putc('/'); uart_putu32(CAN0_DM_TX_FAIL_COUNT - fail_before);
    uart_puts(" RX delta="); uart_putu32(CAN0_DM_RX_COUNT - before); uart_puts("\r\n");
}

static void refresh_all_disabled_dm(void)
{
    uart_puts("DM read pass: DISABLE (0xFD) requests only.\r\n");
    for (uint8_t id = 1u; id <= 4u; ++id) {
        refresh_disabled_dm(id);
        delay_us(10000u);
    }
}

/* MIT map: pos +/-12.5 rad, vel +/-30 rad/s, Kp 0..500, Kd 0..5, torque +/-10 Nm. */
static void pack_dm_torque(uint32_t *hi, uint32_t *lo)
{
    uint16_t p = 32767u;
    uint16_t v = 2047u;
    uint16_t kp = 0u;
    uint16_t kd = 0u;
    uint16_t t = (uint16_t)(((uint32_t)(DM_TEST_TORQUE_MNM + 10000) * 4095u) / 20000u);
    uint8_t b0=(uint8_t)(p>>8), b1=(uint8_t)p, b2=(uint8_t)(v>>4);
    uint8_t b3=(uint8_t)(((v&15u)<<4)|(kp>>8)), b4=(uint8_t)kp;
    uint8_t b5=(uint8_t)(kd>>4), b6=(uint8_t)(((kd&15u)<<4)|(t>>8)), b7=(uint8_t)t;
    *hi=((uint32_t)b0<<24)|((uint32_t)b1<<16)|((uint32_t)b2<<8)|b3;
    *lo=((uint32_t)b4<<24)|((uint32_t)b5<<16)|((uint32_t)b6<<8)|b7;
}

static void test_dm_velocity(uint8_t id)
{
    uint32_t before, hi, lo;
    if (param_seen[id - 1u] != 3u || imax_milli[id - 1u] == 0u || !timeout_safe[id - 1u]) {
        uart_puts("BLOCKED: run q first; all four drives need valid Imax and TIMEOUT >= 400 (20 ms).\r\n");
        return;
    }
    uart_puts("DM"); uart_putu32(id);
    uart_puts(" bounded test: +0.05 Nm torque for 150 ms, then disable.\r\n");
    before = dm_count(id);
    dm_mode(id, 0xfcu);
    if (!wait_dm_count(id, before, 30000u) || ((dm_hi(id) >> 28) & 0xfu) != 1u) {
        uart_puts("No enabled-state feedback; immediately disabling.\r\n");
        dm_mode(id, 0xfdu);
        return;
    }
    pack_dm_torque(&hi, &lo);
    for (uint32_t elapsed = 0u; elapsed < DM_PULSE_MS; elapsed += 10u) {
        if (!send_dm(id, hi, lo)) {
            uart_puts("CAN TX fail; disabling now.\r\n");
            break;
        }
        delay_us(7000u);
    }
    before = dm_count(id);
    dm_mode(id, 0xfdu); /* unconditional timed end */
    (void)wait_dm_count(id, before, 30000u);
    print_dm(id);
}

static void can1_send(uint32_t hi, uint32_t lo)
{
    CAN1_DATA_HI = hi; CAN1_DATA_LO = lo;
    CAN1_CTRL = CAN_KEY | 1u;
    CAN1_CTRL = CAN_KEY | 3u;
    delay_us(3000u);
    CAN1_CTRL = CAN_KEY;
}

static void test_c620(uint8_t id, int16_t current)
{
    uint32_t before_count, before_hi, before_lo, hi = 0u, sample_count = 0u;
    uint32_t ack_before = CAN1_TX_ACK_COUNT, fail_before = CAN1_TX_FAIL_COUNT;
    if (id == 1u) {
        before_count = CAN1_M3508_ID1_COUNT; before_hi = CAN1_M3508_ID1_HI; before_lo = CAN1_M3508_ID1_LO;
        hi = (uint32_t)(uint16_t)current << 16;
    } else {
        before_count = CAN1_M3508_ID2_COUNT; before_hi = CAN1_M3508_ID2_HI; before_lo = CAN1_M3508_ID2_LO;
        hi = (uint16_t)current;
    }
    uart_puts("C620 ID"); uart_putu32(id); uart_puts("(side-");
    uart_puts(id == 1u ? "A" : "B"); uart_puts(") pulse current_raw="); uart_puti32(current);
    uart_puts(" (~"); print_milli((uint32_t)((current < 0 ? -current : current) * 20000 / 16384));
    uart_puts(" A) for 100 ms; then zero current. Wheel must be raised.\r\n");
    for (uint32_t elapsed = 0u; elapsed < C620_PULSE_MS; elapsed += 7u) {
        can1_send(hi, 0u);
        if (elapsed == 28u || elapsed == 56u || elapsed == 84u) {
            if (id == 1u) {
                uint32_t count = CAN1_M3508_ID1_COUNT;
                if (count != sample_count) {
                    print_c620_one("C620-ID1 DURING", count, CAN1_M3508_ID1_HI, CAN1_M3508_ID1_LO);
                    sample_count = count;
                }
            } else {
                uint32_t count = CAN1_M3508_ID2_COUNT;
                if (count != sample_count) {
                    print_c620_one("C620-ID2 DURING", count, CAN1_M3508_ID2_HI, CAN1_M3508_ID2_LO);
                    sample_count = count;
                }
            }
        }
        delay_us(4000u);
    }
    can1_send(0u, 0u); can1_send(0u, 0u); can1_send(0u, 0u);
    delay_us(50000u);
    if (id == 1u)
        print_c620_one("C620-ID1 before", before_count, before_hi, before_lo);
    else
        print_c620_one("C620-ID2 before", before_count, before_hi, before_lo);
    delay_us(10000u);
    if (id == 1u)
        print_c620_one("C620-ID1 after ", CAN1_M3508_ID1_COUNT, CAN1_M3508_ID1_HI, CAN1_M3508_ID1_LO);
    else
        print_c620_one("C620-ID2 after ", CAN1_M3508_ID2_COUNT, CAN1_M3508_ID2_HI, CAN1_M3508_ID2_LO);
    uart_puts("C620 TX ack/fail delta="); uart_putu32(CAN1_TX_ACK_COUNT - ack_before);
    uart_putc('/'); uart_putu32(CAN1_TX_FAIL_COUNT - fail_before); uart_puts("\r\n");
}

static void stop_all(void)
{
    uart_puts("STOP: DM disable IDs 1..4; C620 group-current zero.\r\n");
    for (uint8_t id = 1u; id <= 4u; ++id) { dm_mode(id, 0xfdu); delay_us(3000u); }
    can1_send(0u, 0u); can1_send(0u, 0u); can1_send(0u, 0u);
}

int main(void)
{
    board_init();
    CAN0_CTRL = CAN_KEY;
    CAN1_CTRL = CAN_KEY;
    uart_puts("\r\n--- bounded actuator diagnostic ---\r\n");
    uart_puts("BOOT SAFE: no enable and no nonzero CAN output. USB_DEBUG 115200 8-N-1.\r\n");
    uart_puts("q=read Imax/TIMEOUT; r=request fresh DM disabled feedback; s=status; d=disable all + wheel zero.\r\n");
    uart_puts("m=one IMU sample; t=read-only telemetry up to 10 s; any key stops.\r\n");
    uart_puts("DM keys 1..4: only after q passes; +0.05 N.m for 150 ms then DISABLE.\r\n");
    uart_puts("C620 low: u/j=ID1 +/-; i/k=ID2 +/-; 0.244 A for 100 ms then zero.\r\n");
    uart_puts("C620 medium: U/J=ID1 +/-; I/K=ID2 +/-; 0.488 A for 100 ms then zero.\r\n");
    uart_puts("Use raised wheels, secured legs and reachable motor-power cutoff.\r\n");
    for (;;) {
        int c = uart_getc();
        if (c < 0) continue;
        if (c == 'q' || c == 'Q') query_all_parameters();
        else if (c == 'r' || c == 'R') refresh_all_disabled_dm();
        else if (c == 's' || c == 'S') print_status();
        else if (c == 'm' || c == 'M') print_imu();
        else if (c == 't' || c == 'T') capture_telemetry();
        else if (c == 'd' || c == 'D' || c == 27) stop_all();
        else if (c >= '1' && c <= '4') test_dm_velocity((uint8_t)(c - '0'));
        else if (c == 'u') test_c620(1u, C620_TEST_RAW);
        else if (c == 'j') test_c620(1u, -C620_TEST_RAW);
        else if (c == 'i') test_c620(2u, C620_TEST_RAW);
        else if (c == 'k') test_c620(2u, -C620_TEST_RAW);
        else if (c == 'U') test_c620(1u, C620_TEST_RAW_MED);
        else if (c == 'J') test_c620(1u, -C620_TEST_RAW_MED);
        else if (c == 'I') test_c620(2u, C620_TEST_RAW_MED);
        else if (c == 'K') test_c620(2u, -C620_TEST_RAW_MED);
        else if (c == '\r' || c == '\n' || c == ' ') { }
        else uart_puts("Unknown key; q/r/s/m/t/d, DM 1..4, C620 u/j/i/k or U/J/I/K.\r\n");
    }
}
