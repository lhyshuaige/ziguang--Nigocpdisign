.section .text,"ax",@progbits
.globl ngb_jump
.type ngb_jump,@function
ngb_jump:
 csrw mie,zero
 csrw mstatus,zero
 fence iorw,iorw
 .word 0x0000500f
 fence iorw,iorw
 .word 0x0000100f
 jalr zero,a0,0
.size ngb_jump,.-ngb_jump
