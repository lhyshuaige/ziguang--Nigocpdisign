OUTPUT_ARCH("riscv")
ENTRY(service_start)
MEMORY { ram (rwx) : ORIGIN = 0x82000000, LENGTH = 256K
 service(rx) : ORIGIN = 0x82080000, LENGTH = 256K
 service_ram(rw) : ORIGIN = 0x82100000, LENGTH = 256K }
SECTIONS {
  .init : { KEEP(*bench_*.o(.init)) } >ram
  .text : { *bench_*.o(.text .text.*) } >ram
  .rodata : { *bench_*.o(.rodata .rodata.* .srodata .srodata.*) } >ram
  .data : { *bench_*.o(.data .data.*) . = ALIGN(8); __global_pointer$ = . + 0x800; *bench_*.o(.sdata .sdata.*) } >ram
  .bss (NOLOAD) : { . = ALIGN(4); __bss_start = .; *bench_*.o(.sbss .sbss.* .bss .bss.* COMMON) . = ALIGN(4); _end = .; } >ram
  _sp = ORIGIN(ram)+LENGTH(ram)-16;
  .service : { KEEP(*svc_*.o(.text.service_start)) *svc_*.o(.text .text.*) *(.text .text.*) } >service
  .service_rodata : { *svc_*.o(.rodata .rodata.* .srodata .srodata.*) } >service
  .service_data : { *svc_*.o(.data .data.* .sdata .sdata.*) } >service
  ASSERT(SIZEOF(.service_data)==0, "Service data must be initialized explicitly")
  .service_bss (NOLOAD) : { . = ALIGN(4); __service_bss_start = .; *svc_*.o(.sbss .sbss.* .bss .bss.* COMMON) . = ALIGN(4); __service_bss_end = .; } >service_ram
  __service_stack = ORIGIN(service_ram)+LENGTH(service_ram)-16;
  __reference_call_main = 0x82000028;
  /DISCARD/ : { *(.comment .note .eh_frame*) }
}
