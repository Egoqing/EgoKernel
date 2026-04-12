#ifndef _KERNEL_H
#define _KERNEL_H

#include <types.h>

/* 内核通用定义 */
#define KERNEL_VERSION "0.0.1"
#define KERNEL_NAME    "EgoKernel"

/* 内核虚拟地址空间 */
#define KERNEL_BASE    0xFFFF800000000000UL  /* 内核虚拟基地址 */

/* 内核物理地址空间 */
#define KERNEL_PHYS_BASE 0x80000             /* 内核物理基地址 */

/* 常用宏定义 */
#define ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))

#define ROUND_UP(x, n)    (((x) + (n) - 1) & ~((n) - 1))
#define ROUND_DOWN(x, n)  ((x) & ~((n) - 1))

#define MIN(a, b)         ((a) < (b) ? (a) : (b))
#define MAX(a, b)         ((a) > (b) ? (a) : (b))

#define barrier()         __asm__ __volatile__("" ::: "memory")

/* 空操作和等待指令 */
static inline void nop(void) {
    __asm__ __volatile__("nop");
}

static inline void wfi(void) {
    __asm__ __volatile__("wfi");
}

static inline void wfe(void) {
    __asm__ __volatile__("wfe");
}

/* 中断控制 */
static inline void enable_irq(void) {
    __asm__ __volatile__("msr daifclr, #2");
}

static inline void disable_irq(void) {
    __asm__ __volatile__("msr daifset, #2");
}

static inline void enable_fiq(void) {
    __asm__ __volatile__("msr daifclr, #1");
}

static inline void disable_fiq(void) {
    __asm__ __volatile__("msr daifset, #1");
}

static inline void enable_irq_fiq(void) {
    __asm__ __volatile__("msr daifclr, #3");
}

static inline void disable_irq_fiq(void) {
    __asm__ __volatile__("msr daifset, #3");
}

/* 异常级别查询 */
static inline uint64_t get_current_el(void) {
    uint64_t el;
    __asm__ volatile("mrs %0, CurrentEL" : "=r"(el));
    return (el >> 2) & 0x3;
}

/* 读取ID寄存器 */
static inline uint64_t read_midr_el1(void) {
    uint64_t midr;
    __asm__ volatile("mrs %0, midr_el1" : "=r"(midr));
    return midr;
}

/* 读取多处理器ID */
static inline uint64_t read_mpidr_el1(void) {
    uint64_t mpidr;
    __asm__ volatile("mrs %0, mpidr_el1" : "=r"(mpidr));
    return mpidr;
}

/* 系统停止 */
static inline void hlt(void) {
    while (1) {
        wfi();
    }
}

/* 断言宏 (调试用) */
#ifdef DEBUG
#define ASSERT(cond) \
    do { \
        if (!(cond)) { \
            __asm__ volatile("bkpt #0"); \
        } \
    } while (0)
#else
#define ASSERT(cond) ((void)(cond))
#endif

#endif /* _KERNEL_H */
