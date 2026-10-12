/* Application startup, trap ABI v2. Resident code saves context; slot = C. */
    .section .text.start, "ax", @progbits
    .globl _start
    .type _start, @function
_start:
    csrci mstatus, 8
    csrw mie, zero
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, _stack_top
    andi sp, sp, -16
    la t0, _bss_start
    la t1, _bss_end
    bgeu t0, t1, 2f
1:  sw zero, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b
2:  la t0, _trap_vector_slot
    la t1, trap_handler
    sw t1, 0(t0)
    call main
3:  j 3b
    .size _start, .-_start
