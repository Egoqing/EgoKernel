# 中断处理模块设计文档

## 概述

中断处理模块负责管理树莓派4B的硬件中断，包括ARM异常向量和GIC-400中断控制器。本模块提供中断注册、分发和处理机制，支持定时器、UART、GPIO等外设中断。

## 架构概览

```
中断处理架构：
┌─────────────────────────────────────────────────────┐
│               硬件中断源                            │
│  [Timer] [UART] [GPIO] [USB] [Ethernet] ...       │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
              ┌────────────────┐
              │    GIC-400     │
              │ 中断控制器     │
              └───────┬────────┘
                      │
                      ▼
              ┌────────────────┐
              │ ARM Exception  │
              │   Vector       │
              └───────┬────────┘
                      │
                      ▼
              ┌────────────────┐
              │  IRQ Dispatcher │
              │  (irq.c)       │
              └───────┬────────┘
                      │
         ┌────────────┼────────────┐
         │            │            │
         ▼            ▼            ▼
    ┌────────┐  ┌────────┐  ┌────────┐
    │Timer   │  │UART    │  │Custom  │
    │Handler │  │Handler │  │Handler │
    └────────┘  └────────┘  └────────┘
```

## GIC-400中断控制器

### 概述

树莓派4B使用ARM GIC-400 (Generic Interrupt Controller v2) 中断控制器。

```
GIC-400架构：
┌─────────────────────────────────────┐
│         Distributor (GICD)          │
│    中断优先级、路由、使能控制        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│    CPU Interface (GICC)             │
│    中断信号、优先级屏蔽、EOI         │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│         CPU Core                     │
└─────────────────────────────────────┘
```

### 中断类型

| 类型 | 说明 | ID范围 |
|------|------|--------|
| SGI (Software Generated Interrupt) | 软件中断（CPU间通信） | 0-15 |
| PPI (Private Peripheral Interrupt) | 私有外设中断（每核独立） | 16-31 |
| SPI (Shared Peripheral Interrupt) | 共享外设中断 | 32-1019 |

### 常用中断ID

| 中断 | 硬件 | ID |
|------|------|-----|
| ARM Generic Timer | System Timer | 27 |
| UART0 | PL011 | 57 |
| UART1 | PL011 | 153 |
| GPIO 0-27 | GPIO 1 | 48 |
| GPIO 28-45 | GPIO 2 | 49 |
| GPIO 46-53 | GPIO 3 | 50 |

### GIC寄存器

#### Distributor (GICD) - 基地址: 0xFF801000

| 寄存器 | 偏移 | 说明 |
|--------|------|------|
| GICD_CTLR | 0x000 | 控制寄存器 |
| GICD_TYPER | 0x004 | 类型寄存器 |
| GICD_ISENABLERn | 0x100 + 4n | 中断使能集 |
| GICD_ICENABLERn | 0x180 + 4n | 中断使能清除 |
| GICD_ISPENDRn | 0x200 + 4n | 中断挂起集 |
| GICD_ICPENDRn | 0x280 + 4n | 中断挂起清除 |
| GICD_IPRIORITYRn | 0x400 + 4n | 中断优先级 |
| GICD_ITARGETSRn | 0x800 + 4n | 中断目标CPU |
| GICD_ICFGRn | 0xC00 + 4n | 中断配置（边沿/电平） |

#### CPU Interface (GICC) - 基地址: 0xFF802000

| 寄存器 | 偏移 | 说明 |
|--------|------|------|
| GICC_CTLR | 0x000 | 控制寄存器 |
| GICC_PMR | 0x004 | 优先级掩码 |
| GICC_BPR | 0x008 | 二进制点 |
| GICC_IAR | 0x00C | 中断应答 |
| GICC_EOIR | 0x010 | 中断结束 |
| GICC_RPR | 0x014 | 运行优先级 |
| GICC_HPPIR | 0x018 | 最高优先级挂起中断 |
| GICC_ABPR | 0x01C | 二进制点（Aliased） |
| GICC_AIAR | 0x020 | 中断应答（Aliased） |
| GICC_AEOIR | 0x024 | 中断结束（Aliased） |
| GICC_AHPPIR | 0x028 | 最高优先级挂起中断（Aliased） |

### GIC初始化流程

```c
void gic_init(void) {
    // 1. 初始化Distributor
    gicd_init();

    // 2. 初始化CPU Interface
    gicc_init();

    // 3. 启用CPU Interface
    gicc_enable();
}

void gicd_init(void) {
    // 禁用Distributor
    GICD->CTLR = 0;

    // 等待Distributor禁用完成
    while (GICD->CTLR & 1);

    // 清除所有中断的挂起状态
    for (int i = 0; i < GICD_ITARGETSRN_COUNT; i++) {
        GICD->ICENABLER[i] = 0xFFFFFFFF;
        GICD->ICPENDR[i] = 0xFFFFFFFF;
    }

    // 配置所有SPI为边沿触发
    for (int i = 2; i < GICD_ICFGRN_COUNT; i++) {
        GICD->ICFGR[i] = 0;
    }

    // 设置所有中断的优先级
    for (int i = 0; i < GICD_IPRIORITYRN_COUNT; i++) {
        GICD->IPRIORITYR[i] = 0xA0A0A0A0;
    }

    // 将所有SPI路由到CPU0
    for (int i = 32; i < GICD_ITARGETSRN_COUNT; i++) {
        GICD->ITARGETSR[i] = 0x01010101;
    }

    // 启用Distributor
    GICD->CTLR = 1;
}

void gicc_init(void) {
    // 设置优先级掩码（允许所有优先级）
    GICC->PMR = 0xFF;

    // 禁用抢占
    GICC->BPR = 0;

    // 启用CPU Interface
    GICC->CTLR = 1;
}
```

## ARM异常向量表

### 向量表布局

ARM64异常向量表必须是2KB对齐，包含16个向量：

```
异常向量表布局 (0x2000字节，16个128字节条目)：

偏移    当前SP使用 (SP_ELx)   使用SP_EL0
─────────────────────────────────────────────
0x000   Sync from ELx           Sync from EL0
0x080   IRQ from ELx            IRQ from EL0
0x100   FIQ from ELx            FIQ from EL0
0x180   SError from ELx         SError from EL0
```

### vectors.S 实现

```assembly
.align 11
.global exception_vectors
exception_vectors:
    /* EL1, 使用当前SP */
    .align 7
    el1_sync_current_sp:
        b    sync_handler

    .align 7
    el1_irq_current_sp:
        b    irq_handler

    .align 7
    el1_fiq_current_sp:
        b    fiq_handler

    .align 7
    el1_serror_current_sp:
        b    serror_handler

    /* EL1, 使用SP_EL0 */
    .align 7
    el1_sync_sp_el0:
        b    sync_handler

    .align 7
    el1_irq_sp_el0:
        b    irq_handler

    .align 7
    el1_fiq_sp_el0:
        b    fiq_handler

    .align 7
    el1_serror_sp_el0:
        b    serror_handler

    /* EL0 */
    .align 7
    el0_sync:
        b    sync_handler

    .align 7
    el0_irq:
        b    irq_handler

    .align 7
    el0_fiq:
        b    fiq_handler

    .align 7
    el0_serror:
        b    serror_handler
```

### 异常处理流程

```
中断发生时的流程：

1. 硬件保存：
   - SPSR_ELx (程序状态)
   - ELR_ELx  (返回地址)
   - ES_ELx   (异常综合信息)

2. 跳转到异常向量表对应入口

3. 保存上下文：
   - 通用寄存器 (x0-x30)
   - 栈指针 (sp)

4. 调用C语言处理函数

5. 恢复上下文

6. ERET指令返回
```

## 中断分发器 (IRQ Dispatcher)

### 数据结构

```c
// 中断处理函数类型
typedef void (*irq_handler_t)(void *data);

// 中断描述符
typedef struct irq_desc {
    uint32_t irq;               // 中断号
    irq_handler_t handler;      // 处理函数
    void *data;                 // 处理函数参数
    char name[32];              // 名称
    uint32_t flags;            // 标志
    struct list_head list;     // 链表节点
} irq_desc_t;

// 中断统计
typedef struct irq_stats {
    uint64_t count;             // 总中断次数
    uint64_t spurious;          // 伪中断次数
} irq_stats_t;
```

### 中断注册

```c
// 注册中断处理函数
int request_irq(uint32_t irq, irq_handler_t handler,
                uint32_t flags, const char *name, void *data) {
    irq_desc_t *desc;

    // 分配描述符
    desc = kmalloc(sizeof(irq_desc_t));
    if (!desc) {
        return -1;
    }

    // 填充描述符
    desc->irq = irq;
    desc->handler = handler;
    desc->data = data;
    desc->flags = flags;
    strncpy(desc->name, name, sizeof(desc->name) - 1);

    // 加入中断链表
    list_add(&desc->list, &irq_descs[irq]);

    // 使能GIC中的中断
    gic_enable_irq(irq);

    return 0;
}

// 注销中断
void free_irq(uint32_t irq, void *data) {
    irq_desc_t *desc, *tmp;

    list_for_each_entry_safe(desc, tmp, &irq_descs[irq], list) {
        if (desc->data == data) {
            // 禁用GIC中的中断
            gic_disable_irq(irq);
            // 从链表移除
            list_del(&desc->list);
            // 释放描述符
            kfree(desc);
        }
    }
}
```

### IRQ处理流程

```assembly
/* IRQ处理汇编入口 */
irq_handler:
    // 保存上下文
    sub     sp, sp, #272
    stp     x0, x1, [sp, #0]
    stp     x2, x3, [sp, #16]
    stp     x4, x5, [sp, #32]
    stp     x6, x7, [sp, #48]
    stp     x8, x9, [sp, #64]
    stp     x10, x11, [sp, #80]
    stp     x12, x13, [sp, #96]
    stp     x14, x15, [sp, #112]
    stp     x16, x17, [sp, #128]
    stp     x18, x19, [sp, #144]
    stp     x20, x21, [sp, #160]
    stp     x22, x23, [sp, #176]
    stp     x24, x25, [sp, #192]
    stp     x26, x27, [sp, #208]
    stp     x28, x29, [sp, #224]
    str     x30, [sp, #240]

    // 保存SPSR和ELR
    mrs     x0, spsr_el1
    mrs     x1, elr_el1
    stp     x0, x1, [sp, #248]

    // 调用C处理函数
    bl      handle_irq

    // 恢复上下文
    ldp     x0, x1, [sp, #248]
    msr     spsr_el1, x0
    msr     elr_el1, x1

    ldp     x28, x29, [sp, #224]
    ldp     x26, x27, [sp, #208]
    ldp     x24, x25, [sp, #192]
    ldp     x22, x23, [sp, #176]
    ldp     x20, x21, [sp, #160]
    ldp     x18, x19, [sp, #144]
    ldp     x16, x17, [sp, #128]
    ldp     x14, x15, [sp, #112]
    ldp     x12, x13, [sp, #96]
    ldp     x10, x11, [sp, #80]
    ldp     x8, x9, [sp, #64]
    ldp     x6, x7, [sp, #48]
    ldp     x4, x5, [sp, #32]
    ldp     x2, x3, [sp, #16]
    ldp     x0, x1, [sp, #0]
    ldr     x30, [sp, #240]
    add     sp, sp, #272

    eret
```

### C语言IRQ处理

```c
void handle_irq(void) {
    uint32_t irq;

    // 从GICC_IAR读取中断号
    irq = GICC->IAR & 0x3FF;

    // 处理伪中断
    if (irq >= 1020) {
        irq_stats.spurious++;
        return;
    }

    // 更新统计
    irq_stats.count++;

    // 查找并调用处理函数
    irq_desc_t *desc;
    list_for_each_entry(desc, &irq_descs[irq], list) {
        desc->handler(desc->data);
    }

    // 发送中断结束信号
    GICC->EOIR = irq;
}
```

## 常用中断处理示例

### 定时器中断

```c
#include <timer.h>
#include <int.h>

static void timer_handler(void *data) {
    // 清除定时器中断
    timer_clear_interrupt();

    // 更新系统时间
    update_system_time();

    // 唤醒调度器
    scheduler_tick();

    // 唤醒睡眠进程
    wake_up_sleeping_processes();
}

void timer_init(void) {
    // 配置ARM Generic Timer
    // 设置定时器周期
    timer_set_period(10000);  // 10ms

    // 注册中断处理
    request_irq(IRQ_TIMER, timer_handler, 0, "timer", NULL);

    // 启用定时器
    timer_enable();
}
```

### UART中断

```c
#include <uart.h>
#include <int.h>

static void uart_rx_handler(void *data) {
    // 读取接收到的字符
    char c = uart_read_char();

    // 放入接收缓冲区
    uart_rx_buffer_put(c);

    // 唤醒等待的进程
    wake_up(&uart_read_wait);
}

static void uart_tx_handler(void *data) {
    // 发送下一个字符
    if (!uart_tx_buffer_empty()) {
        uart_write_char(uart_tx_buffer_get());
    } else {
        // 禁用发送中断
        uart_disable_tx_interrupt();
    }
}

void uart_init_with_interrupts(void) {
    // 初始化UART
    uart_init();

    // 注册中断处理
    request_irq(IRQ_UART, uart_rx_handler, 0, "uart", NULL);

    // 使能接收中断
    uart_enable_rx_interrupt();
}
```

## 初始化流程

```
中断系统初始化：

kernel_main()
    │
    ▼
boot/start.S
    │
    ▼
设置异常向量表
    │
    ▼
kernel/main.c
    │
    ▼
int_init()
    ├── gic_init()
    │   ├── gicd_init()
    │   │   ├── 禁用Distributor
    │   │   ├── 清除所有中断
    │   │   ├── 配置边沿/电平触发
    │   │   ├── 设置优先级
    │   │   ├── 设置目标CPU
    │   │   └── 启用Distributor
    │   └── gicc_init()
    │       ├── 设置优先级掩码
    │       └── 启用CPU Interface
    │
    ├── 初始化中断描述符数组
    │
    └── enable_irq()
        └── 清除DAIF标志
```

## 接口设计

```c
// include/int.h
#include <types.h>

// GIC接口
void gic_init(void);
void gic_enable_irq(uint32_t irq);
void gic_disable_irq(uint32_t irq);
void gic_set_irq_priority(uint32_t irq, uint8_t priority);
void gic_set_irq_type(uint32_t irq, uint32_t type);

// 中断注册接口
typedef void (*irq_handler_t)(void *data);

int request_irq(uint32_t irq, irq_handler_t handler,
                uint32_t flags, const char *name, void *data);
void free_irq(uint32_t irq, void *data);

// 中断控制接口
void enable_irq(void);
void disable_irq(void);
void local_irq_save(uint64_t *flags);
void local_irq_restore(uint64_t flags);
```

## 调试技巧

1. **中断风暴检测**：记录每个中断的触发次数
2. **嵌套中断**：在处理函数中打印嵌套深度
3. **延迟测量**：记录中断触发到处理开始的时间
4. **伪中断统计**：监控spurious interrupt数量

## 参考资料

- [ARM GIC Architecture Specification](https://developer.arm.com/documentation/ihi0069/latest/)
- [BCM2711 Interrupt Controller](https://datasheets.raspberrypi.com/bcm2711/bcm2711-peripherals.pdf)
- [ARMv8 Exception Handling](https://developer.arm.com/documentation/ddi0487/latest/)
