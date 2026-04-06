# 内存管理模块设计文档

## 概述

内存管理模块负责管理树莓派4B的物理内存和虚拟内存，提供高效的内存分配和映射机制。本模块采用**伙伴系统**作为物理页分配器，**Slab分配器**用于小对象分配，配合**ARM64 4级页表**实现虚拟内存管理。

## 架构概览

```
内存管理架构：
┌─────────────────────────────────────────────────────┐
│                内核内存管理 API                       │
│  (kmalloc/kfree, map_page/unmap_page, etc.)         │
└─────────────────────┬───────────────────────────────┘
                      │
         ┌────────────┼────────────┐
         │            │            │
         ▼            ▼            ▼
    ┌─────────┐ ┌─────────┐ ┌─────────┐
    │ 伙伴系统 │ │ 页表管理 │ │ Slab系统 │
    │ buddy.c │ │ page.c  │ │ slab.c  │
    └────┬────┘ └────┬────┘ └────┬────┘
         │            │            │
         └────────────┼────────────┘
                      │
                      ▼
              ┌───────────────┐
              │  物理内存      │
              │  (1GB - 8GB)   │
              └───────────────┘
```

## 伙伴系统 (Buddy System)

### 算法原理

伙伴系统将内存按2的幂次方（order）大小划分成块：

```
Order关系：
order 0:  1页   = 4KB
order 1:  2页   = 8KB
order 2:  4页   = 16KB
order 3:  8页   = 32KB
order 4:  16页  = 64KB
order 5:  32页  = 128KB
order 6:  64页  = 256KB
order 7:  128页 = 512KB
order 8:  256页 = 1MB
order 9:  512页 = 2MB
order 10: 1024页 = 4MB
order 11: 2048页 = 8MB
```

### 内存块分裂示例

```
初始状态（order 2的块）：
┌────────────────────────────┐
│       Block A (order 2)     │ 4页
└────────────────────────────┘

请求order 0：
┌──────────┬──────────────────┐
│  Block B │   Block A'        │
│ (order0) │   (order1)        │
└──────────┴──┬───────────────┘
              │
         ┌────┴────┐
         │  Block  │
         │  (order0)│
         └─────────┘
```

### 核心数据结构

```c
// 页大小：4KB
#define PAGE_SIZE      4096
#define PAGE_SHIFT     12
#define MAX_ORDER      11  // 最大order

// 页状态
typedef enum {
    PAGE_FREE,      // 空闲
    PAGE_ALLOCATED, // 已分配
    PAGE_RESERVED   // 保留
} page_state_t;

// 物理页描述符
typedef struct page {
    uint64_t index;          // 页索引
    uint64_t order;          // 当前块的order
    page_state_t state;      // 页状态
    uint64_t ref_count;      // 引用计数
    struct list_head list;   // 链表节点
} page_t;

// 伙伴系统管理器
typedef struct buddy_system {
    uint64_t total_pages;    // 总页数
    uint64_t free_pages;     // 空闲页数
    uint64_t reserved_pages; // 保留页数
    page_t *pages;           // 页描述符数组
    struct list_head free_list[MAX_ORDER];
    spinlock_t lock;         // 保护
} buddy_t;
```

### 伙伴查找算法

```
给定一个order为n的块，其伙伴的计算方式：
buddy_index = page_index ^ (1 << n)

示例（order=2，即4页一组）：
┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐
│  0   │  1   │  2   │  3   │  4   │  5   │  6   │  7   │
│  order 2块  │        │  order 2块  │        │
└──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘
         伙伴对1              伙伴对2

- page_index=0 的伙伴是 index=4 (0 ^ 4 = 4)
- page_index=4 的伙伴是 index=0 (4 ^ 4 = 0)
```

### 关键函数

| 函数 | 说明 |
|------|------|
| `buddy_init(phys_base, size)` | 初始化伙伴系统 |
| `buddy_alloc_pages(order)` | 分配2^order页，返回page_t* |
| `buddy_free_pages(page)` | 释放页面 |
| `buddy_alloc_pages_exact(n)` | 分配精确n页 |
| `buddy_get_phys_addr(page)` | 获取物理地址 |
| `buddy_get_page(paddr)` | 根据物理地址获取page_t |
| `buddy_get_stats()` | 获取统计信息 |

### 分配算法流程

```
buddy_alloc_pages(order):
1. 从free_list[order]开始查找
2. 如果有空闲块，直接返回
3. 如果没有空闲块：
   a. 查找更高order的空闲块
   b. 如果找到，分裂该块：
      - 将块分成两个order-1的块
      - 一个返回给调用者
      - 另一个加入free_list[order-1]
   c. 继续分裂直到满足需求
4. 如果找不到足够大的块，返回NULL
```

### 释放算法流程

```
buddy_free_pages(page):
1. 将页面标记为FREE
2. 查找该页面的伙伴：
   - buddy_index = page_index ^ (1 << page->order)
3. 如果伙伴是FREE：
   - 将两个块合并成更大的块
   - 从free_list中移除伙伴
   - 继续尝试合并
4. 如果伙伴不是FREE：
   - 将块加入对应order的free_list
```

## Slab分配器

### 设计目的

伙伴系统适合分配大块内存（页级别），但对于小对象分配效率低。Slab分配器基于伙伴系统，提供高效的小对象分配。

### 架构

```
Slab架构：
┌─────────────────────────────────┐
│      Slab Cache (kmalloc-32)   │
├─────────────────────────────────┤
│  full_slabs      完全满的slab   │
│  partial_slabs   部分空闲slab   │
│  free_slabs      空闲slab       │
└─────────────────────────────────┘

单个Slab结构：
┌─────────────────────────────────┐
│  slab_t                         │
│  ┌─────┬─────┬─────┬─────┬─────┐ │
│  │ obj │ obj │ obj │ obj │ ... │ │ 32字节对象
│  └─────┴─────┴─────┴─────┴─────┘ │
│  ┌─────────────────────────┐    │
│  │   free bitmap           │    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘
```

### 数据结构

```c
// Slab对象
typedef struct slab {
    struct list_head list;     // 链表节点
    slab_cache_t *cache;       // 所属缓存
    void *start;              // 起始地址
    uint64_t inuse;           // 已使用对象数
    unsigned long free_bitmap[]; // 空闲位图
} slab_t;

// Slab缓存
typedef struct slab_cache {
    char name[32];            // 缓存名称
    size_t obj_size;          // 对象大小
    size_t objects_per_slab;  // 每个slab的对象数
    size_t slab_size;        // 每个slab的字节数
    struct list_head full_slabs;    // 满的slab
    struct list_head partial_slabs; // 部分空闲slab
    struct list_head free_slabs;    // 空闲slab
    spinlock_t lock;          // 保护
} slab_cache_t;

// 预定义缓存大小
#define SLAB_SIZES  {32, 64, 128, 256, 512, 1024, 2048}
```

### 关键函数

| 函数 | 说明 |
|------|------|
| `slab_init()` | 初始化Slab系统 |
| `slab_create(name, size)` | 创建新的slab缓存 |
| `slab_destroy(cache)` | 销毁slab缓存 |
| `slab_alloc(cache)` | 从缓存分配对象 |
| `slab_free(cache, obj)` | 释放对象到缓存 |

### kmalloc/kfree实现

```c
void *kmalloc(size_t size) {
    // 找到最合适的slab缓存
    for (int i = 0; i < SLAB_SIZE_COUNT; i++) {
        if (slab_sizes[i] >= size) {
            return slab_alloc(&slab_caches[i]);
        }
    }
    // 大对象直接从伙伴系统分配
    return buddy_alloc_large(size);
}

void kfree(void *ptr) {
    // 查找ptr所属的slab缓存
    slab_cache_t *cache = find_slab_cache(ptr);
    if (cache) {
        slab_free(cache, ptr);
    } else {
        buddy_free_large(ptr);
    }
}
```

## 页表管理

### ARM64 4级页表结构

```
虚拟地址 [47:0] 转换流程：
┌──────────────────────────────────────────────────────────┐
│ 虚拟地址                                                  │
├─────────┬─────────┬─────────┬─────────┬────────────────┤
│ L9[47]  │ L3[39:38]│ L2[29:21]│ L1[20:12]│ Offset[11:0] │
│ 1 bit   │ 9 bits   │ 9 bits   │ 9 bits   │ 12 bits      │
└────┬────┴────┬────┴────┬────┴────┬────┴───────┬───────┘
     │          │          │          │             │
     ▼          ▼          ▼          ▼             ▼
  ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐
  │ TTBR │   │ PGD  │   │ PUD  │   │ PMD  │   │ PTE  │
  │_EL1 │──▶│[L9] │──▶│[L3] │──▶│[L1] │──▶│[L0] │──▶ 物理页
  └──────┘   └──────┘   └──────┘   └──────┘   └──────┘
  (页表基址) (512项)   (512项)   (512项)   (512项)
```

### 页表项格式

```c
// 页表项标志位
#define PTE_VALID      (1UL << 0)   // 有效位
#define PTE_TABLE      (1UL << 1)   // 表项
#define PTE_BLOCK      (1UL << 1)   // 块项
#define PTE_AF         (1UL << 10)  // 访问标志
#define PTE_SH_INNER   (3UL << 8)   // 内部共享
#define PTE_SH_OUTER   (2UL << 8)   // 外部共享
#define PTE_ACCESS     (1UL << 10)  // 可访问
#define PTE_NG         (1UL << 11)  // 非全局
#define PTE_USER       (1UL << 6)   // 用户可访问
#define PTE_XN         (1UL << 54)  // 不可执行

// 内存属性（MAIR_EL1索引）
#define PTE_ATTR_NORMAL_DEVICE_NG  0x0
#define PTE_ATTR_NORMAL_MEMORY     0x1
#define PTE_ATTR_NORMAL_NC         0x2
```

### 关键函数

| 函数 | 说明 |
|------|------|
| `mmu_init()` | 初始化MMU，建立初始页表 |
| `map_page(vaddr, paddr, flags)` | 映射单个页 |
| `unmap_page(vaddr)` | 取消页映射 |
| `map_range(vaddr, paddr, size, flags)` | 映射一段内存 |
| `get_phys_addr(vaddr)` | 获取物理地址 |
| `set_page_flags(vaddr, flags)` | 设置页标志位 |

### 初始页表设置

```
启动时的页表映射：
┌────────────────────────────────────────┐
│ 虚拟地址               │ 物理地址      │
├────────────────────────────────────────┤
│ 0x00000000 - 0x7FFFFFFF │ 0x00000000 │ 恒等映射（2GB） │
├────────────────────────────────────────┤
│ 0xFFFF000000000000 - ... │ 0xFE000000 │ 设备映射      │
└────────────────────────────────────────┘
```

### MMU启用流程

```c
void mmu_enable(void) {
    // 1. 设置页表基址寄存器
    uint64_t pgd_addr = (uint64_t)kernel_pgd;
    asm volatile("msr ttbr1_el1, %0" : : "r"(pgd_addr));

    // 2. 设置内存属性寄存器 (MAIR_EL1)
    uint64_t mair = (0xFF << 0) |   // Normal Memory
                    (0x00 << 8) |   // Device Memory
                    (0x44 << 16);   // Non-Cacheable
    asm volatile("msr mair_el1, %0" : : "r"(mair));

    // 3. 设置转换控制寄存器 (TCR_EL1)
    uint64_t tcr = (16 << 0) |   // T0SZ = 16 (48-bit VA)
                   (0 << 6) |    // EPD0 = 0
                   (16 << 16) |  // T1SZ = 16 (48-bit VA)
                   (0 << 22) |   // EPD1 = 0
                   (1 << 23);    // A1 = 1 (TTBR1用于EL0/EL1)
    asm volatile("msr tcr_el1, %0" : : "r"(tcr));

    // 4. 启用MMU和I/D Cache
    uint64_t sctlr;
    asm volatile("mrs %0, sctlr_el1" : "=r"(sctlr));
    sctlr |= (1 << 0) |  // M = 1 (MMU enable)
             (1 << 2) |  // C = 1 (D-cache enable)
             (1 << 12); // I = 1 (I-cache enable)
    asm volatile("msr sctlr_el1, %0" : : "r"(sctlr));
}
```

## 内存布局（树莓派4B 1GB版本）

```
物理内存布局：
┌────────────────────────────────────────────────────┐
│ 0x00000000 - 0x0007FFFF (512KB)                    │ 保留（Bootloader）│
├────────────────────────────────────────────────────┤
│ 0x00080000 - 0x001FFFFF (2MB)                      │ 内核代码/数据    │
├────────────────────────────────────────────────────┤
│ 0x00200000 - 0x0020FFFF (64KB)                    │ 页描述符数组    │
├────────────────────────────────────────────────────┤
│ 0x00210000 - 0x3FFFFFFF (~1GB)                    │ 可用物理内存    │
└────────────────────────────────────────────────────┘

虚拟内存布局：
┌────────────────────────────────────────────────────┐
│ 0x0000000000000000 - 0x00007FFFFFFFFFFF (512GB)    │ 用户空间 (TTBR0) │
├────────────────────────────────────────────────────┤
│ 0xFFFF000000000000 - 0xFFFFFFFFFFFFFFFF (512GB)    │ 内核空间 (TTBR1) │
│   - 内核代码/数据                                    │
│   - 页表                                            │
│   - 堆                                              │
│   - 设备映射                                        │
│   - 每CPU数据                                       │
└────────────────────────────────────────────────────┘
```

## 初始化流程

```
mm_init():
    ├── buddy_init(0x00210000, 0x3FDF0000)
    │   ├── 初始化free_list数组
    │   ├── 标记保留页面
    │   └── 将可用内存加入伙伴系统
    │
    ├── page_table_init()
    │   ├── 分配PGD
    │   ├── 建立恒等映射
    │   ├── 建立设备映射
    │   └── 设置TTBR1_EL1
    │
    ├── mmu_enable()
    │   ├── 设置MAIR_EL1
    │   ├── 设置TCR_EL1
    │   └── 启用MMU
    │
    └── slab_init()
        ├── 创建常用大小缓存
        └── 初始化链表头
```

## 接口设计

```c
// include/mm.h
#include <types.h>

// 伙伴系统接口
void buddy_init(uint64_t base, uint64_t size);
page_t *buddy_alloc_pages(int order);
void buddy_free_pages(page_t *page);
uint64_t buddy_get_phys_addr(page_t *page);
page_t *buddy_get_page(uint64_t paddr);
void buddy_get_stats(struct buddy_stats *stats);

// Slab分配器接口
void slab_init(void);
void *kmalloc(size_t size);
void kfree(void *ptr);

// 页表接口
void mmu_init(void);
int map_page(uint64_t vaddr, uint64_t paddr, uint64_t flags);
int unmap_page(uint64_t vaddr);
uint64_t get_phys_addr(uint64_t vaddr);
```

## 调试和测试

### 内存分配测试

```c
void test_buddy_system(void) {
    page_t *pages[4];

    // 分配测试
    pages[0] = buddy_alloc_pages(0);
    pages[1] = buddy_alloc_pages(1);
    pages[2] = buddy_alloc_pages(2);
    pages[3] = buddy_alloc_pages(0);

    // 释放测试
    buddy_free_pages(pages[0]);
    buddy_free_pages(pages[1]);
    buddy_free_pages(pages[2]);
    buddy_free_pages(pages[3]);

    // 验证统计信息
    struct buddy_stats stats;
    buddy_get_stats(&stats);
    printf("Free pages: %lu/%lu\n", stats.free, stats.total);
}

void test_slab_allocator(void) {
    void *ptrs[100];

    // 分配测试
    for (int i = 0; i < 100; i++) {
        ptrs[i] = kmalloc(64 + (i % 8) * 32);
    }

    // 释放测试
    for (int i = 0; i < 100; i += 2) {
        kfree(ptrs[i]);
    }
}
```

### 调试技巧

1. **内存泄漏检测**：在分配/释放时记录调用栈
2. **统计信息**：定期打印空闲页数量
3. **边界检查**：在slab中添加红区检测越界
4. **使用后释放检测**：在page_t中增加magic number

## 参考资料

- [ARMv8 Memory Management](https://developer.arm.com/documentation/ddi0487/latest/)
- [Linux Kernel Buddy System](https://www.kernel.org/doc/Documentation/vm/buddy.txt)
- [Slab Allocator Design](https://www.kernel.org/doc/Documentation/vm/slab.txt)
