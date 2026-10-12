/* Read-only bring-up test for RobotApb in the integrated camera/IMU bitstream. */
#include "murax.h"

static void print_angle(const char *name, int32_t d10)
{
    uart_puts(name);
    if (d10 < 0) { uart_putc('-'); d10 = -d10; }
    uart_putu32((uint32_t)d10 / 10u);
    uart_putc('.');
    uart_putc((char)('0' + (d10 % 10)));
    uart_puts(" deg");
}

static void print_sample(void)
{
    uint32_t status = ROBOT_STATUS;
    uart_puts("status=0x"); uart_puthex32(status);
    uart_puts(" init="); uart_putu32(status & 1u);
    uart_puts(" valid="); uart_putu32((status >> 1) & 1u);
    uart_puts(" samples="); uart_putu32(ROBOT_SAMPLE_CNT);
    uart_puts(" age="); uart_putu32(ROBOT_SAMPLE_AGE);
    uart_puts(" | "); print_angle("roll=", ROBOT_ROLL_D10);
    uart_puts(" "); print_angle("pitch=", ROBOT_PITCH_D10);
    uart_puts(" "); print_angle("yaw=", ROBOT_YAW_D10);
    uart_puts(" | acc=["); uart_puti32(ROBOT_ACCEL_X); uart_putc(',');
    uart_puti32(ROBOT_ACCEL_Y); uart_putc(','); uart_puti32(ROBOT_ACCEL_Z);
    uart_puts("] gyro=["); uart_puti32(ROBOT_GYRO_X); uart_putc(',');
    uart_puti32(ROBOT_GYRO_Y); uart_putc(','); uart_puti32(ROBOT_GYRO_Z);
    uart_puts("]\r\n");
}

int main(void)
{
    board_init();
    uart_puts("\r\n--- RobotApb IMU MMIO test ---\r\n");
    uart_puts("read-only; CAN transmit is not enabled\r\n");
    uart_puts("base=0xF0030000, expected status bit0=1 and sample count increasing\r\n");
    for (;;) {
        print_sample();
        delay_us(200000u);
        if (uart_rx_count()) {
            int c = uart_getc();
            if (c == 27) break;
        }
    }
    uart_puts("stopped; press ESC at bootloader after reset\r\n");
    board_quiesce();
    for (;;) { }
}
