.section .text.start,"ax",@progbits
.globl _start
_start:
 .option push
 .option norelax
 la gp,__global_pointer$
 .option pop
 la sp,__stack_top
 csrw mie,zero
 csrw mstatus,zero
 la t0,trap
 csrw mtvec,t0
 la t0,__data_load
 la t1,__data_start
 la t2,__data_end
1:
 bgeu t1,t2,2f
 lbu t3,0(t0)
 sb t3,0(t1)
 addi t0,t0,1
 addi t1,t1,1
 j 1b
2:
 la t0,__bss_start
 la t1,__bss_end
3:
 bgeu t0,t1,4f
 sb zero,0(t0)
 addi t0,t0,1
 j 3b
4:
 call nigo_application_main
trap:
 lui t0,0x10000
 csrr t1,mcause
 ori t1,t1,0xe0
 sw t1,0(t0)
5:
 j 5b
