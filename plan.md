# EgoKernel 开发计划与进展

## 项目目标

为树莓派4B (ARM64架构) 实现一个完整的操作系统内核，深入理解操作系统原理。

## 当前状态

**阶段**: 规划完成，准备开始实现

**进度**: 0%

**最后更新**: 2026-04-06

---

## 整体路线图

```
阶段1: 基础框架 ━━━━━━━━━━━━━━━━━━ [ ] 0%
阶段2: 调试输出 ━━━━━━━━━━━━━━━━━━ [ ] 0%
阶段3: 内存管理 ━━━━━━━━━━━━━━━━━━ [ ] 0%
阶段4: 中断处理 ━━━━━━━━━━━━━━━━━━ [ ] 0%
阶段5: 定时器和调度 ━━━━━━━━━━━━━━ [ ] 0%
阶段6: 系统调用 ━━━━━━━━━━━━━━━━━━ [ ] 0%
阶段7: 其他驱动 ━━━━━━━━━━━━━━━━━━ [ ] 0%
```

---

## 阶段1: 基础框架

### 目标
建立基本的内核框架，实现从boot到C入口的完整流程。

### 任务清单

- [ ] **1.1 创建基础头文件**
  - [ ] `include/types.h` - 基础类型定义
  - [ ] `include/kernel.h` - 内核通用定义
  - [ ] `include/config.h` - 配置选项

- [ ] **1.2 实现启动代码** ⭐ 需要亲自实现
  - [ ] `boot/start.S` - 汇编入口点
    - [ ] 禁用中断 (DAIF)
    - [ ] 设置栈指针
    - [ ] 设置异常向量表
    - [ ] 清零BSS段
    - [ ] 降到EL1
    - [ ] 跳转到C代码
  - [ ] `boot/linker.ld` - 链接脚本

- [ ] **1.3 实现异常向量表** ⭐ 需要亲自实现
  - [ ] `kernel/int/vectors.S` - 16个异常向量
  - [ ] 简单的占位处理函数

- [ ] **1.4 实现内核主函数** ⭐ 需要亲自实现
  - [ ] `kernel/main.c` - kernel_main()

- [ ] **1.5 创建Makefile**
  - [ ] 配置aarch64-none-elf工具链
  - [ ] 编译规则
  - [ ] 链接规则
  - [ ] 生成kernel8.img

### 验收标准
- [ ] 成功编译生成kernel8.img
- [ ] 能够在树莓派上启动（至少不崩溃）

### 参考资料
- `docs/boot.md`
- BCM2711启动序列
- ARMv8异常级别

---

## 阶段2: 调试输出

### 目标
实现UART串口驱动，提供调试输出能力。

### 任务清单

- [ ] **2.1 实现字符串函数**
  - [ ] `kernel/lib/string.c`
    - [ ] memset
    - [ ] memcpy
    - [ ] strlen
    - [ ] strcpy

- [ ] **2.2 实现UART驱动** ⭐ 需要亲自实现
  - [ ] `kernel/drivers/uart/pl011.c`
    - [ ] UART初始化
    - [ ] 字符输出 (uart_putc)
    - [ ] 字符输入 (uart_getc)
    - [ ] 字符串输出 (uart_puts)
  - [ ] `include/drivers/uart.h`

- [ ] **2.3 实现简单printf**
  - [ ] `kernel/lib/print.c`
    - [ ] 基本格式化输出
    - [ ] 支持%d, %x, %s, %c

- [ ] **2.4 在kernel_main中测试**
  - [ ] 初始化UART
  - [ ] 输出启动信息

### 验收标准
- [ ] 通过串口能看到内核启动信息
- [ ] printf能正确输出各种格式

### 参考资料
- `docs/drivers.md` - UART章节
- `docs/lib.md` - 字符串和格式化输出
- PL011数据手册

---

## 阶段3: 内存管理

### 目标
实现完整的内存管理子系统，包括伙伴系统、页表和Slab。

### 任务清单

- [ ] **3.1 实现页表管理** ⭐ 需要亲自实现
  - [ ] `kernel/mm/page.c`
    - [ ] 创建初始页表
    - [ ] map_page函数
    - [ ] unmap_page函数
  - [ ] `include/mm.h`

- [ ] **3.2 实现伙伴系统** ⭐ 需要亲自实现
  - [ ] `kernel/mm/buddy.c`
    - [ ] 数据结构定义
    - [ ] buddy_init
    - [ ] buddy_alloc_pages
    - [ ] buddy_free_pages
    - [ ] 伙伴查找和合并
  - [ ] `kernel/mm/buddy.h`

- [ ] **3.3 实现Slab分配器** ⭐ 需要亲自实现
  - [ ] `kernel/mm/slab.c`
    - [ ] slab_create
    - [ ] slab_alloc
    - [ ] slab_free
  - [ ] kmalloc/kfree

- [ ] **3.4 启用MMU**
  - [ ] `kernel/mm/mmu.c`
    - [ ] 设置MAIR_EL1
    - [ ] 设置TCR_EL1
    - [ ] 启用MMU

### 验收标准
- [ ] 伙伴系统分配释放正常
- [ ] Slab分配器工作正常
- [ ] MMU成功启用
- [ ] 页表映射正确

### 参考资料
- `docs/memory.md`
- ARMv8内存管理
- Linux伙伴系统实现

---

## 阶段4: 中断处理

### 目标
实现完整的中断处理机制，支持外设中断。

### 任务清单

- [ ] **4.1 实现GIC-400驱动** ⭐ 需要亲自实现
  - [ ] `kernel/int/gic.c`
    - [ ] GIC初始化
    - [ ] 中断使能/禁用
    - [ ] 中断优先级设置

- [ ] **4.2 实现IRQ分发器** ⭐ 需要亲自实现
  - [ ] `kernel/int/irq.c`
    - [ ] 中断注册 (request_irq)
    - [ ] 中断注销 (free_irq)
    - [ ] IRQ处理流程

- [ ] **4.3 实现上下文保存/恢复** ⭐ 需要亲自实现
  - [ ] `kernel/int/entry.S`
    - [ ] 中断入口
    - [ ] 上下文保存
    - [ ] 上下文恢复
    - [ ] 中断返回

- [ ] **4.4 实现异常处理**
  - [ ] `kernel/int/handlers.c`
    - [ ] 同步异常处理
    - [ ] IRQ处理
    - [ ] FIQ处理

### 验收标准
- [ ] GIC初始化成功
- [ ] 能够注册和触发中断
- [ ] 上下文切换正确

### 参考资料
- `docs/interrupt.md`
- GIC-400架构手册
- ARMv8异常处理

---

## 阶段5: 定时器和调度

### 目标
实现定时器驱动和进程调度器。

### 任务清单

- [ ] **5.1 实现定时器驱动** ⭐ 需要亲自实现
  - [ ] `kernel/drivers/timer.c`
    - [ ] ARM Generic Timer初始化
    - [ ] 周期性中断
    - [ ] 延迟函数

- [ ] **5.2 实现进程控制块**
  - [ ] `kernel/proc/process.c`
    - [ ] task_t结构
    - [ ] fork系统调用框架

- [ ] **5.3 实现上下文切换** ⭐ 需要亲自实现
  - [ ] `kernel/proc/switch.S`
    - [ ] 保存上下文
    - [ ] 恢复上下文
    - [ ] context_switch函数

- [ ] **5.4 实现调度器** ⭐ 需要亲自实现
  - [ ] `kernel/proc/sched.c`
    - [ ] 时间片轮转
    - [ ] schedule函数
    - [ ] scheduler_tick

### 验收标准
- [ ] 定时器周期性触发
- [ ] 进程能够正确切换
- [ ] 时间片轮转工作正常

### 参考资料
- `docs/process.md`
- `docs/drivers.md` - 定时器章节

---

## 阶段6: 系统调用

### 目标
实现系统调用机制和基础系统调用。

### 任务清单

- [ ] **6.1 实现系统调用入口** ⭐ 需要亲自实现
  - [ ] SVC异常处理
  - [ ] 系统调用参数传递
  - [ ] syscall_handler框架

- [ ] **6.2 实现基础系统调用**
  - [ ] SYS_WRITE - 写入
  - [ ] SYS_READ - 读取
  - [ ] SYS_EXIT - 退出
  - [ ] SYS_GETPID - 获取PID
  - [ ] SYS_FORK - 创建进程

### 验收标准
- [ ] 系统调用能正常工作
- [ ] 用户程序能调用系统调用

### 参考资料
- `docs/process.md`

---

## 阶段7: 其他驱动

### 目标
完善驱动支持。

### 任务清单
- [ ] GPIO驱动
- [ ] Mailbox驱动（帧缓冲区）
- [ ] SD卡驱动
- [ ] 键盘/鼠标输入

---

## 当前工作

### 正在进行的任务
**阶段1.1**: 创建基础头文件

### 下一步计划
1. 完成 `include/types.h` - 定义uint8_t, uint16_t, uint32_t, uint64_t等基础类型
2. 完成 `include/kernel.h` - 定义NULL, 布尔类型等
3. 完成 `include/config.h` - 定义页大小、内核栈大小等配置
4. 开始实现 `boot/start.S`

### 阻碍/问题
无

---

## 学习笔记

### 已掌握的知识点
- ARM64异常级别 (EL0-EL3)
- 树莓派4B启动流程
- 内核内存布局

### 正在学习的知识点
- ARM64汇编指令
- 链接脚本语法

### 计划学习的知识点
- 伙伴系统算法
- GIC-400中断控制器
- ARMv8内存管理

---

## 参考资料

### 内部文档
- `docs/boot.md`
- `docs/memory.md`
- `docs/interrupt.md`
- `docs/process.md`
- `docs/drivers.md`
- `docs/lib.md`
- `docs/sync.md`

### 外部资源
- [ARM Architecture Reference Manual ARMv8](https://developer.arm.com/documentation/ddi0487/latest/)
- [BCM2711 Peripherals Datasheet](https://datasheets.raspberrypi.com/bcm2711/bcm2711-peripherals.pdf)
- [GIC-400 Architecture](https://developer.arm.com/documentation/ihi0069/latest/)
- [Linux Kernel Source](https://github.com/torvalds/linux)

### 参考项目
- [xv6-riscv](https://github.com/mit-pdos/xv6-riscv) - MIT的简单OS
- [rpi-os](https://github.com/siara-cc/raspberry-pi-os) - RPi OS教程

---

## 更新日志

### 2026-04-06
- 创建项目结构
- 完成所有设计文档
- 创建CLAUDE.md协作规则
- 创建plan.md进展追踪
