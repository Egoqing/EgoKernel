# 进程管理模块设计文档

## 概述

进程管理模块负责管理内核中的进程/任务，包括进程创建、调度、切换和终止。本模块采用多进程模型，支持时间片轮转调度，并提供系统调用接口。

## 架构概览

```
进程管理架构：
┌─────────────────────────────────────────────────────┐
│              系统调用接口 (SVC)                     │
│   (fork, exec, exit, wait, getpid, ...)            │
└─────────────────────┬───────────────────────────────┘
                      │
                      ▼
              ┌────────────────┐
              │   进程管理器    │
              │  (process.c)   │
              └───────┬────────┘
                      │
         ┌────────────┼────────────┐
         │            │            │
         ▼            ▼            ▼
    ┌────────┐  ┌────────┐  ┌────────┐
    │ 进程   │  │ 调度器  │  │ 上下文  │
    │ PCB    │  │sched.c │  │switch.S │
    └────────┘  └────────┘  └────────┘
```

## 进程控制块 (PCB)

### 数据结构

```c
// 进程状态
typedef enum {
    TASK_RUNNING,    // 运行中
    TASK_READY,      // 就绪
    TASK_BLOCKED,     // 阻塞
    TASK_ZOMBIE,     // 僵尸
    TASK_STOPPED     // 停止
} task_state_t;

// 进程标识
#define MAX_TASKS    64
#define PID_KERNEL   0    // 内核进程
#define PID_INIT     1    // init进程

// 进程上下文（通用寄存器）
typedef struct context {
    uint64_t x19;      // 被调用者保存的寄存器
    uint64_t x20;
    uint64_t x21;
    uint64_t x22;
    uint64_t x23;
    uint64_t x24;
    uint64_t x25;
    uint64_t x26;
    uint64_t x27;
    uint64_t x28;
    uint64_t fp;        // x29
    uint64_t sp;        // 栈指针
    uint64_t pc;        // 程序计数器
} context_t;

// 进程控制块
typedef struct task {
    uint64_t pid;               // 进程ID
    task_state_t state;         // 进程状态
    uint64_t priority;          // 优先级
    uint64_t time_slice;        // 时间片
    uint64_t counter;           // 剩余时间片

    context_t context;          // 进程上下文
    uint64_t kernel_sp;         // 内核栈指针

    // 内存信息
    uint64_t user_stack;        // 用户栈地址
    uint64_t user_stack_size;   // 用户栈大小
    page_t *page_table;         // 页表

    // 父子关系
    struct task *parent;        // 父进程
    struct task *children;      // 子进程链表
    struct task *next_sibling;  // 下一个兄弟

    // 调度相关
    struct list_head run_list;   // 运行队列

    // 等待相关
    uint64_t exit_code;         // 退出码
    struct list_head wait_list; // 等待队列

    // 统计信息
    uint64_t cpu_time;          // CPU时间
    uint64_t start_time;        // 开始时间

    char name[32];              // 进程名称
} task_t;
```

### 进程状态转换

```
进程状态转换图：

┌─────────┐
│ CREATED │──▶ fork()
└────┬────┘
     │
     ▼
┌─────────┐  fork()  ┌─────────┐
│ RUNNING │◀────────│  READY  │◀─────┐
└────┬────┘          └────┬────┘      │
     │ time_slice_up     │            │
     │                   │ schedule() │
     ▼                   │            │
┌─────────┐              │            │
│ BLOCKED │──────────────┘            │
└────┬────┘  wake_up()                │
     │ exit()                       │
     ▼                               │
┌─────────┐                          │
│ ZOMBIE  │                          │
└─────────┘                          │
     │ wait()                        │
     └───────────────────────────────┘
```

## 进程调度器

### 调度策略

采用**时间片轮转 (Round Robin)** 调度：

| 参数 | 值 | 说明 |
|------|-----|------|
| 时间片 | 10ms | 每个进程的运行时间 |
| 优先级 | 1-10 | 高优先级先调度（未来扩展） |
| 优先级提升 | - | 基于运行时间动态调整（未来扩展） |

### 调度队列

```c
// 运行队列
struct list_head run_queue;

// 当前运行进程
task_t *current_task;

// 下一个进程ID
uint64_t next_pid;
```

### 调度器接口

```c
// 初始化调度器
void scheduler_init(void);

// 调度函数（选择下一个进程运行）
void schedule(void);

// 主动让出CPU
void yield(void);

// 睡眠指定时间
void sleep_ms(uint64_t ms);

// 唤醒进程
void wake_up(task_t *task);

// 添加进程到运行队列
void enqueue_task(task_t *task);

// 从运行队列移除进程
void dequeue_task(task_t *task);
```

### 调度流程

```c
void schedule(void) {
    task_t *prev, *next;

    prev = current_task;

    // 如果当前进程还在运行状态，放回队列
    if (prev->state == TASK_RUNNING) {
        prev->state = TASK_READY;
        enqueue_task(prev);
    }

    // 从运行队列选择下一个进程
    next = pick_next_task();
    if (!next) {
        // 没有可运行进程，运行idle进程
        next = idle_task;
    }

    // 切换到新进程
    if (prev != next) {
        next->state = TASK_RUNNING;
        context_switch(prev, next);
    }
}

task_t *pick_next_task(void) {
    task_t *task;

    // 从运行队列头部获取
    if (!list_empty(&run_queue)) {
        task = list_first_entry(&run_queue, task_t, run_list);
        list_del(&task->run_list);
        return task;
    }

    return NULL;
}

// 定时器中断触发的调度
void scheduler_tick(void) {
    current_task->counter--;

    // 时间片用完，触发调度
    if (current_task->counter == 0) {
        current_task->counter = current_task->time_slice;
        need_reschedule = 1;
    }
}
```

## 上下文切换

### ARM64上下文保存

```
上下文切换时的寄存器保存：

调用者保存 (Caller-saved):
- x0-x18: 由调用者负责保存

被调用者保存 (Callee-saved):
- x19-x28: 由被调用者（内核）负责保存
- x29 (fp), sp, pc: 由内核负责保存
```

### 汇编实现 (switch.S)

```assembly
.global context_switch
context_switch:
    /* prev在x0, next在x1 */

    /* 保存prev上下文 */
    stp     x19, x20, [x0, #0]
    stp     x21, x22, [x0, #16]
    stp     x23, x24, [x0, #32]
    stp     x25, x26, [x0, #48]
    stp     x27, x28, [x0, #64]
    stp     x29, x30, [x0, #80]     // fp, lr
    mov     x2, sp
    str     x2, [x0, #96]          // sp
    mov     x2, lr
    str     x2, [x0, #104]         // pc (从lr获取)

    /* 恢复next上下文 */
    ldp     x19, x20, [x1, #0]
    ldp     x21, x22, [x1, #16]
    ldp     x23, x24, [x1, #32]
    ldp     x25, x26, [x1, #48]
    ldp     x27, x28, [x1, #64]
    ldp     x29, x30, [x1, #80]
    ldr     x2, [x1, #96]
    mov     sp, x2
    ldr     x2, [x1, #104]
    mov     lr, x2

    /* 更新current_task */
    ldr     x2, =current_task
    str     x1, [x2]

    /* 返回 */
    ret
```

### 系统调用上下文切换

系统调用时需要保存用户空间上下文：

```assembly
.global syscall_entry
syscall_entry:
    /* 保存用户上下文 */
    sub     sp, sp, #272
    stp     x0, x1, [sp, #0]
    stp     x2, x3, [sp, #16]
    /* ... 保存所有寄存器 ... */

    /* 调用C处理函数 */
    bl      handle_syscall

    /* 恢复用户上下文 */
    ldp     x0, x1, [sp, #0]
    /* ... 恢复所有寄存器 ... */
    add     sp, sp, #272

    eret
```

## 进程创建

### fork系统调用

```c
task_t *fork(void) {
    task_t *child, *parent;

    parent = current_task;

    // 分配新进程结构
    child = kmalloc(sizeof(task_t));
    if (!child) {
        return NULL;
    }

    // 复制父进程信息
    *child = *parent;

    // 分配新PID
    child->pid = next_pid++;
    child->parent = parent;

    // 分配新内核栈
    child->kernel_sp = (uint64_t)kmalloc(KERNEL_STACK_SIZE);
    if (!child->kernel_sp) {
        kfree(child);
        return NULL;
    }
    child->kernel_sp += KERNEL_STACK_SIZE;

    // 复制页表（简化版：共享页表）
    child->page_table = parent->page_table;

    // 设置子进程返回值为0
    child->context.x0 = 0;

    // 设置子进程状态为就绪
    child->state = TASK_READY;

    // 加入父进程的子进程链表
    child->next_sibling = parent->children;
    parent->children = child;

    // 添加到运行队列
    enqueue_task(child);

    // 父进程返回子进程PID
    return child;
}
```

## 进程终止

### exit系统调用

```c
void exit(int exit_code) {
    task_t *task;

    task = current_task;

    // 设置退出码
    task->exit_code = exit_code;

    // 设置状态为僵尸
    task->state = TASK_ZOMBIE;

    // 唤醒父进程
    if (task->parent->state == TASK_BLOCKED) {
        wake_up(task->parent);
    }

    // 释放资源
    // TODO: 释放页表、用户栈等

    // 触发调度
    schedule();
}

// wait系统调用
int wait(int *status) {
    task_t *child;

    while (1) {
        // 查找僵尸子进程
        child = find_zombie_child(current_task);
        if (child) {
            // 返回退出状态
            if (status) {
                *status = child->exit_code;
            }

            // 释放子进程结构
            kfree(child);

            return child->pid;
        }

        // 没有僵尸子进程，睡眠等待
        current_task->state = TASK_BLOCKED;
        schedule();
    }
}
```

## 系统调用

### 系统调用号定义

```c
#define SYS_EXIT        1
#define SYS_FORK        2
#define SYS_READ        3
#define SYS_WRITE       4
#define SYS_GETPID      5
#define SYS_SLEEP       6
#define SYS_YIELD       7
#define SYS_WAIT        8
```

### 系统调用处理

```c
uint64_t syscall_handler(uint64_t syscall_num, uint64_t arg0,
                          uint64_t arg1, uint64_t arg2) {
    switch (syscall_num) {
        case SYS_EXIT:
            exit((int)arg0);
            break;

        case SYS_FORK:
            return fork();

        case SYS_READ:
            return sys_read(arg0, (void*)arg1, arg2);

        case SYS_WRITE:
            return sys_write(arg0, (void*)arg1, arg2);

        case SYS_GETPID:
            return current_task->pid;

        case SYS_SLEEP:
            sleep_ms(arg0);
            break;

        case SYS_YIELD:
            yield();
            break;

        case SYS_WAIT:
            return wait((int*)arg0);

        default:
            return -1;
    }

    return 0;
}
```

### SVC指令触发

```assembly
// 用户程序调用系统调用
mov     x8, #SYS_WRITE      // 系统调用号
mov     x0, #1              // 文件描述符
mov     x1, #msg            // 缓冲区地址
mov     x2, #len            // 长度
svc     #0                  // 触发系统调用
```

## 初始化流程

```
进程管理初始化：

kernel_main()
    │
    ▼
process_init()
    ├── 初始化空闲进程列表
    │
    ├── 创建init进程
    │   ├── 分配PCB
    │   ├── 分配内核栈
    │   ├── 设置上下文
    │   └── 设置状态为READY
    │
    └── scheduler_init()
        ├── 初始化运行队列
        └── 设置current_task = init_task

    │
    ▼
enable_irq()
    │
    ▼
定时器中断触发
    │
    ▼
scheduler_tick()
    │
    ▼
schedule() [如果need_reschedule]
    │
    ▼
context_switch()
```

## 接口设计

```c
// include/proc.h
#include <types.h>

// 进程管理接口
void process_init(void);
task_t *fork(void);
void exit(int exit_code);
int wait(int *status);
uint64_t getpid(void);

// 调度器接口
void scheduler_init(void);
void schedule(void);
void yield(void);
void sleep_ms(uint64_t ms);
void wake_up(task_t *task);

// 系统调用接口
uint64_t syscall_handler(uint64_t num, uint64_t arg0,
                         uint64_t arg1, uint64_t arg2);
```

## 调试技巧

1. **进程列表**：打印所有进程的状态
2. **调度跟踪**：记录每次上下文切换
3. **死锁检测**：监控长时间阻塞的进程
4. **性能分析**：统计CPU时间分布

## 参考资料

- [Linux Process Management](https://www.kernel.org/doc/html/latest/scheduler/)
- [ARMv8 Exception Handling](https://developer.arm.com/documentation/ddi0487/latest/)
- [OS Design: Process Management](https://www.os3.nl/Process_management)
