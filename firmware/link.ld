OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { BOOT(rx) : ORIGIN = 0x80000000, LENGTH = 64K
         RAM(rwx) : ORIGIN = 0x81000000, LENGTH = 128K }
SECTIONS {
 .text : { KEEP(*(.text.start)) *(.text .text.*) *(.rodata .rodata.*) . = ALIGN(16); } > BOOT
 .data : { __data_start = .; __global_pointer$ = . + 0x800;
           *(.sdata .sdata.*) *(.data .data.*) . = ALIGN(16); __data_end = .; } > RAM AT> BOOT
 __data_load = LOADADDR(.data);
 .bss (NOLOAD) : { __bss_start = .; *(.sbss .sbss.*) *(.bss .bss.*) *(COMMON) . = ALIGN(16); __bss_end = .; } > RAM
 __stack_top = ORIGIN(RAM) + LENGTH(RAM);
 ASSERT(__bss_end < __stack_top - 32768, "Insufficient CPU stack")
 /DISCARD/ : { *(.comment) *(.eh_frame .eh_frame.*) }
}
