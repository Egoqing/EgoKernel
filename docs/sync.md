# 同步原语设计文档

## 概述

同步原语模块提供内核中必要的并发控制机制，包括自旋锁、互斥锁、信号量等。这些机制用于保护共享数据，防止竞态条件。

## 架构概览

```
同步原语架构：
┌─────────────────────────────────────────────────────┐
│              同步原语 API                           │
│  (spin_lock, mutex, semaphore, wait_queue)         │
└─────────────────────┬───────────────────────────────┘
                      │
         ┌────────────┼────────────┬────────────┐
         │            │            │            │
         ▼            ▼            ▼            ▼
    ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐
    │Spinlock│  │ Mutex  │  │ Semaphore │ │Wait Q  │
    │spinlock│  │ mutex  │  │semaphore│ │wait.c │
    └────────┘  └────────┘  └────────┘  └────────┘
                      │
                      ▼
              ┌──────────────┐
              │  ARM64 原子操作  │
              │  (LDXR/STXR)  │
              └──────────────┘
```

## ARM64 原子操作

### 原子加载/存储指令

ARM64提供独占加载和存储指令用于实现原子操作：

```c
// 独占加载
// LDXR Rt, [Rn]  - 加载寄存器到Rt，设置独占监视器
static inline uint32_t atomic_ldxr(volatile uint32_t *ptr) {
    uint32_t value;
    asm volatile("ldxr %w0, [%1]" : "=r"(value) : "r"(ptr));
    return value;
}

// 独占存储
// STXR Ws, Rt, [Rn] - 存储Rt到内存，成功则Ws=0
static inline uint32_t atomic_stxr(volatile uint32_t *ptr, uint32_t value) {
    uint32_t result;
    asm volatile("stxr %w0, %w1, [%2]"
                 : "=r"(result)
                 : "r"(value), "r"(ptr)
                 : "memory");
    return result;
}

// 独占加载和存储（带获取/释放语义）
#define atomic_acquire(ptr) atomic_ldxr(ptr)
#define atomic_release(ptr, val) atomic_stxr(ptr, val)
```

### 原子操作宏

```c
// include/atomic.h

// 原子读取
#define atomic_read(v)      ((v)->counter)

// 原子设置
#define atomic_set(v, i)    ((v)->counter = (i))

// 原子加
static inline void atomic_add(atomic_t *v, int i) {
    int result;
    uint32_t tmp;

    do {
        tmp = atomic_ldxr(&v->counter);
        result = tmp + i;
    } while (atomic_stxr(&v->counter, result));
}

// 原子减
static inline void atomic_sub(atomic_t *v, int i) {
    int result;
    uint32_t tmp;

    do {
        tmp = atomic_ldxr(&v->counter);
        result = tmp - i;
    } while (atomic_stxr(&v->counter, result));
}

// 原子加并返回原值
static inline int atomic_add_return(atomic_t *v, int i) {
    int result;
    uint32_t tmp;

    do {
        tmp = atomic_ldxr(&v->counter);
        result = tmp + i;
    } while (atomic_stxr(&v->counter, result));

    return result;
}

// 原子减并返回原值
static inline int atomic_sub_return(atomic_t *v, int i) {
    int result;
    uint32_t tmp;

    do {
        tmp = atomic_ldxr(&v->counter);
        result = tmp - i;
    } while (atomic_stxr(&v->counter, result));

    return result;
}

// 原子加1
static inline void atomic_inc(atomic_t *v) {
    atomic_add(v, 1);
}

// 原子减1
static inline void atomic_dec(atomic_t *v) {
    atomic_sub(v, 1);
}

// 原子比较并交换
static inline int atomic_cmpxchg(atomic_t *v, int old, int new) {
    int result;
    uint32_t tmp;

    do {
        tmp = atomic_ldxr(&v->counter);
        if (tmp != old) {
            return tmp;
        }
    } while (atomic_stxr(&v->counter, new));

    return old;
}

// 原子位操作
static inline void set_bit(int nr, volatile unsigned long *addr) {
    unsigned long mask = 1UL << (nr & 31);
    unsigned long *ptr = addr + (nr >> 5);
    unsigned long old, new;

    do {
        old = atomic_ldxr(ptr);
        new = old | mask;
    } while (atomic_stxr(ptr, new));
}

static inline void clear_bit(int nr, volatile unsigned long *addr) {
    unsigned long mask = ~(1UL << (nr & 31));
    unsigned long *ptr = addr + (nr >> 5);
    unsigned long old, new;

    do {
        old = atomic_ldxr(ptr);
        new = old & mask;
    } while (atomic_stxr(ptr, new));
}
```

## 自旋锁 (Spinlock)

### 设计原理

自旋锁是一种忙等待锁，当一个进程试图获取已持有的自旋锁时，它会循环等待（自旋）直到锁可用。

```
自旋锁工作原理：

进程A                     进程B                     进程C
  │                         │                         │
  ▼                         ▼                         ▼
spin_lock(&lock)          spin_lock(&lock)          spin_lock(&lock)
  │                         │                         │
  ▼                         ▼                         ▼
获取锁成功                 检测锁已持有               检测锁已持有
  │                         │                         │
  ▼                         ▼                         ▼
临界区代码               自旋等待                   自旋等待
  │                     (while locked)             (while locked)
  ▼                         │                         │
spin_unlock(&lock)         │                         │
  │                         ▼                         ▼
  ▼                       获取锁成功                 检测锁已持有
释放锁                       │                   (while locked)
                            ▼
                         临界区代码
                            │
                            ▼
                        spin_unlock(&lock)
```

### 数据结构

```c
typedef struct spinlock {
    volatile int locked;    // 锁状态：0=未持有，1=持有
} spinlock_t;

// 初始化
#define SPIN_LOCK_INIT()     {0}

#define DEFINE_SPINLOCK(x)   spinlock_t x = SPIN_LOCK_INIT()

static inline void spin_lock_init(spinlock_t *lock) {
    lock->locked = 0;
}
```

### 实现

```c
// include/sync.h

// 获取自旋锁
static inline void spin_lock(spinlock_t *lock) {
    // 禁用中断（防止中断死锁）
    uint64_t flags;
    local_irq_save(flags);

    // 尝试获取锁
    while (1) {
        int expected = 0;
        // 原子比较并交换：如果lock->locked==0则设为1
        if (__atomic_compare_exchange_n(&lock->locked, &expected, 1,
                                         0, __ATOMIC_ACQUIRE,
                                         __ATOMIC_RELAXED)) {
            break;
        }
        // 获取失败，自旋
        asm volatile("wfi");  // Wait For Interrupt（节能）
    }
}

// 尝试获取自旋锁（不阻塞）
static inline int spin_trylock(spinlock_t *lock) {
    uint64_t flags;
    local_irq_save(flags);

    int expected = 0;
    if (__atomic_compare_exchange_n(&lock->locked, &expected, 1,
                                     0, __ATOMIC_ACQUIRE,
                                     __ATOMIC_RELAXED)) {
        return 1;  // 成功
    }

    local_irq_restore(flags);
    return 0;  // 失败
}

// 释放自旋锁
static inline void spin_unlock(spinlock_t *lock) {
    // 释放锁
    __atomic_store_n(&lock->locked, 0, __ATOMIC_RELEASE);

    // 恢复中断
    uint64_t flags;
    local_irq_restore(flags);
}
```

### 嵌套自旋锁

```c
// 可递归的自旋锁
typedef struct {
    spinlock_t lock;
    int count;
    task_t *owner;
} recursive_spinlock_t;

static inline void rec_spin_lock_init(recursive_spinlock_t *rlock) {
    spin_lock_init(&rlock->lock);
    rlock->count = 0;
    rlock->owner = NULL;
}

static inline void rec_spin_lock(recursive_spinlock_t *rlock) {
    task_t *current = get_current_task();

    if (rlock->owner == current) {
        // 已经持有，增加计数
        rlock->count++;
    } else {
        // 需要获取锁
        spin_lock(&rlock->lock);
        rlock->owner = current;
        rlock->count = 1;
    }
}

static inline void rec_spin_unlock(recursive_spinlock_t *rlock) {
    if (--rlock->count == 0) {
        // 计数为0，释放锁
        rlock->owner = NULL;
        spin_unlock(&rlock->lock);
    }
}
```

## 互斥锁 (Mutex)

### 设计原理

互斥锁与自旋锁不同，当获取锁失败时会让出CPU，不会自旋等待。适用于可能长时间持有锁的场景。

### 数据结构

```c
typedef struct mutex {
    spinlock_t wait_lock;   // 保护wait_list的自旋锁
    task_t *owner;           // 当前持有者
    struct list_head wait_list;  // 等待队列
} mutex_t;

// 初始化
#define MUTEX_INIT()    { \
    .wait_lock = SPIN_LOCK_INIT(), \
    .owner = NULL, \
    .wait_list = LIST_HEAD_INIT(wait_list) \
}

#define DEFINE_MUTEX(x)  mutex_t x = MUTEX_INIT()

static inline void mutex_init(mutex_t *mutex) {
    spin_lock_init(&mutex->wait_lock);
    mutex->owner = NULL;
    INIT_LIST_HEAD(&mutex->wait_list);
}
```

### 实现

```c
// 获取互斥锁
void mutex_lock(mutex_t *mutex) {
    task_t *current = get_current_task();

    // 获取保护锁
    spin_lock(&mutex->wait_lock);

    // 尝试直接获取
    if (mutex->owner == NULL) {
        mutex->owner = current;
        spin_unlock(&mutex->wait_lock);
        return;
    }

    // 锁被持有，加入等待队列
    list_add_tail(&current->wait_list, &mutex->wait_list);

    // 设置进程状态为阻塞
    current->state = TASK_BLOCKED;

    // 释放保护锁
    spin_unlock(&mutex->wait_lock);

    // 让出CPU
    schedule();

    // 被唤醒后重新尝试获取
    mutex_lock(mutex);
}

// 尝试获取互斥锁（不阻塞）
int mutex_trylock(mutex_t *mutex) {
    task_t *current = get_current_task();

    spin_lock(&mutex->wait_lock);

    if (mutex->owner == NULL) {
        mutex->owner = current;
        spin_unlock(&mutex->wait_lock);
        return 1;
    }

    spin_unlock(&mutex->wait_lock);
    return 0;
}

// 释放互斥锁
void mutex_unlock(mutex_t *mutex) {
    task_t *current = get_current_task();

    spin_lock(&mutex->wait_lock);

    // 检查是否是锁的持有者
    if (mutex->owner != current) {
        spin_unlock(&mutex->wait_lock);
        return;
    }

    // 释放锁
    mutex->owner = NULL;

    // 唤醒等待队列中的第一个进程
    if (!list_empty(&mutex->wait_list)) {
        task_t *waiter = list_first_entry(&mutex->wait_list,
                                          task_t, wait_list);
        list_del(&waiter->wait_list);
        waiter->state = TASK_READY;
        enqueue_task(waiter);
    }

    spin_unlock(&mutex->wait_lock);
}
```

## 信号量 (Semaphore)

### 设计原理

信号量是一种更通用的同步机制，可以管理多个资源。Dijkstra提出的信号量包含一个整数值和两个操作：P（等待/减少）和V（信号/增加）。

### 数据结构

```c
typedef struct semaphore {
    spinlock_t lock;
    int count;
    struct list_head wait_list;
} sem_t;

// 初始化
#define SEM_INIT(value)  { \
    .lock = SPIN_LOCK_INIT(), \
    .count = value, \
    .wait_list = LIST_HEAD_INIT(wait_list) \
}

static inline void sem_init(sem_t *sem, int value) {
    spin_lock_init(&sem->lock);
    sem->count = value;
    INIT_LIST_HEAD(&sem->wait_list);
}
```

### 实现

```c
// P操作 - 获取资源（如果count>0则减少，否则等待）
void down(sem_t *sem) {
    task_t *current = get_current_task();

    spin_lock(&sem->lock);

    if (sem->count > 0) {
        // 有可用资源
        sem->count--;
        spin_unlock(&sem->lock);
        return;
    }

    // 无可用资源，等待
    list_add_tail(&current->wait_list, &sem->wait_list);
    current->state = TASK_BLOCKED;
    spin_unlock(&sem->lock);
    schedule();
}

// 尝试P操作（不阻塞）
int down_trylock(sem_t *sem) {
    spin_lock(&sem->lock);

    if (sem->count > 0) {
        sem->count--;
        spin_unlock(&sem->lock);
        return 1;  // 成功
    }

    spin_unlock(&sem->lock);
    return 0;  // 失败
}

// V操作 - 释放资源（增加count，唤醒等待进程）
void up(sem_t *sem) {
    spin_lock(&sem->lock);

    if (list_empty(&sem->wait_list)) {
        // 没有等待进程，增加计数
        sem->count++;
    } else {
        // 唤醒一个等待进程
        task_t *waiter = list_first_entry(&sem->wait_list,
                                          task_t, wait_list);
        list_del(&waiter->wait_list);
        waiter->state = TASK_READY;
        enqueue_task(waiter);
    }

    spin_unlock(&sem->lock);
}
```

## 等待队列 (Wait Queue)

### 数据结构

```c
typedef struct wait_queue {
    struct list_head list;
    spinlock_t lock;
} wait_queue_t;

static inline void init_waitqueue(wait_queue_t *wq) {
    INIT_LIST_HEAD(&wq->list);
    spin_lock_init(&wq->lock);
}
```

### 实现

```c
// 添加到等待队列
static inline void add_wait_queue(wait_queue_t *wq, task_t *task) {
    spin_lock(&wq->lock);
    list_add_tail(&task->wait_list, &wq->list);
    spin_unlock(&wq->lock);
}

// 从等待队列移除
static inline void remove_wait_queue(wait_queue_t *wq, task_t *task) {
    spin_lock(&wq->lock);
    list_del(&task->wait_list);
    spin_unlock(&wq->lock);
}

// 睡眠直到条件满足
#define wait_event(wq, condition)           \
do {                                        \
    while (!(condition)) {                  \
        add_wait_queue(&(wq), current_task);\
        current_task->state = TASK_BLOCKED;  \
        schedule();                         \
    }                                       \
    remove_wait_queue(&(wq), current_task); \
} while (0)

// 唤醒等待队列
static inline void wake_up(wait_queue_t *wq) {
    task_t *task, *tmp;

    spin_lock(&wq->lock);
    list_for_each_entry_safe(task, tmp, &wq->list, wait_list) {
        list_del(&task->wait_list);
        task->state = TASK_READY;
        enqueue_task(task);
    }
    spin_unlock(&wq->lock);
}

// 唤醒一个进程
static inline void wake_up_one(wait_queue_t *wq) {
    task_t *task;

    if (list_empty(&wq->list)) {
        return;
    }

    spin_lock(&wq->lock);
    task = list_first_entry(&wq->list, task_t, wait_list);
    list_del(&task->wait_list);
    task->state = TASK_READY;
    enqueue_task(task);
    spin_unlock(&wq->lock);
}
```

## 读写锁 (Read-Write Lock)

### 数据结构

```c
typedef struct rwlock {
    spinlock_t lock;
    int readers;
    int writer;
    task_t *owner;
    struct list_head read_waiters;
    struct list_head write_waiters;
} rwlock_t;

static inline void rwlock_init(rwlock_t *rw) {
    spin_lock_init(&rw->lock);
    rw->readers = 0;
    rw->writer = 0;
    rw->owner = NULL;
    INIT_LIST_HEAD(&rw->read_waiters);
    INIT_LIST_HEAD(&rw->write_waiters);
}
```

### 实现

```c
// 获取读锁
void read_lock(rwlock_t *rw) {
    task_t *current = get_current_task();

    spin_lock(&rw->lock);

    // 如果有写锁，等待
    while (rw->writer || rw->owner == current) {
        list_add_tail(&current->wait_list, &rw->read_waiters);
        current->state = TASK_BLOCKED;
        spin_unlock(&rw->lock);
        schedule();
        spin_lock(&rw->lock);
    }

    rw->readers++;
    spin_unlock(&rw->lock);
}

// 释放读锁
void read_unlock(rwlock_t *rw) {
    spin_lock(&rw->lock);

    rw->readers--;

    // 唤醒等待的写进程
    if (rw->readers == 0 && !list_empty(&rw->write_waiters)) {
        task_t *writer = list_first_entry(&rw->write_waiters,
                                          task_t, wait_list);
        list_del(&writer->wait_list);
        writer->state = TASK_READY;
        enqueue_task(writer);
    }

    spin_unlock(&rw->lock);
}

// 获取写锁
void write_lock(rwlock_t *rw) {
    task_t *current = get_current_task();

    spin_lock(&rw->lock);

    // 如果有读者或写锁，等待
    while (rw->readers > 0 || rw->writer ||
           (rw->owner && rw->owner != current)) {
        list_add_tail(&current->wait_list, &rw->write_waiters);
        current->state = TASK_BLOCKED;
        spin_unlock(&rw->lock);
        schedule();
        spin_lock(&rw->lock);
    }

    rw->writer = 1;
    rw->owner = current;
    spin_unlock(&rw->lock);
}

// 释放写锁
void write_unlock(rwlock_t *rw) {
    spin_lock(&rw->lock);

    rw->writer = 0;
    rw->owner = NULL;

    // 优先唤醒等待的写进程
    if (!list_empty(&rw->write_waiters)) {
        task_t *writer = list_first_entry(&rw->write_waiters,
                                          task_t, wait_list);
        list_del(&writer->wait_list);
        writer->state = TASK_READY;
        enqueue_task(writer);
    } else {
        // 唤醒所有等待的读进程
        task_t *reader, *tmp;
        list_for_each_entry_safe(reader, tmp, &rw->read_waiters, wait_list) {
            list_del(&reader->wait_list);
            reader->state = TASK_READY;
            enqueue_task(reader);
        }
    }

    spin_unlock(&rw->lock);
}
```

## 接口设计

```c
// include/sync.h
#include <types.h>
#include <list.h>
#include <task.h>

// 原子类型
typedef struct {
    volatile int counter;
} atomic_t;

// 原子操作
void atomic_set(atomic_t *v, int i);
int atomic_read(atomic_t *v);
void atomic_add(atomic_t *v, int i);
void atomic_sub(atomic_t *v, int i);
int atomic_add_return(atomic_t *v, int i);
int atomic_sub_return(atomic_t *v, int i);
void atomic_inc(atomic_t *v);
void atomic_dec(atomic_t *v);
int atomic_cmpxchg(atomic_t *v, int old, int new);

// 自旋锁
typedef struct spinlock {
    volatile int locked;
} spinlock_t;

void spin_lock_init(spinlock_t *lock);
void spin_lock(spinlock_t *lock);
void spin_unlock(spinlock_t *lock);
int spin_trylock(spinlock_t *lock);

// 互斥锁
typedef struct mutex {
    spinlock_t wait_lock;
    task_t *owner;
    struct list_head wait_list;
} mutex_t;

void mutex_init(mutex_t *mutex);
void mutex_lock(mutex_t *mutex);
void mutex_unlock(mutex_t *mutex);
int mutex_trylock(mutex_t *mutex);

// 信号量
typedef struct semaphore {
    spinlock_t lock;
    int count;
    struct list_head wait_list;
} sem_t;

void sem_init(sem_t *sem, int value);
void down(sem_t *sem);
int down_trylock(sem_t *sem);
void up(sem_t *sem);

// 等待队列
typedef struct wait_queue {
    struct list_head list;
    spinlock_t lock;
} wait_queue_t;

void init_waitqueue(wait_queue_t *wq);
void wake_up(wait_queue_t *wq);
void wake_up_one(wait_queue_t *wq);
#define wait_event(wq, condition) ...
```

## 使用示例

### 自旋锁示例

```c
spinlock_t my_lock = SPIN_LOCK_INIT();

void critical_section(void) {
    spin_lock(&my_lock);

    // 临界区代码
    shared_data++;

    spin_unlock(&my_lock);
}
```

### 互斥锁示例

```c
mutex_t my_mutex = MUTEX_INIT();

void access_resource(void) {
    mutex_lock(&my_mutex);

    // 访问共享资源
    process_data();

    mutex_unlock(&my_mutex);
}
```

### 信号量示例

```c
sem_t resource_sem;

void init(void) {
    // 初始化信号量，允许3个并发访问
    sem_init(&resource_sem, 3);
}

void access_resource(void) {
    down(&resource_sem);

    // 访问资源

    up(&resource_sem);
}
```

### 等待队列示例

```c
wait_queue_t data_available = WAIT_QUEUE_INIT();
int data_ready = 0;

void producer(void) {
    // 生产数据
    produce_data();
    data_ready = 1;

    // 唤醒等待者
    wake_up(&data_available);
}

void consumer(void) {
    // 等待数据可用
    wait_event(data_available, data_ready);

    // 消费数据
    consume_data();
}
```

## 注意事项

### 自旋锁 vs 互斥锁

| 特性 | 自旋锁 | 互斥锁 |
|------|--------|--------|
| 等待方式 | 忙等待（自旋） | 让出CPU |
| 适用场景 | 短时间持锁 | 长时间持锁 |
| 中断上下文 | 可以使用 | 不能使用 |
| 性能 | 短时间快 | 长时间快 |

### 死锁预防

1. **嵌套锁顺序**：总是按相同顺序获取多个锁
2. **避免嵌套自旋锁**：嵌套自旋锁容易死锁
3. **中断上下文**：中断中不能使用可能睡眠的锁
4. **锁的持有时间**：尽量缩短临界区

### 调试技巧

1. **锁统计**：记录锁的获取/释放次数
2. **死锁检测**：超时检测锁持有时间
3. **锁的层次**：为锁分配层次号，检测非法获取顺序
4. **锁的调试**：添加调试信息打印

## 参考资料

- [Linux Kernel Locking](https://www.kernel.org/doc/Documentation/kernel-hacking/locking.rst)
- [ARMv8 Memory Ordering](https://developer.arm.com/documentation/dap0002/latest/)
- [Synchronization Primitives](https://en.wikipedia.org/wiki/Synchronization_(computer_science))
