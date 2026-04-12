# 启动和引导模块设计文档

## 概述

启动模块负责从树莓派4B固件加载内核开始，到进入C内核主函数之前的所有初始化工作。

## 启动流程

```
RPi4 Boot Flow:
┌─────────────┐
│ Power On    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ GPU loads   │ 读取SD卡上的start4.elf
│ firmware    │ (VideoCore firmware)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Load        │ 加载config.txt配置
│ config.txt  │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Load        │ 加载kernel8.img到0x80000
│ kernel8.img │ (物理地址)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Jump to     │ 跳转到_start
│ 0x80000     │ (在EL2异常级别)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ boot/start.S│ 汇编初始化代码
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Setup CPU   │ 设置CPU状态
│ State       │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Setup Stack │ 初始化内核栈
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Setup       │ 设置异常向量表
│ Vectors     │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Clear BSS   │ 清零BSS段
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Drop to EL1 │ 从EL2降到EL1
│             │ (内核运行级别)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Jump to C   │ 跳转到kernel_main()
│ kernel_main │
└─────────────┘
```

## 异常级别 (Exception Levels)

ARM64有4个异常级别，从高到低：

| EL | 权限 | 用途 |
|----|------|------|
| EL3 | 最高 | Secure Monitor (TrustZone) |
| EL2 | 高 | Hypervisor (虚拟化) |
| EL1 | 中 | 操作系统内核 |
| EL0 | 最低 | 用户程序 |

**启动时**：CPU在EL2启动
**内核运行**：切换到EL1

## 文件结构

```
boot/
├── start.S         # 汇编入口点，所有初始化代码
├── boot.c          # 启动C代码（可选）
└── linker.ld       # 链接脚本，定义内存布局

arch/arm64/boot/
└── head.S          # ARM64特定的启动辅助代码
```

## start.S 关键代码段

### 1. 入口点和基础设置
- 在内核启动早期，中断处理基础设施尚未准备好，如果此时发生中断，系统将无法正确处理，导致崩溃。
- 启动流程中的中断处理
  启动阶段                 中断状态                                             
  ─────────────────────────────────────────                                     
  1. CPU 上电              ← 硬件默认可能启用                                   
  2. 禁止中断              ✓ 安全状态                                           
  3. 设置栈                ✓                                                    
  4. 清零 BSS              ✓                                                    
  5. 设置异常向量表        ✓                                                    
  6. 初始化 GIC            ✓                                                    
  7. 注册 IRQ 处理器       ✓                                                    
  8. 启用中断              ← 主动启用 
-              
```assembly
.section .text.boot
.global _start
_start:
    // 禁用所有中断
    msr    daifclr, #0xF

    // 设置异常向量表基地址
    ldr    x0, =exception_vectors
    msr    vbar_el2, x0
```

### 2. 栈设置

```assembly
    // 设置栈指针
    ldr    x0, =__stack_top
    mov    sp, x0
```

### 3. 清零BSS

```assembly
    // 获取BSS起始和结束地址
    ldr    x0, =__bss_start
    ldr    x1, =__bss_end
    mov    x2, #0

clear_bss:
    str    x2, [x0], #8
    cmp    x0, x1
    b.ne   clear_bss
```

### 4. 降到EL1

```assembly
    // 配置EL1的寄存器
    mov    x0, #(1 << 31)      // EL1是AArch64
    msr    hcr_el2, x0

    // 设置SCTLR_EL1
    mov    x0, #(1 << 2)      // 启用 caches
    msr    sctlr_el1, x0

    // 返回到EL1，跳转到kernel_main
    mov    x0, #0             // SP_EL0 = 0
    msr    spsel, x0

    ldr    x0, =kernel_main
    msr    elr_el2, x0

    eret                    // 退出到EL1
```

## 链接脚本 (linker.ld)

### 内存布局

```ld
ENTRY(_start)

SECTIONS {
    /* 内核加载地址：0x80000 */
    . = 0x80000;

    /* 启动代码放在最开始 */
    .text.boot : {
        *(.text.boot)
    }

    /* 代码段 */
    .text : {
        *(.text)
    }

    /* 只读数据段 */
    .rodata : {
        *(.rodata)
    }

    /* 数据段 */
    .data : {
        *(.data)
    }

    /* BSS段（未初始化数据） */
    .bss : {
        __bss_start = .;
        *(.bss)
        __bss_end = .;
    }

    /* 内核栈（16KB） */
    . = ALIGN(16);
    .stack : {
        __stack_bottom = .;
        . = . + 0x4000;
        __stack_top = .;
    }

    /* 堆起始地址 */
    . = ALIGN(4096);
    __heap_start = .;
}
```

### 内存分布图

```
物理内存布局（0x80000开始）：
┌──────────────────────────────────────┐
│ 0x80000                              │
│ .text.boot    (启动代码)             │
├──────────────────────────────────────┤
│ .text         (内核代码)             │
├──────────────────────────────────────┤
│ .rodata       (只读数据)             │
├──────────────────────────────────────┤
│ .data         (已初始化数据)         │
├──────────────────────────────────────┤
│ .bss          (未初始化数据)         │
├──────────────────────────────────────┤
│ .stack        (内核栈，16KB)         │
├──────────────────────────────────────┤
│ [后续用于堆和伙伴系统]                │
└──────────────────────────────────────┘
```

## 异常向量表

### 异常类型说明

ARM64定义了四种异常类型：

| 异常类型 | 名称 | 触发原因 |
|----------|------|----------|
| **Synchronous** | 同步异常 | 指令执行时的异常，如：非法指令、数据中止、系统调用(SVC)等 |
| **IRQ** | 中断请求 | 外部硬件中断，如：定时器、UART、网络等 |
| **FIQ** | 快速中断请求 | 高优先级的外部中断（在ARMv8中通常由IRQ替代） |
| **SError** | 系统错误 | 外部中止错误，如：内存总线错误、异步数据中止等 |

### ARM64异常向量表完整布局

异常向量表必须是 **2KB 对齐**，包含 **16个向量**，每个向量 **128字节对齐**。

#### 向量表结构

```
偏移       异常来源              异常类型    说明
─────────────────────────────────────────────────────────────────
0x000      EL1, 当前SP           同步       EL1执行时同步异常（系统调用等）
0x080      EL1, 当前SP           IRQ        EL1执行时硬件中断
0x100      EL1, 当前SP           FIQ        EL1执行时快速中断
0x180      EL1, 当前SP           SError     EL1执行时系统错误
0x200      EL1, SP_EL0           同步       EL0→EL1时同步异常（用户态异常）
0x280      EL1, SP_EL0           IRQ        EL0→EL1时硬件中断
0x300      EL1, SP_EL0           FIQ        EL0→EL1时快速中断
0x380      EL1, SP_EL0           SError     EL0→EL1时系统错误
0x400      EL0                   同步       EL0执行时同步异常
0x480      EL0                   IRQ        EL0执行时硬件中断
0x500      EL0                   FIQ        EL0执行时快速中断
0x580      EL0                   SError     EL0执行时系统错误
0x600      Lower EL (AArch64)     同步       处理从更低EL来的同步异常
0x680      Lower EL (AArch64)     IRQ        处理从更低EL来的硬件中断
0x700      Lower EL (AArch64)     FIQ        处理从更低EL来的快速中断
0x780      Lower EL (AArch64)     SError     处理从更低EL来的系统错误
```

#### 栈指针说明

- **当前SP (Current SP with SP_ELx)**: 使用当前异常级别选定的栈指针
  - 当 PSTATE.SP = 0 时使用 SP_EL0
  - 当 PSTATE.SP = 1 时使用 SP_EL1

- **SP_EL0**: 强制使用EL0的栈指针（用于处理用户态异常）

#### 各向量在EgoKernel中的作用

| 向量 | 用途 | 处理优先级 |
|-------|------|-----------|
| EL1, 同步 (当前SP) | 内核态系统调用、非法指令等 | 高 |
| EL1, IRQ (当前SP) | 内核态硬件中断（内核抢占） | 高 |
| EL1, SError (当前SP) | 内核态内存错误、总线错误 | 极高 |
| EL1, 同步 (SP_EL0) | 用户态异常（缺页、非法操作） | 中 |
| EL1, IRQ (SP_EL0) | 用户态硬件中断（设备驱动） | 中 |
| EL1, SError (SP_EL0) | 用户态内存错误 | 极高 |
| EL0, 同步 | 用户态自身异常（不应直接发生） | 低 |
| EL0, IRQ | 用户态硬件中断（通常由EL1处理） | 低 |
| EL0, SError | 用户态系统错误（通常由EL1处理） | 低 |
| Lower EL (AArch64) | 处理从更低EL来的异常（EL2/EL3使用） | 低 |

### 完整的16向量实现

```assembly
.section .text.vectors
.align 11              /* 2KB对齐 */
.global exception_vectors
.type exception_vectors, @function

exception_vectors:
    /* ========== EL1, Current SP with SP_EL0 ========== */

    /* 0x000: EL1, 同步异常, 当前SP */
    .align 7           /* 128字节对齐 */
el1_sync_current_sp:
    b sync_handler

    /* 0x080: EL1, IRQ异常, 当前SP */
    .align 7
el1_irq_current_sp:
    b irq_handler

    /* 0x100: EL1, FIQ异常, 当前SP */
    .align 7
el1_fiq_current_sp:
    b fiq_handler

    /* 0x180: EL1, SError异常, 当前SP */
    .align 7
el1_serror_current_sp:
    b serror_handler

    /* ========== EL1, Current SP with SP_EL1 ========== */

    /* 0x200: EL1, 同步异常, SP_EL1 */
    .align 7
el1_sync_sp_el1:
    b sync_handler

    /* 0x280: EL1, IRQ异常, SP_EL1 */
    .align 7
el1_irq_sp_el1:
    b irq_handler

    /* 0x300: EL1, FIQ异常, SP_EL1 */
    .align 7
el1_fiq_sp_el1:
    b fiq_handler

    /* 0x380: EL1, SError异常, SP_EL1 */
    .align 7
el1_serror_sp_el1:
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
```

### EgoKernel 启动阶段的简化实现

对于启动阶段，可以暂时实现 **12个向量** 版本（EL1的8个 + EL0的4个），因为：

1. 启动时直接从EL2跳到EL1，不会经过EL0
2. Lower EL (AArch64) 向量主要用于EL2/EL3处理更底层异常
3. 暂时所有handler都跳到无限循环，后续再细化

简化版本：
```assembly
exception_vectors:
    /* EL1, Current SP with SP_EL0 (4个) */
    .align 7;  b sync_handler    /* 0x000 */
    .align 7;  b irq_handler     /* 0x080 */
    .align 7;  b fiq_handler     /* 0x100 */
    .align 7;  b serror_handler  /* 0x180 */

    /* EL1, Current SP with SP_EL1 (4个) */
    .align 7;  b sync_handler    /* 0x200 */
    .align 7;  b irq_handler     /* 0x280 */
    .align 7;  b fiq_handler     /* 0x300 */
    .align 7;  b serror_handler  /* 0x380 */

    /* EL0 (4个) */
    .align 7;  b sync_handler    /* 0x400 */
    .align 7;  b irq_handler     /* 0x480 */
    .align 7;  b fiq_handler     /* 0x500 */
    .align 7;  b serror_handler  /* 0x580 */
```

## C内核入口 (kernel/main.c)

```c
#include <kernel.h>

void kernel_main(void) {
    // 1. 首先初始化UART用于调试输出
    uart_init();
    uart_puts("EgoKernel starting...\n");

    // 2. 初始化内存管理
    mm_init();
    uart_puts("Memory manager initialized\n");

    // 3. 初始化中断控制器
    gic_init();
    uart_puts("GIC initialized\n");

    // 4. 初始化定时器
    timer_init();
    uart_puts("Timer initialized\n");

    // 5. 启用中断
    enable_irq();

    // 6. 内核主循环
    while (1) {
        wfi();  // Wait For Interrupt
    }
}
```

## 关键寄存器

| 寄存器 | 用途 | 异常级别 |
|--------|------|----------|
| VBAR_ELx | 异常向量表基地址 | EL1/EL2/EL3 |
| SP_ELx | 栈指针 | EL0/EL1 |
| SCTLR_ELx | 系统控制寄存器 | EL1/EL2/EL3 |
| DAIF | 中断屏蔽位 | 当前EL |
| ELR_ELx | 异常返回地址 | EL1/EL2/EL3 |
| SPSR_ELx | 异常返回状态 | EL1/EL2/EL3 |
| HCR_EL2 |Hypervisor配置寄存器，bit[31]=1表示EL1使用AArch64|EL2|
| SPSSEL |栈指针选择，0=SP_EL0, 1=SP_EL1|当前EL|

## 配置文件 (config.txt)

树莓派启动时读取config.txt配置：

```ini
# 禁用启动时显示的彩色方块
disable_overscan=1

# 内核文件
kernel=kernel8.img

# 内核命令行参数
cmdline="console=ttyAMA0,115200"

# 启用UART
enable_uart=1

# 核心频率（可选）
arm_freq=1500

# 内存分配（可选）
gpu_mem=16
```

## 启动时检查清单

- [ ] 核心在正确的异常级别运行
- [ ] 栈指针正确设置
- [ ] BSS段已清零
- [ ] 异常向量表已设置
- [ ] UART初始化并能输出
- [ ] 内存管理器初始化成功

## 调试技巧

1. **无输出时检查**：确认UART初始化参数正确（波特率115200，GPIO 14/15）
2. **启动失败**：检查链接脚本中的入口点地址是否为0x80000
3. **异常处理**：在异常向量表中放置调试输出，捕获异常

## 参考资料

- [ARM Architecture Reference Manual ARMv8](https://developer.arm.com/documentation/ddi0487/latest/)
- [Raspberry Pi 4 Boot Sequence](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html)
- [AArch64 Exception Levels](https://developer.arm.com/documentation/ddi0406/latest/)
