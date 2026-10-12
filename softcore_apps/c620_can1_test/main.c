/* CAN1-only monitor for two DJI C620/M3508 motor IDs (1 and 2).
 * No CAN transmission occurs unless the operator enters 'z' on USB_DEBUG.
 */
#include "murax.h"

#define CAN_KEY 0xC6200000u

static void print_i16(int32_t value)
{
    int32_t signed_value = (value & 0x8000) ? (value - 0x10000) : value;
    uart_puti32(signed_value);
}

static void print_motor(const char *name, uint32_t count,
                        uint32_t hi, uint32_t lo)
{
    uart_puts(name);
    uart_puts(" frames="); uart_putu32(count);
    uart_puts(" angle="); uart_putu32((hi >> 16) & 0xffffu);
    uart_puts(" rpm="); print_i16(hi & 0xffffu);
    uart_puts(" current_raw="); print_i16((lo >> 16) & 0xffffu);
    uart_puts(" temp="); uart_putu32((lo >> 8) & 0xffu);
    uart_puts("C payload="); uart_puthex32(hi); uart_puthex32(lo);
    uart_puts("\r\n");
}

static void status_print(void)
{
    uint32_t status = ROBOT_STATUS;
    uart_puts("CAN1 status=0x"); uart_puthex32(status);
    uart_puts(" rx_seen="); uart_putu32((status >> 3) & 1u);
    uart_puts(" tx_ready="); uart_putu32((status >> 5) & 1u);
    uart_puts(" ID1_count="); uart_putu32(CAN1_M3508_ID1_COUNT);
    uart_puts(" ID2_count="); uart_putu32(CAN1_M3508_ID2_COUNT);
    uart_puts(" tx_ack="); uart_putu32(CAN1_TX_ACK_COUNT);
    uart_puts(" tx_fail="); uart_putu32(CAN1_TX_FAIL_COUNT);
    uart_puts("\r\n");
    print_motor("M3508-1", CAN1_M3508_ID1_COUNT,
                CAN1_M3508_ID1_HI, CAN1_M3508_ID1_LO);
    print_motor("M3508-2", CAN1_M3508_ID2_COUNT,
                CAN1_M3508_ID2_HI, CAN1_M3508_ID2_LO);
}

static void can1_send_zero_once(void)
{
    uint32_t ack_before = CAN1_TX_ACK_COUNT;
    uint32_t fail_before = CAN1_TX_FAIL_COUNT;

    /* Group command frame 0x200, DLC 8: four signed current commands = 0. */
    CAN1_DATA_LO = 0u;
    CAN1_DATA_HI = 0u;
    CAN1_CTRL = CAN_KEY | 1u; /* keyed enable */
    CAN1_CTRL = CAN_KEY | 3u; /* enqueue exactly one frame */

    /* Allow transmission/retries to finish, then close the TX gate. */
    delay_us(30000u);
    CAN1_CTRL = CAN_KEY;

    uart_puts("TX CAN1 ID=0x200 DLC=8 data=0000000000000000 requested once; ACK +");
    uart_putu32(CAN1_TX_ACK_COUNT - ack_before);
    uart_puts(" FAIL +"); uart_putu32(CAN1_TX_FAIL_COUNT - fail_before);
    uart_puts("\r\n");
}

int main(void)
{
    uint32_t last_print_cycle;
    board_init();
    last_print_cycle = cycles();
    uart_puts("\r\n--- DJI C620 / M3508 CAN1 test ---\r\n");
    uart_puts("CAN1 receives standard IDs 0x201 (motor 1) and 0x202 (motor 2).\r\n");
    uart_puts("CAN1 TX uses standard ID 0x200. Nothing is sent automatically.\r\n");
    uart_puts("Commands: s=status, z=send one all-zero group-current frame.\r\n");
    uart_puts("CAN classic, 1 Mbps, 11-bit IDs. USB_DEBUG UART: 115200 8-N-1.\r\n");
    status_print();

    for (;;) {
        if (uart_rx_count()) {
            int c = uart_getc();
            if (c == 's' || c == 'S') status_print();
            else if (c == 'z' || c == 'Z') can1_send_zero_once();
        }
        if ((uint32_t)(cycles() - last_print_cycle) >= (CPU_HZ / 2u)) {
            last_print_cycle = cycles();
            status_print();
        }
    }
}
