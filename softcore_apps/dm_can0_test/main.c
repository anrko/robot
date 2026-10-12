/* Read-only DM4310 CAN0 monitor for IDs 1..4.
 * It periodically reads register 0x08 (ESC_ID); no enable/motion frames.
 */
#include "murax.h"

#define CAN_KEY 0xC6200000u
#define DM_PARAM_REQUEST_ID 0x7ffu
#define DM_MASTER_ID        0u
#define DM_ID_REG_ESC_ID    0x08u

static const uint8_t dm_ids[] = {1u, 2u, 3u, 4u};

static void print_id_data(uint32_t id, uint32_t low, uint32_t high)
{
    uart_puts(" reply_id=0x"); uart_puthex32(id);
    uart_puts(" data="); uart_puthex32(high); uart_puthex32(low);
    uart_puts(" count="); uart_putu32(CAN0_DM_RX_COUNT);
    uart_puts("\r\n");
}

static void request_esc_id(uint8_t motor_id)
{
    uint32_t ack_before = CAN0_DM_TX_ACK_COUNT;
    uint32_t fail_before = CAN0_DM_TX_FAIL_COUNT;
    uint32_t rx_before = CAN0_DM_RX_COUNT;
    uint32_t rx_after;
    uint32_t reply_hi;
    uint32_t reply_lo;

    /* DM read-param request: id-low, id-high, 0x33, register, 4 zero bytes. */
    /* CAN TX serializes data[63:56] first: [ID, 0, 0x33, RID, 0,0,0,0]. */
    CAN0_DATA_HI = ((uint32_t)motor_id << 24) |
                   (0x33u << 8) | DM_ID_REG_ESC_ID;
    CAN0_DATA_LO = 0u;
    CAN0_CTRL = CAN_KEY | 1u; /* keyed CAN0 TX enable; no frame by itself */
    CAN0_CTRL = CAN_KEY | 3u; /* queue exactly one standard 0x7FF frame */
    delay_us(15000u);          /* allow TX retries and DM reply to complete */
    CAN0_CTRL = CAN_KEY;       /* close the TX gate between queries */
    rx_after = CAN0_DM_RX_COUNT;
    reply_hi = CAN0_DM_DATA_HI;
    reply_lo = CAN0_DM_DATA_LO;

    uart_puts("DM read ESC_ID motor="); uart_putu32(motor_id);
    uart_puts(" req=7FF: "); uart_puthex32(CAN0_DATA_HI); uart_puthex32(CAN0_DATA_LO);
    uart_puts(" ACK+"); uart_putu32(CAN0_DM_TX_ACK_COUNT - ack_before);
    uart_puts(" FAIL+"); uart_putu32(CAN0_DM_TX_FAIL_COUNT - fail_before);
    uart_puts("; ");
    print_id_data(CAN0_DM_LAST_ID, reply_lo, reply_hi);
    if (rx_after != rx_before && (CAN0_DM_LAST_ID & 0x7ffu) == DM_MASTER_ID &&
        ((reply_hi >> 8) & 0xffu) == 0x33u &&
        (reply_hi & 0xffu) == DM_ID_REG_ESC_ID &&
        ((reply_lo >> 24) & 0xffu) == motor_id) {
        uart_puts("  PASS: DM ID "); uart_putu32(motor_id);
        uart_puts(" answered ESC_ID="); uart_putu32((reply_lo >> 24) & 0xffu);
        uart_puts("\r\n");
    } else {
        uart_puts("  NO MATCHING REPLY for requested motor ID ");
        uart_putu32(motor_id); uart_puts("\r\n");
    }
}

static void status_print(void)
{
    uint32_t status = ROBOT_STATUS;
    uart_puts("CAN0(DM) status=0x"); uart_puthex32(status);
    uart_puts(" rx_seen="); uart_putu32((status >> 2) & 1u);
    uart_puts(" tx_ready="); uart_putu32((status >> 4) & 1u);
    uart_puts(" replies="); uart_putu32(CAN0_DM_RX_COUNT);
    uart_puts(" last_id=0x"); uart_puthex32(CAN0_DM_LAST_ID);
    uart_puts(" data="); uart_puthex32(CAN0_DM_DATA_HI); uart_puthex32(CAN0_DM_DATA_LO);
    uart_puts(" tx_ack="); uart_putu32(CAN0_DM_TX_ACK_COUNT);
    uart_puts(" tx_fail="); uart_putu32(CAN0_DM_TX_FAIL_COUNT);
    uart_puts("\r\n");
}

int main(void)
{
    uint32_t last_status;
    uint32_t previous_rx_count;
    uint8_t index = 0u;

    board_init();
    CAN0_CTRL = CAN_KEY; /* start with TX disabled */
    CAN1_CTRL = CAN_KEY; /* leave the C620 bus untouched */
    uart_puts("\r\n--- DM4310 CAN0 read-only detection ---\r\n");
    uart_puts("Queries standard ID 0x7FF, register 0x08, motor IDs 1..4; Master ID expected 0.\r\n");
    uart_puts("No motor enable or motion command is ever sent. CAN1/C620 is not used.\r\n");
    uart_puts("Keep motors disabled and mechanically secured. Commands: s=status.\r\n");

    last_status = cycles();
    previous_rx_count = CAN0_DM_RX_COUNT;
    for (;;) {
        request_esc_id(dm_ids[index]);
        index = (uint8_t)((index + 1u) & 3u);
        delay_us(85000u); /* about 100 ms between queries; one addressed reply at a time */

        if (uart_rx_count()) {
            int c = uart_getc();
            if (c == 's' || c == 'S') status_print();
        }
        if ((uint32_t)(cycles() - last_status) >= CPU_HZ) {
            last_status = cycles();
            if (CAN0_DM_RX_COUNT == previous_rx_count)
                uart_puts("WARNING: no new DM reply in the last second; check Master ID, bitrate, CAN wiring and termination.\r\n");
            previous_rx_count = CAN0_DM_RX_COUNT;
            status_print();
        }
    }
}
