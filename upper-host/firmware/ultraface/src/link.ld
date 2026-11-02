OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { IMAGE(rx) : ORIGIN = 0x82000000, LENGTH = 2M
         RAM(rwx) : ORIGIN = 0x82800000, LENGTH = 128K }
SECTIONS {
 .text : { KEEP(*(.text.start)) *(.text .text.*) *(.rodata .rodata.*) . = ALIGN(16); } > IMAGE
 .data : { __data_start = .; __global_pointer$ = . + 0x800;
           *(.sdata .sdata.*) *(.data .data.*) . = ALIGN(16); __data_end = .; } > RAM AT> IMAGE
 __data_load = LOADADDR(.data);
 .bss (NOLOAD) : { __bss_start = .; *(.sbss .sbss.*) *(.bss .bss.*) *(COMMON) . = ALIGN(16); __bss_end = .; } > RAM
 __stack_top = ORIGIN(RAM) + LENGTH(RAM);
 ASSERT(__bss_end < __stack_top - 32768, "Insufficient application stack")
 /DISCARD/ : { *(.comment) *(.eh_frame .eh_frame.*) }
}
