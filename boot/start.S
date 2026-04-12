/*
 * EgoKernel 启动代码
 *
 * 这是内核的入口点，由树莓派固件在0x80000处调用
 * CPU启动时在EL2异常级别
 */

.section .text.boot
.global _start
.type _start, @function

_start:
    // 禁用所有中断
    msr daifclr, #0xF

    // 读取当前异常级别
    mrs x0, CurrentEL
    lsr x0, x0, #2      // 右移2位，让EL值在最低位                                                                                                                                                                               
    cmp x0, #2          // 比较是否等于2 (EL2)    
    bne wrong_el        // 如果不是EL2则跳转到错误处理

    // 设置异常向量表
    ldr x0, =exception_vectors
    msr    vbar_el2, x0

    // 设置栈指针
    ldr    x0, =__stack_top
    mov    sp, x0

    // 清除BSS段
    ldr    x0, =__bss_start
    ldr    x1, =__bss_end
    mov    x2, #0

clear_bss:
    cmp    x0, x1
    b.ge   eret_el1
    str    x2, [x0], #8        // 后变基模式
    b   clear_bss

eret_el1:
    mov    x0, #(1 << 31)      // EL1是AArch64
    msr    hcr_el2, x0         // Hypervisor配置寄存器，bit[31]=1表示EL1使用AArch64 

    // 设置SCTLR_EL1
    mrs x0, sctlr_el1         // 先读取系统控制寄存器当前值
    orr x0, x0, #(1 << 2)     // 只设置bit[2] 系统控制寄存器，bit[2]=1启用data cache
    msr sctlr_el1, x0         // 启用 caches

    // 返回到EL1，跳转到kernel_main
    mov    x0, #0 
    msr    spsel, x0          // 栈指针选择，0=SP_EL0, 1=SP_EL1 

    ldr    x0, =kernel_main
    msr    elr_el2, x0       // elr_el2：异常返回地址 

    eret                    // 退出到EL1
.size _start, .-_start   // 计算start的大小

wrong_el:
    mov x0, #1
    b   boot_error

boot_error:
    /* x0 = 错误码 */                                                                                                                                                                                                        
    mov x19, x0          // 保存到x19，调试器可查看                                                                                                                                                                          
hang:                                                                                                                                                                                                                        
    wfi                  // Wait For Interrupt，节省功耗                                                                                                                                                                      
    b   hang    

/* ===== USER IMPLEMENTATION REQUIRED =====
 *
 * 实现简单的异常处理函数
 * 这些函数用于捕获未处理的异常
 *
 * - sync_handler: 同步异常处理
 * - irq_handler: IRQ异常处理
 * - fiq_handler: FIQ异常处理
 * - serror_handler: SError异常处理
 *
 * 建议: 先用无限循环 b self 实现占位
 * ===== END USER IMPLEMENTATION ===== */

.global sync_handler
sync_handler:
    /* TODO: 实现同步异常处理 */
    b      sync_handler

.global irq_handler
irq_handler:
    /* TODO: 实现IRQ异常处理 */
    b      irq_handler

.global fiq_handler
fiq_handler:
    /* TODO: 实现FIQ异常处理 */
    b      fiq_handler

.global serror_handler
serror_handler:
    /* TODO: 实现SError异常处理 */
    b      serror_handler

/* ===== USER IMPLEMENTATION REQUIRED =====
 *
 * 实现完整的异常向量表
 *
 * ARM64异常向量表要求：
 * - 必须是 2KB 对齐 (.align 11)
 * - 包含16个向量，每个128字节对齐 (.align 7)
 *
 * 向量表布局 (参考 docs/boot.md):
 *
 * 偏移    异常来源              异常类型    说明
 * 0x000   EL1, Current SP with SP_EL0  同步       PSTATE.SP=0时的EL1异常
 * 0x080   EL1, Current SP with SP_EL0  IRQ        PSTATE.SP=0时的EL1异常
 * 0x100   EL1, Current SP with SP_EL0  FIQ        PSTATE.SP=0时的EL1异常
 * 0x180   EL1, Current SP with SP_EL0  SError     PSTATE.SP=0时的EL1异常
 * 0x200   EL1, Current SP with SP_EL1  同步       PSTATE.SP=1时的EL1异常
 * 0x280   EL1, Current SP with SP_EL1  IRQ        PSTATE.SP=1时的EL1异常
 * 0x300   EL1, Current SP with SP_EL1  FIQ        PSTATE.SP=1时的EL1异常
 * 0x380   EL1, Current SP with SP_EL1  SError     PSTATE.SP=1时的EL1异常
 * 0x400   EL1, from EL0               同步       处理来自EL0的异常
 * 0x480   EL1, from EL0               IRQ        处理来自EL0的异常
 * 0x500   EL1, from EL0               FIQ        处理来自EL0的异常
 * 0x580   EL1, from EL0               SError     处理来自EL0的异常
 * 0x600   EL0                        同步       EL0自身的异常
 * 0x680   EL0                        IRQ        EL0自身的异常
 * 0x700   EL0                        FIQ        EL0自身的异常
 * 0x780   EL0                        SError     EL0自身的异常
 *
 * 每个100(0x80)字节对齐，跳转到对应handler
 * ===== END USER IMPLEMENTATION ===== */

.section .text.vectors
.align 11
.global exception_vectors
.type exception_vectors, @function

exception_vectors:
    /* ========== EL1, Current SP with SP_EL0 ========== */

    /* 0x000: EL1, 同步异常, PSTATE.SP=0 */
    .align 7
el1_sync_sp0:
    b sync_handler

    /* 0x080: EL1, IRQ异常, PSTATE.SP=0 */
    .align 7
el1_irq_sp0:
    b irq_handler

    /* 0x100: EL1, FIQ异常, PSTATE.SP=0 */
    .align 7
el1_fiq_sp0:
    b fiq_handler

    /* 0x180: EL1, SError异常, PSTATE.SP=0 */
    .align 7
el1_serror_sp0:
    b serror_handler

    /* ========== EL1, Current SP with SP_EL1 ========== */

    /* 0x200: EL1, 同步异常, PSTATE.SP=1 */
    .align 7
el1_sync_sp1:
    b sync_handler

    /* 0x280: EL1, IRQ异常, PSTATE.SP=1 */
    .align 7
el1_irq_sp1:
    b irq_handler

    /* 0x300: EL1, FIQ异常, PSTATE.SP=1 */
    .align 7
el1_fiq_sp1:
    b fiq_handler

    /* 0x380: EL1, SError异常, PSTATE.SP=1 */
    .align 7
el1_serror_sp1:
    b serror_handler

    /* ========== EL1, taking exception from EL0 ========== */

    /* 0x400: EL1, 同步异常, 来自EL0 */
    .align 7
el1_sync_from_el0:
    b sync_handler

    /* 0x480: EL1, IRQ异常, 来自EL0 */
    .align 7
el1_irq_from_el0:
    b irq_handler

    /* 0x500: EL1, FIQ异常, 来自EL0 */
    .align 7
el1_fiq_from_el0:
    b fiq_handler

    /* 0x580: EL1, SError异常, 来自EL0 */
    .align 7
el1_serror_from_el0:
    b serror_handler

    /* ========== EL0 ========== */

    /* 0x600: EL0, 同步异常 */
    .align 7
el0_sync:
    b sync_handler

    /* 0x680: EL0, IRQ异常 */
    .align 7
el0_irq:
    b irq_handler

    /* 0x700: EL0, FIQ异常 */
    .align 7
el0_fiq:
    b fiq_handler

    /* 0x780: EL0, SError异常 */
    .align 7
el0_serror:
    b serror_handler

.size exception_vectors, .-exception_vectors
