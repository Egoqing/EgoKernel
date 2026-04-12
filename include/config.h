#ifndef _CONFIG_H
#define _CONFIG_H

/* 内存配置 */
#define PAGE_SIZE           4096        /* 4KB 页大小 */
#define PAGE_SHIFT          12          /* 页偏移位数 */

#define KERNEL_STACK_SIZE   16384       /* 16KB 内核栈 */
#define KERNEL_STACK_SHIFT  14

/* CPU配置 */
#define MAX_CPUS            4           /* 树莓派4B是4核 */

/* 内存管理配置 */
#define MAX_ORDER           10          /* 伙伴系统最大order: 2^10 * 4KB = 4MB */
#define MIN_ORDER           0

#define SLAB_MIN_SIZE       8
#define SLAB_MAX_SIZE       8192

/* 进程管理配置 */
#define MAX_PROCESSES       64
#define KERNEL_PID          0

/* 调度配置 */
#define TIME_SLICE          10          /* 时间片 (毫秒) */
#define HZ                  100          /* 时钟频率 (Hz) */

/* UART配置 */
#define UART_BAUD_RATE      115200
#define UART_CLOCK_RATE     48000000    /* PL011时钟频率 */

/* GIC配置 */
#define GIC_NR_IRQS         512

/* 物理内存范围 (树莓派4B 1GB) */
#define PHYS_MEMORY_START   0x00000000UL
#define PHYS_MEMORY_END     0x40000000UL

/* 内核加载地址 */
#define KERNEL_LOAD_ADDR    0x80000

/* 调试选项 */
#define DEBUG               0           /* 设置为1启用调试输出 */

#endif /* _CONFIG_H */
