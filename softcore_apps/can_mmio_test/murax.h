/* =============================================================================
 * murax.h -- ACG138 (VexRiscv / Murax, RV32IM @ 50 MHz) 板级支持头文件
 *
 * 一份头文件,把「写机器人程序」真正会用到的东西都放在一起:
 *
 *   UART        打印 / 非阻塞收字节
 *   GPIO        LED 与引脚(注意:写之前必须先设输出使能)
 *   定时器      硬件周期节拍,可产生中断 —— 控制环的心脏
 *   中断        C 里写 trap_handler(),中断自动进来
 *   计时        rdcycle:测你的控制环到底跑了多久(纳秒级)
 *   trace       往 RAM 环形缓冲里记数据,事后导成 CSV 画图 —— 调 PID 全靠它
 *   Q16 定点    这颗核没有 FPU,浮点会链接失败;定点是必须的
 *   PID         控制环骨架
 *   互补滤波    陀螺仪 + 加速度计融合的骨架
 *
 * 一切都在 50 MHz 下算好,CPU_HZ 改一处即可。
 * ========================================================================== */

#ifndef MURAX_H
#define MURAX_H

#include <stdint.h>
#include <limits.h>

#define CPU_HZ          50000000u
#define CYCLES_PER_US   (CPU_HZ / 1000000u)      /* 50 */

/* ---------------------------------------------------------------------- */
/* 寄存器                                                                  */
/* ---------------------------------------------------------------------- */

#define GPIO_BASE    0xF0000000u
#define GPIO_INPUT   (*(volatile uint32_t *)(GPIO_BASE + 0x00u))
#define GPIO_OUTPUT  (*(volatile uint32_t *)(GPIO_BASE + 0x04u))
#define GPIO_OE      (*(volatile uint32_t *)(GPIO_BASE + 0x08u))

#define UART_BASE    0xF0010000u
#define UART_DATA    (*(volatile uint32_t *)(UART_BASE + 0x00u))
#define UART_STATUS  (*(volatile uint32_t *)(UART_BASE + 0x04u))
#define UART_CLKDIV  (*(volatile uint32_t *)(UART_BASE + 0x08u))
#define UART_FRAME   (*(volatile uint32_t *)(UART_BASE + 0x0Cu))

#define TIMER_BASE        0xF0020000u

/* !! 这张表是从生成的网表里逐条读出来的,不是猜的 !!
 *
 * 一开始我按"看着合理"的偏移写(0x04/0x08/0x0C/0x1C/0x20),结果写进去的地方根本
 * 不是定时器寄存器 —— limit 还是 0、tick 使能还是 0,于是一个 tick 都不产生,
 * 中断一次都没进过。**这类错误的症状是"程序正常跑但什么都没发生"**,
 * 因为它不报错。
 *
 * 真正的布局 —— 读和写用的是同一套偏移(网表里两处 case(io_apb_PADDR) 完全一致):
 *
 *     0x00  prescaler limit     写它同时把预分频计数器清零
 *     0x10  中断 pendings       写 1 清除
 *     0x14  中断 masks          写 1 使能
 *     0x40  timer A 控制        [1:0] tick 选择, [16] 计满自动清零
 *     0x44  timer A limit
 *     0x48  timer A 计数值      只读
 *     0x50  timer B 控制
 *     0x54  timer B limit
 *     0x58  timer B 计数值      只读
 */
#define TIMER_PRESCALE    (*(volatile uint32_t *)(TIMER_BASE + 0x00u))
#define TIMER_IRQ_PEND    (*(volatile uint32_t *)(TIMER_BASE + 0x10u))
#define TIMER_IRQ_MASK    (*(volatile uint32_t *)(TIMER_BASE + 0x14u))
#define TIMER_A_CTRL      (*(volatile uint32_t *)(TIMER_BASE + 0x40u))
#define TIMER_A_LIMIT     (*(volatile uint32_t *)(TIMER_BASE + 0x44u))
#define TIMER_A_VALUE     (*(volatile uint32_t *)(TIMER_BASE + 0x48u))
#define TIMER_B_CTRL      (*(volatile uint32_t *)(TIMER_BASE + 0x50u))
#define TIMER_B_LIMIT     (*(volatile uint32_t *)(TIMER_BASE + 0x54u))
#define TIMER_B_VALUE     (*(volatile uint32_t *)(TIMER_BASE + 0x58u))

/* timer A/B 控制位。
 *
 * 名字值得较真:bit16 是"计满就自动重载",不是"立刻清零"。网表里是
 *     timerA_io_clear = (|(clearsEnable & timerA_io_full)) || busClearing
 * 也就是计满时自己清零重数。
 *
 * **这一位必须置上**:不置的话计数器到 limit 就被 inhibitFull 停住,
 * 只产生一次 io_full,然后永远不再有中断。只进了一次中断就卡住、
 * 然后奇怪"为什么没有第二次",就是漏了它。
 * (真正"立刻清零"是写偏移 0x00。) */
#define TIMER_TICK_PRESCALER  0x2u      /* bit1: prescaler overflow */
#define TIMER_TICK_CPU        0x1u      /* bit0: CPU clock */
#define TIMER_CTRL_AUTORELOAD 0x10000u  /* 计满自动重载(必置,否则只有一次中断)*/

#define TIMER_IRQ_A           0x1u
#define TIMER_IRQ_B           0x2u

/* LED: led[6:0] = GPIO 输出低 7 位(1 = 亮)。bit7 是心跳灯,固件动不了。 */
#define LED_MASK     0x7Fu

/* ---------------------------------------------------------------------- */
/* 极小工具                                                               */
/* ---------------------------------------------------------------------- */

#define REG32(a)     (*(volatile uint32_t *)(uintptr_t)(a))

static inline uint32_t irq_save(void)
{
    uint32_t s;
    __asm__ volatile("csrrci %0, mstatus, 8" : "=r"(s) :: "memory");
    return s;
}

static inline void irq_restore(uint32_t s)
{
    if (s & 8u) __asm__ volatile("csrsi mstatus, 8" ::: "memory");
    else __asm__ volatile("csrci mstatus, 8" ::: "memory");
}

static inline void irq_disable(void)
{
    __asm__ volatile("csrci mstatus, 8" ::: "memory");
}

/* 打开 M 模式中断门(mstatus.MIE)。
 *
 * !! 这一步单独做是不够的 !!
 *
 * RISC-V 的规则是:**mstatus.MIE 和 mie 里对应的那一位都必须为 1**,中断才会
 * 被响应。这里的 irq_enable() 只管前者。
 *
 * 第一版就是漏了后者 —— 定时器配得分毫不差,一个中断也进不来,因为
 * mie.MTIE 一直是 0。症状是"什么都配好了,但什么都没发生"。
 * 中断源的使能位:
 *     mie bit 7  MTIE  机器定时器中断  <- 定时器走这条
 *     mie bit 11 MEIE  机器外部中断    <- UART / GPIO 走这条
 * 下面对应的两个函数负责它们。 */
static inline void irq_enable(void)
{
    __asm__ volatile("csrsi mstatus, 8" ::: "memory");
}

static inline void irq_enable_mtie(void)     /* 让定时器中断能进来 */
{
    __asm__ volatile("csrs mie, %0" :: "r"(1u << 7) : "memory");
}

static inline void irq_enable_meie(void)     /* 让 UART / GPIO 中断能进来 */
{
    __asm__ volatile("csrs mie, %0" :: "r"(1u << 11) : "memory");
}

static inline uint32_t irq_mie(void)
{
    uint32_t v; __asm__ volatile("csrr %0, mie" : "=r"(v)); return v;
}
static inline uint32_t irq_mstatus(void)
{
    uint32_t v; __asm__ volatile("csrr %0, mstatus" : "=r"(v)); return v;
}

/* ---------------------------------------------------------------------- */
/* 计时: rdcycle                                                          */
/* ---------------------------------------------------------------------- */
/* 这颗核原来把 mcycle 关掉了(mcycleAccess = NONE),所以 rdcycle 根本不存在。
 * 现在打开了 —— 控制环不能测量自己的周期,就是不能调试的控制环。 */

static inline uint32_t cycles(void)
{
    uint32_t c;
    __asm__ volatile("csrr %0, mcycle" : "=r"(c));
    return c;
}

static inline uint32_t instret(void)
{
    uint32_t c;
    __asm__ volatile("csrr %0, minstret" : "=r"(c));
    return c;
}

/* Hardware mcycle is 64 bit; cycles() returns its low 32 bits. */
static inline uint64_t cycles64(void)
{
    uint32_t hi, lo, again;
    do {
        __asm__ volatile("csrr %0, mcycleh" : "=r"(hi));
        __asm__ volatile("csrr %0, mcycle" : "=r"(lo));
        __asm__ volatile("csrr %0, mcycleh" : "=r"(again));
    } while (hi != again);
    return ((uint64_t)hi << 32) | lo;
}
#define CYCLES_TO_US(c)  ((c) / CYCLES_PER_US)
#define CYCLES_TO_MS(c)  ((c) / (CPU_HZ / 1000u))

/* ---------------------------------------------------------------------- */
/* 定时器 / 系统节拍                                                       */
/* ---------------------------------------------------------------------- */
/* 净表里的语义(照实写的,不是猜的):
 *
 *     timerA_io_tick = |(ticksEnable & {prescaler_overflow, 1'b1})
 *     limitHit       = (counter == io_limit)
 *     io_full        = limitHit && io_tick
 *
 * 也就是:选了 TIMER_TICK_CPU 之后,每 (limit+1) 个 CPU 周期来一次 io_full。
 * 50 MHz 下要 1 kHz,limit = 50000-1 = 49999。
 *
 * prescaler 那条路是:预分频每 (prescale+1) 拍溢出一次,再乘上 timer 的
 * (limit+1),适合要很长的周期、又不想让 16 位 limit 溢出的场合。
 */

extern volatile uint32_t g_ms;            /* 由节拍中断维护的毫秒计数 */
extern volatile uint32_t g_cycles_at_ms;  /* 上一次节拍时的 rdcycle */

/* 中断/异常计数,以及最后一次异常的 mcause —— 判断"中断到底有没有在跑"用 */
extern volatile uint32_t g_timer_ok;      /* 定时器寄存器读回校验是否通过 */
extern volatile uint32_t g_timer_lim_wr;  /* 写进去 / 读回来的 limit */
extern volatile uint32_t g_timer_lim_rd;
extern volatile uint32_t g_timer_ctrl_wr; /* 写进去 / 读回来的控制字 */
extern volatile uint32_t g_timer_ctrl_rd;
extern volatile uint32_t g_irq_count;
extern volatile uint32_t g_exc_count;
extern volatile uint32_t g_exc_cause;

/* Timer A pending 时更新兼容记账并清 pending。自定义 ISR 仍须正确清中断。
 * millis()/micros() 基于 cycle 计数，不依赖 timer_tick()。 */
void timer_tick(void);

/* 起一个周期为 period_us 微秒的硬件节拍,并使能它的中断。
 * 返回实际周期（整数微秒）；配置失败返回 0。 */
uint32_t timer_start_us(uint32_t period_us);
void timer_stop(void);
void board_quiesce(void);
uint64_t micros64(void);
uint64_t millis64(void);

/* 只使能中断,不设定时器(给已经配好的定时器用) */
static inline void timer_irq_enable(uint32_t which)
{
    TIMER_IRQ_PEND = which;          /* 写 1 清掉可能残留的 pending */
    TIMER_IRQ_PEND = which;          /* 再写一次:上一次可能正好撞上 io_full 脉冲 */
    TIMER_IRQ_MASK |= which;         /* preserve other enabled timer sources */
    irq_enable_mtie();               /* CPU 侧的 mie.MTIE —— 少了它前面全是白配 */
}

static inline void timer_irq_disable(void)
{
    TIMER_IRQ_MASK = 0u;
}

#define TIMER_IRQ_CLEAR(w)  do { TIMER_IRQ_PEND = (w); TIMER_IRQ_PEND = (w); } while (0)

static inline uint32_t micros(void)
{
    return (uint32_t)micros64();
}

static inline uint32_t millis(void) { return (uint32_t)millis64(); }

/* 忙等,用 rdcycle 计时,不受编译器优化影响 */
static inline void delay_us(uint32_t us)
{
    while (us) {
        uint32_t chunk = us > 80000000u ? 80000000u : us;
        uint32_t t0 = cycles(), want = chunk * CYCLES_PER_US;
        while ((uint32_t)(cycles() - t0) < want) { }
        us -= chunk;
    }
}

/* ---------------------------------------------------------------------- */
/* UART                                                                   */
/* ---------------------------------------------------------------------- */

static inline int uart_tx_free(void)  { return (int)((UART_STATUS >> 16) & 0xFFu); }
static inline int uart_rx_count(void) { return (int)((UART_STATUS >> 24) & 0xFFu); }

static inline void uart_putc(char c)
{
    while (uart_tx_free() == 0) { }
    UART_DATA = (uint32_t)(uint8_t)c;
}

static inline void uart_puts(const char *s)
{
    while (*s) uart_putc(*s++);
}

static inline void uart_puthex8(uint32_t v)
{
    int sh;
    for (sh = 4; sh >= 0; sh -= 4) {
        uint32_t d = (v >> (unsigned)sh) & 0xFu;
        uart_putc((char)(d < 10u ? '0' + d : 'a' + d - 10u));
    }
}

static inline void uart_puthex32(uint32_t v)
{
    int sh;
    for (sh = 28; sh >= 0; sh -= 4) {
        uint32_t d = (v >> (unsigned)sh) & 0xFu;
        uart_putc((char)(d < 10u ? '0' + d : 'a' + d - 10u));
    }
}

static inline void uart_putu32(uint32_t v)
{
    char buf[10];
    int n = 0;
    if (v == 0u) { uart_putc('0'); return; }
    while (v && n < 10) { buf[n++] = (char)('0' + (v % 10u)); v /= 10u; }
    while (n--) uart_putc(buf[n]);
}

static inline void uart_puti32(int32_t v)
{
    if (v < 0) { uart_putc('-'); uart_putu32((uint32_t)(-(int64_t)v)); }
    else       { uart_putu32((uint32_t)v); }
}

/* 收一个字节;没有就返回 -1(不阻塞)。 */
static inline int uart_getc(void)
{
    if (uart_rx_count() == 0) return -1;
    return (int)(UART_DATA & 0xFFu);
}

static inline void uart_flush(void)
{
    while (uart_tx_free() != 16) { }
}

/* ---------------------------------------------------------------------- */
/* trace:把控制环的变量记进 RAM,事后导成 CSV                              */
/* ---------------------------------------------------------------------- */
/* 调 PID 靠肉眼看串口是没用的 —— 数据太密。正确做法是:按节拍把几个通道记
 * 进 RAM,跑几百个周期,停,然后一次性倒出来导入 Excel/Python 画图。
 *
 * 4 通道 × 512 点 × 4 字节 = 8 KB。要更多就改这两个宏(注意别吃光 RAM:
 * 你的程序最大 40 KB)。 */

#define TRACE_CHANNELS  4
#define TRACE_DEPTH     512

extern volatile uint32_t g_trace_w;      /* 写指针 */
extern volatile uint32_t g_trace_n;      /* 总共记了多少(含回绕) */
extern volatile uint32_t g_trace_frozen;

int32_t *trace_slot(uint32_t i);          /* 第 i 圈的第 0 通道地址 */

static inline void trace_reset(void)
{
    uint32_t s = irq_save();
    g_trace_w = 0u;
    g_trace_n = 0u;
    irq_restore(s);
}

/* 记一行。满了自动回绕(保留最新的)。 */
void trace_push(int32_t c0, int32_t c1, int32_t c2, int32_t c3);

/* 以 CSV 倒出(第一行是表头),倒完自动 trace_reset。
 * 直接粘进 Excel,或者重定向到文件给 Python。 */
void trace_dump(void);

static inline int trace_full(void) { return g_trace_n >= TRACE_DEPTH; }

/* ---------------------------------------------------------------------- */
/* Q16.16 定点数                                                          */
/* ---------------------------------------------------------------------- */
/* 这颗核没有 FPU。写 1.5f 要么链接失败,要么更糟:悄悄用软件浮点跑得比控制
 * 周期还慢。定点是这里的标准做法。
 *
 * Q16.16:高 16 位整数部分,低 16 位小数。范围 ±32768,精度 1/65536。
 * 陀螺仪、编码器、PWM 占空比都在这个范围内,够用。 */

typedef int32_t q16_t;

#define Q16_ONE      (1 << 16)
#define Q16_SHIFT    16

static inline q16_t q16_sat64(int64_t x)
{
    if (x > INT32_MAX) return INT32_MAX;
    if (x < INT32_MIN) return INT32_MIN;
    return (q16_t)x;
}
static inline q16_t q16_from_int(int32_t i) { return q16_sat64((int64_t)i * Q16_ONE); }
/* Arithmetic rounds toward zero; do not rely on signed shifts. */
static inline int32_t q16_to_int(q16_t a) { return a / Q16_ONE; }
static inline q16_t q16_from_milli(int32_t m) { return q16_sat64((int64_t)m * Q16_ONE / 1000); }
static inline q16_t q16_frac(int32_t num, int32_t den)
{
    if (den == 0) return 0;
    return q16_sat64(((int64_t)num * Q16_ONE) / den);
}

static inline q16_t q16_mul(q16_t a, q16_t b)
{
    return q16_sat64(((int64_t)a * b) / Q16_ONE);
}

/* Q16 除法,纯 32 位实现。
 *
 * 写成 (a << 16) / b 是最直观的,但那是 64 位除法 —— 而这颗核只有 32 位
 * 的 `div`(RV32IM),64 位除法会变成对 __udivdi3 的调用,链接期直接报
 * undefined reference。控制环里也不能接受一个几百周期的手写除法。
 *
 * 所以:先算整数商和余数(32 位 div/rem 指令,一条就完),再把余数逐位
 * 移出 16 位小数。全程 32 位。 */
static inline q16_t q16_div(q16_t a, q16_t b)
{
    uint32_t ua, ub, qi, rem, frac = 0u, r;
    int neg, i;

    if (b == 0) return (a >= 0) ? (q16_t)0x7FFFFFFF : (q16_t)0x80000000;

    neg = (a < 0) ^ (b < 0);
    ua  = (a < 0) ? (uint32_t)(-(int64_t)a) : (uint32_t)a;
    ub  = (b < 0) ? (uint32_t)(-(int64_t)b) : (uint32_t)b;

    qi  = ua / ub;
    rem = ua % ub;

    if (qi >= 0x8000u)                      /* 结果超出 Q16 表示范围 */
        return neg ? (q16_t)0x80000000 : (q16_t)0x7FFFFFFF;

    for (i = 0; i < 16; i++) {
        frac <<= 1;
        rem  <<= 1;                         /* rem < ub <= 2^31,不会丢位 */
        if (rem >= ub) { rem -= ub; frac |= 1u; }
    }

    r = (qi << Q16_SHIFT) | (frac & 0xFFFFu);
    if (r == 0x80000000u) return (q16_t)0x80000000;
    return neg ? (q16_t)(-(int64_t)r) : (q16_t)r;
}

/* 饱和加减:控制环里宁可顶住,也不要回绕成一个巨大的反向值。
 * 整型回绕在控制器里等于瞬间满舵反向 —— 那会直接把机器人摔了。 */
static inline q16_t q16_add_sat(q16_t a, q16_t b)
{
    int64_t r = (int64_t)a + b;
    if (r >  0x7FFFFFFF) return  0x7FFFFFFF;
    if (r < -(int64_t)0x80000000) return (q16_t)0x80000000;
    return (q16_t)r;
}

static inline q16_t q16_sub_sat(q16_t a, q16_t b)
{
    return q16_sat64((int64_t)a - b);
}

static inline q16_t q16_clamp(q16_t a, q16_t lo, q16_t hi)
{
    if (a < lo) return lo;
    if (a > hi) return hi;
    return a;
}

static inline q16_t q16_abs(q16_t a) { return q16_sat64(a < 0 ? -(int64_t)a : a); }

/* 打印成 -12.3456 这样的形式,便于眼看 */
static inline void uart_putq16(q16_t a)
{
    uint32_t ip, magnitude;
    uint32_t fp;
    if (a < 0) uart_putc('-');
    magnitude = a < 0 ? (uint32_t)(-(int64_t)a) : (uint32_t)a;
    ip = magnitude / Q16_ONE;
    fp = (magnitude & 0xFFFFu) * 10000u >> Q16_SHIFT;
    uart_putu32((uint32_t)ip);
    uart_putc('.');
    if (fp < 1000u) uart_putc('0');
    if (fp < 100u)  uart_putc('0');
    if (fp < 10u)   uart_putc('0');
    uart_putu32(fp);
}

/* ---------------------------------------------------------------------- */
/* PID                                                                    */
/* ---------------------------------------------------------------------- */
/* 类型叫 pidq_t 不叫 pid_t:后者是 POSIX 已经占用的名字(<sys/types.h> 里就有),
 * 在这颗核上是裸机所以撞不上,但一旦要拿到 PC 上跑同一套代码来验证就会打起来 ——
 * 而这正是最该做的事。名字让开是最省事的办法。 */

typedef struct {
    q16_t kp, ki, kd;    /* physical per-second gains, never store kd/dt */
    q16_t dt_s;
    int64_t integ_wide;  /* Q32.32 preserves small integral increments */
    q16_t integ;          /* 积分累加器 */
    q16_t prev_err;       /* 上一次误差 */
    q16_t out_min, out_max;
    int   first;          /* 第一次调用时不算微分 */
} pidq_t;

/* 初始化。增益按**物理单位**给(每秒),dt_s 是控制周期(秒的 Q16)。
 *
 * !! 为什么必须传 dt —— 这是踩过的坑 !!
 *
 * pid_step 内部是"每拍"算一次,所以两处都要换算:
 *     积分: integ += ki·err·dt      -> 每拍用 ki·dt
 *     微分: d(err)/dt               -> 每拍用 kd/dt
 *
 * 第一版没做这个换算,而 dt = 1 ms,于是**有效微分增益被放大了 1000 倍** ——
 * 闭环直接变成振荡(角度在 ±8 度之间来回甩,角速度 ±300 度/秒),
 * 而纸面推导明明写着极点在 −26/−54。
 *
 * 换在初始化里做,好处有两条:增益是物理量(每秒),不用心算采样率;
 * 而且**除法只做一次,中断里一次都没有**。 */
static inline void pid_init(pidq_t *p, q16_t kp, q16_t ki, q16_t kd,
                            q16_t out_min, q16_t out_max, q16_t dt_s)
{
    p->kp    = kp;
    p->ki    = ki;
    p->kd    = kd;
    p->dt_s  = dt_s > 0 ? dt_s : 1;
    p->integ_wide = 0;
    p->integ = 0;
    p->prev_err = 0;
    p->out_min = out_min;
    p->out_max = out_max;
    p->first = 1;
}

static inline void pid_reset(pidq_t *p)
{
    p->integ = 0; p->integ_wide = 0; p->prev_err = 0; p->first = 1;
}

/* 一个采样周期的 PID。增益由 pid_init 传进来,已按 dt 换算好。
 *
 * 带抗积分饱和(anti-windup):输出被限幅时就不再累加积分。
 * 这一条对平衡车是必须的 —— 没有它,车一旦被按在地上几秒,积分项会涨到
 * 天上,松手瞬间满舵,直接飞出去。 */
/* Wide P+D sum before final clamp; rate is d(error)/dt in units/second. */
static inline q16_t pid_step_error_rate(pidq_t *p, q16_t err, q16_t rate)
{
    int64_t raw = ((int64_t)p->kp * err) / Q16_ONE
                + ((int64_t)p->kd * rate) / Q16_ONE + p->integ;
    q16_t out;
    out = q16_clamp(q16_sat64(raw), p->out_min, p->out_max);
    if ((raw < p->out_max && raw > p->out_min) ||
        (raw >= p->out_max && err < 0) || (raw <= p->out_min && err > 0)) {
        int64_t delta = (int64_t)q16_mul(p->ki, err) * p->dt_s;
        int64_t lo = (int64_t)p->out_min * Q16_ONE;
        int64_t hi = (int64_t)p->out_max * Q16_ONE;
        p->integ_wide += delta;
        if (p->integ_wide > hi) p->integ_wide = hi;
        if (p->integ_wide < lo) p->integ_wide = lo;
        p->integ = q16_sat64(p->integ_wide / Q16_ONE);
    }
    return out;
}

/* D acts on measured velocity, avoids derivative kick on setpoint changes. */
static inline q16_t pid_step_rate(pidq_t *p, q16_t setpoint, q16_t meas, q16_t meas_rate)
{
    q16_t err = q16_sub_sat(setpoint, meas);
    p->first = 0; p->prev_err = err;
    return pid_step_error_rate(p, err, q16_sub_sat(0, meas_rate));
}

static inline q16_t pid_step(pidq_t *p, q16_t setpoint, q16_t meas)
{
    q16_t err = q16_sub_sat(setpoint, meas);
    q16_t rate = p->first ? 0 : q16_div(q16_sub_sat(err, p->prev_err), p->dt_s);
    p->first = 0; p->prev_err = err;
    return pid_step_error_rate(p, err, rate);
}

/* ---------------------------------------------------------------------- */
/* 互补滤波:陀螺仪 + 加速度计                                             */
/* ---------------------------------------------------------------------- */
/* 陀螺仪短期准、长期漂;加速度计长期准、短期抖。互补滤波把两者按频率拼接,
 * 一个系数就够,比卡尔曼好调得多 —— 平衡车这个量级完全够用。
 *
 * 角度单位用"度"的 Q16 表示,角速度用"度/秒"。 */
typedef struct {
    q16_t angle;      /* 融合后的角度 */
    q16_t alpha;      /* 0.98 左右:信任陀螺仪的程度 */
} cfilt_t;

static inline void cfilt_init(cfilt_t *f, q16_t alpha, q16_t initial_angle)
{
    f->alpha = alpha;
    f->angle = initial_angle;
}

/* dt_us: 本次和上次的间隔(微秒)。gyro_dps: 陀螺仪角速度。acc_angle: 加计算出的角度。 */
static inline q16_t cfilt_update(cfilt_t *f, q16_t gyro_dps, q16_t acc_angle, uint32_t dt_us)
{
    /* 角度增量 = 角速度 × dt,dt 换成秒的 Q16 */
    q16_t dt_s = q16_frac((int32_t)dt_us, 1000000);
    q16_t predicted = q16_add_sat(f->angle, q16_mul(gyro_dps, dt_s));
    q16_t na = q16_sub_sat(acc_angle, predicted);
    q16_t one_minus = q16_sub_sat(Q16_ONE, f->alpha);

    f->angle = q16_add_sat(predicted, q16_mul(one_minus, na));
    return f->angle;
}

/* ---------------------------------------------------------------------- */
/* 上电时 GPIO 输出是老实的:先设输出使能,再写值                           */
/* ---------------------------------------------------------------------- */

static inline void board_init(void)
{
    GPIO_OE = LED_MASK;
    GPIO_OUTPUT = 0u;
}

/* RobotApb MMIO exposed by the integrated FPGA bitstream. */
#define ROBOT_BASE       0xF0030000u
#define ROBOT_STATUS     (*(volatile uint32_t *)(ROBOT_BASE + 0x00u))
#define ROBOT_ROLL_D10   (*(volatile int32_t  *)(ROBOT_BASE + 0x04u))
#define ROBOT_PITCH_D10  (*(volatile int32_t  *)(ROBOT_BASE + 0x08u))
#define ROBOT_YAW_D10    (*(volatile int32_t  *)(ROBOT_BASE + 0x0Cu))
#define ROBOT_ACCEL_X    (*(volatile int32_t  *)(ROBOT_BASE + 0x10u))
#define ROBOT_ACCEL_Y    (*(volatile int32_t  *)(ROBOT_BASE + 0x14u))
#define ROBOT_ACCEL_Z    (*(volatile int32_t  *)(ROBOT_BASE + 0x18u))
#define ROBOT_GYRO_X     (*(volatile int32_t  *)(ROBOT_BASE + 0x1Cu))
#define ROBOT_GYRO_Y     (*(volatile int32_t  *)(ROBOT_BASE + 0x20u))
#define ROBOT_GYRO_Z     (*(volatile int32_t  *)(ROBOT_BASE + 0x24u))
#define ROBOT_SAMPLE_CNT (*(volatile uint32_t *)(ROBOT_BASE + 0x28u))
#define ROBOT_SAMPLE_AGE (*(volatile uint32_t *)(ROBOT_BASE + 0x2Cu))
#define CAN0_CTRL        (*(volatile uint32_t *)(ROBOT_BASE + 0x80u))
#define CAN0_DATA_LO     (*(volatile uint32_t *)(ROBOT_BASE + 0x84u))
#define CAN0_DATA_HI     (*(volatile uint32_t *)(ROBOT_BASE + 0x88u))
#define CAN1_CTRL        (*(volatile uint32_t *)(ROBOT_BASE + 0x90u))
#define CAN1_DATA_LO     (*(volatile uint32_t *)(ROBOT_BASE + 0x94u))
#define CAN1_DATA_HI     (*(volatile uint32_t *)(ROBOT_BASE + 0x98u))

#endif /* MURAX_H */
