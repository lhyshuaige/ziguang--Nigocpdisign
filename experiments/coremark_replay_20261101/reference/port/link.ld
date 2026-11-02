OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0x80000000, LENGTH = 256K }
SECTIONS {
  .init : { KEEP(*(.init)) } >ram
  .text : { *(.text .text.*) } >ram
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } >ram
  .data : { *(.data .data.*) . = ALIGN(8); __global_pointer$ = . + 0x800; *(.sdata .sdata.*) } >ram
  .bss (NOLOAD) : { . = ALIGN(4); __bss_start = .; *(.sbss .sbss.* .bss .bss.* COMMON) . = ALIGN(4); _end = .; } >ram
  _sp = ORIGIN(ram)+LENGTH(ram)-16;
  /DISCARD/ : { *(.comment .note .eh_frame*) }
}
