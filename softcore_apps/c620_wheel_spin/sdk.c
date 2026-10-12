/* =============================================================================
 * sdk.c -- murax.h 里那些不能是 static inline 的部分
 *
 * 节拍计数、trace 缓冲、定时器启动、默认中断处理。
 * 你可以随便改这里的默认行为;要覆盖中断处理,在 main.c 里实现 trap_handler()
 * 就行 —— 这里的那个是 weak 的。
 * ========================================================================== */

#include "murax.h"

/* ---------------------------------------------------------------------- */
/* 节拍                                                                   */
/* ---------------------------------------------------------------------- */

volatile uint32_t g_ms          = 0u;
volatile uint32_t g_cycles_at_ms = 0u;

/* 定时器中断里要做的记账。默认 trap_handler 会替你调。
 *
 * 自定义 trap_handler 应在 Timer A pending 时调用它，更新兼容记账并清除 pending。
 * millis()/micros() 直接读 cycle，不依赖此记账；遗漏清 pending 仍会造成中断风暴。 */
void timer_tick(void)
{
    g_cycles_at_ms = cycles();
    g_ms = (uint32_t)(cycles64() / (CPU_HZ / 1000u));
    TIMER_IRQ_CLEAR(TIMER_IRQ_A);
}

/* Monotonic uptime independent of IRQ latency and programmed timer period. */
uint64_t micros64(void) { return cycles64() / CYCLES_PER_US; }
uint64_t millis64(void) { return cycles64() / (CPU_HZ / 1000u); }

void timer_stop(void)
{
    uint32_t s = irq_save();
    TIMER_IRQ_MASK = 0u;
    TIMER_A_CTRL = 0u;
    TIMER_B_CTRL = 0u;
    TIMER_A_LIMIT = 0u;  /* writes clear the counters */
    TIMER_B_LIMIT = 0u;
    TIMER_IRQ_CLEAR(TIMER_IRQ_A | TIMER_IRQ_B);
    __asm__ volatile("csrc mie, %0" :: "r"(1u << 7) : "memory");
    irq_restore(s);
}

void board_quiesce(void)
{
    irq_disable();
    __asm__ volatile("csrw mie, zero" ::: "memory");
    timer_stop();
    UART_STATUS = 0u; /* RTL +0x04 write bits 0/1 disable TX/RX IRQ enables. */
    GPIO_OUTPUT = 0u;
}

/* 起一个周期为 period_us 微秒的硬件节拍。
 *
 * ticksEnable 的语义是从网表里读出来的,不是猜的:
 *     timerA_io_tick = |(ticksEnable & {prescaler_overflow, 1'b1})
 * 所以 bit0(TIMER_TICK_CPU)= 直接用 CPU 时钟,周期就是 (limit+1) 个周期。
 * 选它而不是预分频,是因为它给的周期是精确的 —— 控制环要的就是这个。
 *
 * limit 是 16 位,所以单靠这条路最长 65536 周期 = 1.31 ms。
 * 要更长的周期就得走预分频:prescale 和 limit 两级相乘。
 * 返回值是实际做到的周期(微秒),方便你核对。 */
uint32_t timer_start_us(uint32_t period_us)
{
    uint32_t want, ps, lim, actual, wr_lim, wr_ctrl;
    uint32_t saved_irq = irq_save();
    /* Mask/stop before programming; preserve global IRQ state on return. */
    TIMER_IRQ_MASK &= ~TIMER_IRQ_A;
    TIMER_A_CTRL = 0u;
    if (period_us == 0u) period_us = 1u;

    /* 50 MHz 下每微秒 50 个周期。上限约 80 秒,再大就超出 uint32 的表示了。 */
    if (period_us > 80000000u) period_us = 80000000u;
    want = period_us * CYCLES_PER_US;
    if (want == 0u) want = 1u;

    if (want <= 65536u) {
        /* 一级就够:limit = 周期数 - 1 */
        lim    = want - 1u;
        ps     = 0u;
        actual = lim + 1u;
        wr_lim  = lim;
        wr_ctrl = TIMER_TICK_CPU | TIMER_CTRL_AUTORELOAD;
    } else {
        /* 两级:预分频每 (ps+1) 拍溢出一次,定时器再数 (lim+1) 次。
         * limit 是 16 位,一级最长只有 65536 周期 = 1.31 ms。 */
        uint32_t div = (want + 65535u) / 65536u;
        if (div < 2u)      div = 2u;
        if (div > 65536u)  div = 65536u;

        lim = want / div;
        if (lim == 0u)     lim = 1u;
        if (lim > 65536u)  lim = 65536u;

        ps     = div - 1u;
        actual = (ps + 1u) * lim;

        wr_lim  = lim - 1u;
        wr_ctrl = TIMER_TICK_PRESCALER | TIMER_CTRL_AUTORELOAD;
    }

    /* A/B share a prescaler: never silently change B's running timebase. */
    if ((TIMER_B_CTRL & 3u) == TIMER_TICK_PRESCALER &&
        (TIMER_PRESCALE & 0xFFFFu) != ps) {
        g_timer_ok = 0u;
        irq_restore(saved_irq);
        return 0u;
    }
    TIMER_PRESCALE = ps;
    TIMER_A_LIMIT = wr_lim;
    TIMER_A_CTRL = wr_ctrl;

    TIMER_A_CTRL |= TIMER_CTRL_AUTORELOAD;  /* 计满自动重载;不置的话只会有一次中断 */

    /* ---- 读回校验 ----------------------------------------------------
     * 这是被一次真实的失败逼出来的:第一版把寄存器偏移写错了,写进去的地方
     * 根本不是定时器寄存器。**那样不会报任何错** —— limit 还是 0、tick 使能
     * 还是 0,一个 tick 都不产生,中断一次也不进,而程序"正常"跑完了。
     * 症状是"什么都没发生",这是最难查的一类。
     *
     * 所以配完立刻读回来对一遍,对不上就置错误标志,由调用者喊出来。 */
    /* 对比的是"实际写进去的值",不是重新算一遍的表达式。
     * 第一版这里对比的是 lim-1,而写进去的其实是 lim(两个分支的约定不一样),
     * 于是硬件明明是对的、报的却是 MISMATCH。**一条会误报的门禁和没有门禁一样糟**,
     * 所以这里改成只跟写入值比 —— 这样它就不可能因为算错而误报。 */
    g_timer_lim_wr = wr_lim;
    g_timer_ctrl_wr = wr_ctrl;
    g_timer_lim_rd = TIMER_A_LIMIT & 0xFFFFu;
    g_timer_ctrl_rd = TIMER_A_CTRL & (0x3u | TIMER_CTRL_AUTORELOAD);

    if (g_timer_lim_rd != (wr_lim & 0xFFFFu) ||
        g_timer_ctrl_rd != (wr_ctrl & (0x3u | TIMER_CTRL_AUTORELOAD)) ||
        (TIMER_PRESCALE & 0xFFFFu) != ps) {
        g_timer_ok = 0u;
    } else {
        g_timer_ok = 1u;
    }

    if (g_timer_ok) timer_irq_enable(TIMER_IRQ_A);
    else TIMER_A_CTRL = 0u;
    irq_restore(saved_irq);

    return actual / CYCLES_PER_US;
}

/* ---------------------------------------------------------------------- */
/* 64 位除法:RV32IM 没有,由编译器生成的 __udivdi3 调用会在这里被满足       */
/* ---------------------------------------------------------------------- */
/* 这颗核有 32 位的 mul/div(RV32IM),但 64 位除法不在指令集里。写
 *     uint64_t x = a * 1000000ull / b;
 * 编译器会生成一个对 __udivdi3 的调用,而 -nostdlib 的链接里没有它 ——
 * 报的是 "undefined reference to __udivdi3",和"乘法除法"看起来毫无关系,
 * 但根因就是这个。
 *
 * 与其让每个用 64 位运算的人各自撞一次这堵墙,不如在这里给出实现。
 * 移位相减,64 次迭代 —— 正确但慢,控制环的中断里别用。
 * (q16_div 已经改成纯 32 位了,常见路径不会走到这里。) */

static uint64_t udivmod64(uint64_t n, uint64_t d, uint64_t *rem)
{
    uint64_t q = 0u, r = 0u;
    int i;

    if (d == 0u) { if (rem) *rem = 0u; return 0u; }

    for (i = 63; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1u);
        if (r >= d) { r -= d; q |= ((uint64_t)1u << i); }
    }
    if (rem) *rem = r;
    return q;
}

uint64_t __udivdi3(uint64_t a, uint64_t b) { return udivmod64(a, b, 0); }
uint64_t __umoddi3(uint64_t a, uint64_t b)
{
    uint64_t r; udivmod64(a, b, &r); return r;
}

int64_t __divdi3(int64_t a, int64_t b)
{
    int neg = (a < 0) ^ (b < 0);
    uint64_t ua = (a < 0) ? (uint64_t)(-(int64_t)(a + 1)) + 1u : (uint64_t)a;
    uint64_t ub = (b < 0) ? (uint64_t)(-(int64_t)(b + 1)) + 1u : (uint64_t)b;
    uint64_t q  = udivmod64(ua, ub, 0);
    if (q == (1ull << 63)) return neg ? INT64_MIN : INT64_MAX;
    return neg ? -(int64_t)q : (int64_t)q;
}

int64_t __moddi3(int64_t a, int64_t b)
{
    int neg = (a < 0);
    uint64_t ua = (a < 0) ? (uint64_t)(-(int64_t)(a + 1)) + 1u : (uint64_t)a;
    uint64_t ub = (b < 0) ? (uint64_t)(-(int64_t)(b + 1)) + 1u : (uint64_t)b;
    uint64_t r;
    udivmod64(ua, ub, &r);
    return neg ? -(int64_t)r : (int64_t)r;
}

/* ---------------------------------------------------------------------- */
/* trace                                                                  */
/* ---------------------------------------------------------------------- */

static int32_t s_trace[TRACE_DEPTH][TRACE_CHANNELS];

volatile uint32_t g_trace_w = 0u;
volatile uint32_t g_trace_n = 0u;
volatile uint32_t g_trace_frozen = 0u;

int32_t *trace_slot(uint32_t i) { return s_trace[i]; }

void trace_push(int32_t c0, int32_t c1, int32_t c2, int32_t c3)
{
    if (g_trace_frozen) return;
    uint32_t w = g_trace_w;
    s_trace[w][0] = c0;
    s_trace[w][1] = c1;
    s_trace[w][2] = c2;
    s_trace[w][3] = c3;
    w++;
    if (w >= TRACE_DEPTH) w = 0u;      /* 满了就回绕,保留最新的 */
    g_trace_w = w;
    if (g_trace_n < TRACE_DEPTH) g_trace_n++;
}

/* 以 CSV 倒出。第一行表头,之后每行 4 个整数。
 *
 * 倒出顺序从最旧到最新:如果缓冲已经回绕过,就从写指针处开始读。
 * 这一点必须对 —— 一张时间轴错乱的曲线比没有曲线更误导人。 */
void trace_dump(void)
{
    uint32_t s = irq_save();
    uint32_t was_frozen = g_trace_frozen;
    uint32_t n, start;
    uint32_t i, k;
    g_trace_frozen = 1u;
    n = g_trace_n;
    start = (n < TRACE_DEPTH) ? 0u : g_trace_w;
    irq_restore(s); /* UART transmission runs with control IRQs enabled. */

    uart_puts("i,c0,c1,c2,c3\r\n");
    for (i = 0u; i < n; i++) {
        uint32_t idx = start + i;
        if (idx >= TRACE_DEPTH) idx -= TRACE_DEPTH;
        uart_putu32(i);
        for (k = 0u; k < TRACE_CHANNELS; k++) {
            uart_putc(',');
            uart_puti32(s_trace[idx][k]);
        }
        uart_puts("\r\n");
        /* 一边倒一边能让串口发出去:倒 8 KB 数据会占满发送 FIFO,
         * uart_putc 自己会等,这里不用额外做什么。 */
    }
    uart_puts("end\r\n");
    trace_reset();
    s = irq_save();
    g_trace_frozen = was_frozen;
    irq_restore(s);
}

/* ---------------------------------------------------------------------- */
/* 中断处理                                                               */
/* ---------------------------------------------------------------------- */

/* 异常/中断的计数,方便你判断"到底有没有在中断" */
volatile uint32_t g_timer_ok      = 0u;  /* 定时器寄存器读回校验是否通过 */
volatile uint32_t g_timer_lim_wr  = 0u;  /* 写进去的 limit */
volatile uint32_t g_timer_lim_rd  = 0u;  /* 读回来的 limit */
volatile uint32_t g_timer_ctrl_wr = 0u;  /* 写进去的控制字 */
volatile uint32_t g_timer_ctrl_rd = 0u;  /* 读回来的控制字 */
volatile uint32_t g_irq_count  = 0u;
volatile uint32_t g_exc_count  = 0u;
volatile uint32_t g_exc_cause  = 0u;

/* 定时器中断在用户代码里要做的事。
 * 默认什么都不做 —— 覆盖它,把你的控制环放进来:
 *
 *     void control_tick(void) { ... 读传感器、算 PID、写 PWM ... }
 *
 * 这个函数在中断上下文里被调,每拍一次。要快。 */
__attribute__((weak)) void control_tick(void) { }
__attribute__((weak)) void control_tick_b(void) { }
/* UART source is level-sensitive. Override to drain RX/service TX; the default
 * masks UART interrupts to avoid a permanent interrupt storm. */
__attribute__((weak)) void uart_irq_handler(void) { UART_STATUS = 0u; }

/* 默认的中断/异常处理。
 *
 * weak:你在 main.c 里写一个同名的,你这个就赢,不需要改任何别的地方。
 * 自定义处理器应按 pending 来源清除相应中断；Timer A 可调用 timer_tick()。
 * 64 位 cycle 计时不依赖定时器 ISR。 */
__attribute__((weak)) void trap_handler(uint32_t mcause)
{
    if (mcause & 0x80000000u) {
        uint32_t code = mcause & 0x7FFFFFFFu;
        g_irq_count++;
        if (code == 7u) {            /* 机器定时器中断 */
            uint32_t pending = TIMER_IRQ_PEND;
            if (pending & TIMER_IRQ_A) { timer_tick(); control_tick(); }
            if (pending & TIMER_IRQ_B) { TIMER_IRQ_CLEAR(TIMER_IRQ_B); control_tick_b(); }
        } else if (code == 11u) {
            uart_irq_handler();
        } else {
            board_quiesce();
            for (;;) { }
        }
    } else {
        /* 异常。几乎总是 bug,而且继续跑只会让现场更难查:
         * 打印一次,然后停住,把 mcause 和 mepc 留在串口上。 */
        uint32_t epc;
        __asm__ volatile("csrr %0, mepc" : "=r"(epc));
        board_quiesce();
        g_exc_count++;
        g_exc_cause = mcause;
        uart_puts("\r\n*** EXCEPTION ***\r\n  mcause = 0x");
        uart_puthex32(mcause);
        uart_puts("\r\n  mepc   = 0x");
        uart_puthex32(epc);
        uart_puts("\r\n");
        for (;;) { }
    }
}
