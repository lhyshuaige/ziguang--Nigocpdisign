.section .text.service_start,"ax",@progbits
.globl service_start
service_start:
 .option push
 .option norelax
 la gp,__global_pointer$
 .option pop
 la sp,__service_stack
 csrw mie,zero
 csrw mstatus,zero
 la t0,service_trap
 csrw mtvec,t0
 la t0,__service_bss_start
 la t1,__service_bss_end
1: bgeu t0,t1,2f
 sw zero,0(t0)
 addi t0,t0,4
 j 1b
2: call replay_main
service_trap:
 lui t0,0x10000
 csrr t1,mcause
 ori t1,t1,0xe0
 sw t1,0(t0)
3: j 3b

.section .text,"ax",@progbits
.globl replay_invoke
replay_invoke:
 la t0,saved_sp
 sw sp,0(t0)
 la t0,saved_ra
 sw ra,0(t0)
 la sp,_sp
 fence iorw,iorw
 .word 0x0000500f
 fence iorw,iorw
 .word 0x0000100f
 la t0,__reference_call_main
 jr t0

.globl replay_return
replay_return:
 la t0,saved_sp
 lw sp,0(t0)
 la t0,saved_ra
 lw ra,0(t0)
 ret
