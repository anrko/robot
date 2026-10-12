/* One-shot, all-zero CAN test. Nothing is transmitted until user presses 0/1. */
#include "murax.h"

#define CAN_KEY 0xC6200000u

static void status_print(void)
{
    uint32_t s = ROBOT_STATUS;
    uart_puts("status=0x"); uart_puthex32(s);
    uart_puts(" CAN0_RX="); uart_putu32((s >> 2) & 1u);
    uart_puts(" CAN1_RX="); uart_putu32((s >> 3) & 1u);
    uart_puts(" CAN0_READY="); uart_putu32((s >> 4) & 1u);
    uart_puts(" CAN1_READY="); uart_putu32((s >> 5) & 1u);
    uart_puts("\r\n");
}

static void can0_zero_once(void)
{
    CAN0_DATA_LO = 0u;
    CAN0_DATA_HI = 0u;
    CAN0_CTRL = CAN_KEY | 1u; /* keyed enable */
    CAN0_CTRL = CAN_KEY | 3u; /* one-shot queue request */
    delay_us(20000u);
    CAN0_CTRL = CAN_KEY;      /* disable further submissions */
    uart_puts("CAN0 requested one standard ID 0x200 DLC 8 all-zero frame\r\n");
}

static void can1_zero_once(void)
{
    CAN1_DATA_LO = 0u;
    CAN1_DATA_HI = 0u;
    CAN1_CTRL = CAN_KEY | 1u;
    CAN1_CTRL = CAN_KEY | 3u;
    delay_us(20000u);
    CAN1_CTRL = CAN_KEY;
    uart_puts("CAN1 requested one standard ID 0x201 DLC 8 all-zero frame\r\n");
}

int main(void)
{
    board_init();
    uart_puts("\r\n--- CAN MMIO one-shot test ---\r\n");
    uart_puts("No CAN frame is sent automatically. Disconnect motor power for TX tests.\r\n");
    uart_puts("Send key 0 = one all-zero CAN0 frame; key 1 = one all-zero CAN1 frame; s = status.\r\n");
    uart_puts("USB-CAN must be normal/active mode at 1 Mbps, standard ID, classic CAN.\r\n");
    status_print();
    for (;;) {
        if (uart_rx_count()) {
            int c = uart_getc();
            if (c == 's' || c == 'S') status_print();
            else if (c == '0') can0_zero_once();
            else if (c == '1') can1_zero_once();
            else if (c == 27) break;
        }
    }
    uart_puts("Leaving test; reset FPGA to return to bootloader.\r\n");
    board_quiesce();
    for (;;) { }
}
