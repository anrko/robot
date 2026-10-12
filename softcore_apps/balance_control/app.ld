/* Linker script for application images loaded by the Murax UART bootloader.
 * The bootloader receives the raw binary and stores it at 0x80002000, so the
 * program must be linked to run from there.
 */
OUTPUT_FORMAT("elf32-littleriscv", "elf32-littleriscv", "elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)

/* 0x80002000 .. 0x8000C000 = 40960 bytes, the limit enforced by the
 * bootloader (IMAGE_MAX) and by host/murax_loader.py.  The region starts past
 * the bootloader's 8 KiB window and ends where the stack begins. */
MEMORY
{
  RAM (rwx) : ORIGIN = 0x80002000, LENGTH = 0xA000
}

SECTIONS
{
  /* The bootloader owns the real trap vector, so here the image's own copy
   * of the dispatcher is just placed inline. */
  .text : ALIGN(4)
  {
    KEEP(*(.text.start))
    KEEP(*(.text.trap))
    *(.text .text.*)
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
    *(.data .data.*)
    *(.sdata .sdata.*)
    . = ALIGN(4);
  } > RAM

  .bss (NOLOAD) : ALIGN(4)
  {
    _bss_start = .;
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > RAM

  /* Same slot the bootloader's resident trap vector reads. */
  PROVIDE(_trap_vector_slot = 0x80001FFC);

  PROVIDE(_stack_top = 0x80010000);
  /* gp 只在启用 small-data(-msmall-data-limit>0)时才会被用到,而 build.sh
   * 明确传了 -msmall-data-limit=0,所以它现在是个不参与寻址的哑符号。
   * 但原来那个值 0x80000800 是**bootloader 的地盘** —— 哪天有人把 small-data
   * 打开,gp 就会带着程序去读写 bootloader 的代码。指向本镜像就对了。 */
  PROVIDE(__global_pointer$ = _bss_end);

  /DISCARD/ : { *(.comment) *(.note*) *(.riscv.attributes) }
}
