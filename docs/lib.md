# 内核库函数设计文档

## 概述

内核库函数模块提供内核常用工具函数，包括字符串操作、格式化输出、链表操作等。由于是裸金属内核，没有标准C库支持，需要自行实现这些基础函数。

## 架构概览

```
内核库架构：
┌─────────────────────────────────────────────────────┐
│               内核库函数 API                         │
│  (string.h, stdio.h, kernel.h等)                   │
└─────────────────────┬───────────────────────────────┘
                      │
         ┌────────────┼────────────┬────────────┐
         │            │            │            │
         ▼            ▼            ▼            ▼
    ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐
    │ String │  │ Print  │  │ List   │  │ Math   │
    │ string.c│  │ print.c│  │ list.h │  │ math.c │
    └────────┘  └────────┘  └────────┘  └────────┘
```

## 字符串操作 (string.c)

### 函数列表

| 函数 | 说明 | 复杂度 |
|------|------|--------|
| `memset` | 填充内存 | O(n) |
| `memcpy` | 复制内存 | O(n) |
| `memmove` | 移动内存（处理重叠） | O(n) |
| `memcmp` | 比较内存 | O(n) |
| `strlen` | 计算字符串长度 | O(n) |
| `strcpy` | 复制字符串 | O(n) |
| `strncpy` | 复制n个字符 | O(n) |
| `strcmp` | 比较字符串 | O(n) |
| `strncmp` | 比较n个字符 | O(n) |
| `strchr` | 查找字符 | O(n) |
| `strstr` | 查找子串 | O(n*m) |
| `atoi` | 字符串转整数 | O(n) |
| `itoa` | 整数转字符串 | O(n) |

### 函数实现

```c
#include <string.h>
#include <types.h>

// 填充内存
void *memset(void *s, int c, size_t n) {
    unsigned char *p = (unsigned char *)s;

    while (n--) {
        *p++ = (unsigned char)c;
    }

    return s;
}

// 复制内存（不处理重叠）
void *memcpy(void *dest, const void *src, size_t n) {
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;

    while (n--) {
        *d++ = *s++;
    }

    return dest;
}

// 移动内存（处理重叠）
void *memmove(void *dest, const void *src, size_t n) {
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;

    if (d < s) {
        // 从前向后复制
        while (n--) {
            *d++ = *s++;
        }
    } else if (d > s) {
        // 从后向前复制
        d += n;
        s += n;
        while (n--) {
            *--d = *--s;
        }
    }

    return dest;
}

// 比较内存
int memcmp(const void *s1, const void *s2, size_t n) {
    const unsigned char *p1 = (const unsigned char *)s1;
    const unsigned char *p2 = (const unsigned char *)s2;

    while (n--) {
        if (*p1 != *p2) {
            return *p1 - *p2;
        }
        p1++;
        p2++;
    }

    return 0;
}

// 计算字符串长度
size_t strlen(const char *s) {
    size_t len = 0;

    while (*s++) {
        len++;
    }

    return len;
}

// 复制字符串
char *strcpy(char *dest, const char *src) {
    char *d = dest;

    while ((*d++ = *src++));

    return dest;
}

// 复制n个字符
char *strncpy(char *dest, const char *src, size_t n) {
    char *d = dest;

    while (n-- && (*d++ = *src++));

    // 填充剩余的'\0'
    while (n--) {
        *d++ = '\0';
    }

    return dest;
}

// 比较字符串
int strcmp(const char *s1, const char *s2) {
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }

    return *(unsigned char *)s1 - *(unsigned char *)s2;
}

// 比较n个字符
int strncmp(const char *s1, const char *s2, size_t n) {
    while (n-- && *s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }

    if (n == SIZE_MAX) {
        return 0;
    }

    return *(unsigned char *)s1 - *(unsigned char *)s2;
}

// 查找字符
char *strchr(const char *s, int c) {
    while (*s) {
        if (*s == (char)c) {
            return (char *)s;
        }
        s++;
    }

    return NULL;
}

// 查找子串
char *strstr(const char *haystack, const char *needle) {
    size_t needle_len = strlen(needle);

    if (needle_len == 0) {
        return (char *)haystack;
    }

    while (*haystack) {
        if (strncmp(haystack, needle, needle_len) == 0) {
            return (char *)haystack;
        }
        haystack++;
    }

    return NULL;
}

// 字符串转整数
int atoi(const char *s) {
    int result = 0;
    int sign = 1;

    // 跳过空白字符
    while (*s == ' ' || *s == '\t' || *s == '\n') {
        s++;
    }

    // 处理符号
    if (*s == '-') {
        sign = -1;
        s++;
    } else if (*s == '+') {
        s++;
    }

    // 转换数字
    while (*s >= '0' && *s <= '9') {
        result = result * 10 + (*s - '0');
        s++;
    }

    return sign * result;
}

// 整数转字符串
char *itoa(int value, char *str, int base) {
    char *p = str;
    char *p1, *p2;
    unsigned int ud = value;
    int divisor = 10;

    // 处理负数
    if (base == 10 && value < 0) {
        *p++ = '-';
        str++;
        ud = -value;
    }

    // 选择除数
    if (base == 16) {
        divisor = 16;
    }

    // 转换数字
    do {
        int remainder = ud % divisor;
        *p++ = (remainder < 10) ? (remainder + '0') : (remainder + 'a' - 10);
    } while (ud /= divisor);

    // 终止字符串
    *p = '\0';

    // 反转字符串
    p1 = str;
    p2 = p - 1;
    while (p1 < p2) {
        char tmp = *p1;
        *p1++ = *p2;
        *p2-- = tmp;
    }

    return str;
}
```

## 格式化输出 (print.c)

### printf实现

```c
#include <print.h>
#include <string.h>
#include <uart.h>

// 辅助函数：输出字符
static void putc(char c, void *data) {
    (void)data;
    uart_putc(c);
}

// 辅助函数：输出字符串
static void puts(const char *s, void *data) {
    (void)data;
    uart_puts(s);
}

// 格式化输出
int printf(const char *fmt, ...) {
    va_list args;
    int count;

    va_start(args, fmt);
    count = vfprintf((putc_func)putc, puts, fmt, args, NULL);
    va_end(args);

    return count;
}

// 格式化输出到指定函数
int vfprintf(putc_func putc, puts_func puts,
             const char *fmt, va_list args, void *data) {
    int count = 0;
    char buf[32];
    int i, len;

    while (*fmt) {
        if (*fmt == '%') {
            fmt++;

            // 处理格式说明符
            switch (*fmt) {
                case 'd':  // 有符号十进制整数
                case 'i':
                    itoa(va_arg(args, int), buf, 10);
                    puts(buf, data);
                    count += strlen(buf);
                    break;

                case 'u':  // 无符号十进制整数
                    utoa(va_arg(args, unsigned int), buf, 10);
                    puts(buf, data);
                    count += strlen(buf);
                    break;

                case 'x':  // 十六进制整数（小写）
                    utoa(va_arg(args, unsigned int), buf, 16);
                    puts(buf, data);
                    count += strlen(buf);
                    break;

                case 'X':  // 十六进制整数（大写）
                    utoa(va_arg(args, unsigned int), buf, 16);
                    for (i = 0; buf[i]; i++) {
                        if (buf[i] >= 'a' && buf[i] <= 'f') {
                            buf[i] -= 32;
                        }
                    }
                    puts(buf, data);
                    count += strlen(buf);
                    break;

                case 'p':  // 指针
                    puts("0x", data);
                    count += 2;
                    utoa((uint64_t)va_arg(args, void *), buf, 16);
                    puts(buf, data);
                    count += strlen(buf);
                    break;

                case 'c':  // 字符
                    putc(va_arg(args, int), data);
                    count++;
                    break;

                case 's':  // 字符串
                    {
                        char *s = va_arg(args, char *);
                        if (s == NULL) {
                            s = "(null)";
                        }
                        puts(s, data);
                        count += strlen(s);
                    }
                    break;

                case '%':  // %本身
                    putc('%', data);
                    count++;
                    break;

                default:
                    putc('%', data);
                    putc(*fmt, data);
                    count += 2;
                    break;
            }
        } else {
            putc(*fmt, data);
            count++;
        }
        fmt++;
    }

    return count;
}

// 无符号整数转字符串
static void utoa(unsigned int value, char *str, int base) {
    char *p = str;
    char *p1, *p2;
    unsigned int ud = value;
    int divisor = base;

    // 转换数字
    do {
        int remainder = ud % divisor;
        *p++ = (remainder < 10) ? (remainder + '0') : (remainder + 'a' - 10);
    } while (ud /= divisor);

    // 终止字符串
    *p = '\0';

    // 反转字符串
    p1 = str;
    p2 = p - 1;
    while (p1 < p2) {
        char tmp = *p1;
        *p1++ = *p2;
        *p2-- = tmp;
    }
}
```

## 链表操作 (list.h)

### 双向链表

```c
#ifndef _LIST_H
#define _LIST_H

#include <types.h>

// 链表节点
struct list_head {
    struct list_head *next, *prev;
};

// 初始化链表头
#define LIST_HEAD_INIT(name) { &(name), &(name) }

#define LIST_HEAD(name) \
    struct list_head name = LIST_HEAD_INIT(name)

// 初始化链表
static inline void INIT_LIST_HEAD(struct list_head *list) {
    list->next = list;
    list->prev = list;
}

// 添加节点到链表头
static inline void list_add(struct list_head *new, struct list_head *head) {
    struct list_head *next = head->next;

    next->prev = new;
    new->next = next;
    new->prev = head;
    head->next = new;
}

// 添加节点到链表尾
static inline void list_add_tail(struct list_head *new, struct list_head *head) {
    struct list_head *prev = head->prev;

    prev->next = new;
    new->next = head;
    new->prev = prev;
    head->prev = new;
}

// 从链表删除节点
static inline void list_del(struct list_head *entry) {
    struct list_head *prev = entry->prev;
    struct list_head *next = entry->next;

    next->prev = prev;
    prev->next = next;
    entry->next = NULL;
    entry->prev = NULL;
}

// 检查链表是否为空
static inline int list_empty(const struct list_head *head) {
    return head->next == head;
}

// 获取包含链表节点的结构体指针
#define list_entry(ptr, type, member) \
    ((type *)((char *)(ptr) - offsetof(type, member)))

// 遍历链表
#define list_for_each(pos, head) \
    for (pos = (head)->next; pos != (head); pos = pos->next)

// 安全遍历链表（支持删除）
#define list_for_each_safe(pos, n, head) \
    for (pos = (head)->next, n = pos->next; \
         pos != (head); \
         pos = n, n = pos->next)

#endif  // _LIST_H
```

## 数学函数 (math.c)

### 基础数学函数

```c
#include <math.h>
#include <types.h>

// 绝对值
int abs(int x) {
    return (x < 0) ? -x : x;
}

// 向上取整
int ceil(float x) {
    int i = (int)x;
    return (x > i) ? (i + 1) : i;
}

// 向下取整
int floor(float x) {
    return (int)x;
}

// 四舍五入
int round(float x) {
    return (int)(x + 0.5);
}

// 最小值
int min(int a, int b) {
    return (a < b) ? a : b;
}

// 最大值
int max(int a, int b) {
    return (a > b) ? a : b;
}

// 限制范围
int clamp(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

// 交换两个值
void swap(int *a, int *b) {
    int tmp = *a;
    *a = *b;
    *b = tmp;
}

// 幂运算（整数）
int pow_int(int base, int exp) {
    int result = 1;

    while (exp > 0) {
        if (exp % 2 == 1) {
            result *= base;
        }
        base *= base;
        exp /= 2;
    }

    return result;
}

// 对数（整数）
int log2_int(uint32_t value) {
    int result = 0;

    while (value >>= 1) {
        result++;
    }

    return result;
}

// 位操作
int popcount(uint32_t x) {
    int count = 0;

    while (x) {
        count += x & 1;
        x >>= 1;
    }

    return count;
}

// 找到最高位
int clz(uint32_t x) {
    int count = 32;

    if (x == 0) return count;

    if (!(x & 0xFFFF0000)) {
        count -= 16;
        x <<= 16;
    }
    if (!(x & 0xFF000000)) {
        count -= 8;
        x <<= 8;
    }
    if (!(x & 0xF0000000)) {
        count -= 4;
        x <<= 4;
    }
    if (!(x & 0xC0000000)) {
        count -= 2;
        x <<= 2;
    }
    if (!(x & 0x80000000)) {
        count--;
        x <<= 1;
    }

    return count;
}
```

## 位图操作 (bitmap.h)

```c
#ifndef _BITMAP_H
#define _BITMAP_H

#include <types.h>

#define BITS_PER_BYTE   8
#define BITS_PER_LONG   32
#define DIV_ROUND_UP(n, d) (((n) + (d) - 1) / (d))
#define BIT_WORD(nr)    ((nr) / BITS_PER_LONG)

// 设置位
static inline void set_bit(int nr, unsigned long *addr) {
    addr[BIT_WORD(nr)] |= (1UL << (nr % BITS_PER_LONG));
}

// 清除位
static inline void clear_bit(int nr, unsigned long *addr) {
    addr[BIT_WORD(nr)] &= ~(1UL << (nr % BITS_PER_LONG));
}

// 测试位
static inline int test_bit(int nr, const unsigned long *addr) {
    return (addr[BIT_WORD(nr)] >> (nr % BITS_PER_LONG)) & 1;
}

// 改变位
static inline void change_bit(int nr, unsigned long *addr) {
    addr[BIT_WORD(nr)] ^= (1UL << (nr % BITS_PER_LONG));
}

// 查找第一个置位的位
static inline int find_first_bit(const unsigned long *addr, unsigned long size) {
    unsigned long i;

    for (i = 0; i < DIV_ROUND_UP(size, BITS_PER_LONG); i++) {
        if (addr[i]) {
            int bit;
            for (bit = 0; bit < BITS_PER_LONG; bit++) {
                if (addr[i] & (1UL << bit)) {
                    return i * BITS_PER_LONG + bit;
                }
            }
        }
    }

    return size;
}

// 查找第一个清零的位
static inline int find_first_zero_bit(const unsigned long *addr, unsigned long size) {
    unsigned long i;

    for (i = 0; i < DIV_ROUND_UP(size, BITS_PER_LONG); i++) {
        if (~addr[i]) {
            int bit;
            for (bit = 0; bit < BITS_PER_LONG; bit++) {
                if (!(addr[i] & (1UL << bit))) {
                    return i * BITS_PER_LONG + bit;
                }
            }
        }
    }

    return size;
}

#endif  // _BITMAP_H
```

## 接口设计

```c
// include/string.h
void *memset(void *s, int c, size_t n);
void *memcpy(void *dest, const void *src, size_t n);
void *memmove(void *dest, const void *src, size_t n);
int memcmp(const void *s1, const void *s2, size_t n);
size_t strlen(const char *s);
char *strcpy(char *dest, const char *src);
char *strncpy(char *dest, const char *src, size_t n);
int strcmp(const char *s1, const char *s2);
int strncmp(const char *s1, const char *s2, size_t n);
char *strchr(const char *s, int c);
char *strstr(const char *haystack, const char *needle);
int atoi(const char *s);
char *itoa(int value, char *str, int base);

// include/print.h
typedef void (*putc_func)(char, void *);
typedef void (*puts_func)(const char *, void *);

int printf(const char *fmt, ...);
int vfprintf(putc_func putc, puts_func puts,
             const char *fmt, va_list args, void *data);

// include/list.h
struct list_head {
    struct list_head *next, *prev;
};

#define LIST_HEAD(name) struct list_head name = { &(name), &(name) }

void INIT_LIST_HEAD(struct list_head *list);
void list_add(struct list_head *new, struct list_head *head);
void list_add_tail(struct list_head *new, struct list_head *head);
void list_del(struct list_head *entry);
int list_empty(const struct list_head *head);

#define list_entry(ptr, type, member) \
    ((type *)((char *)(ptr) - offsetof(type, member)))

#define list_for_each(pos, head) \
    for (pos = (head)->next; pos != (head); pos = pos->next)

// include/math.h
int abs(int x);
int ceil(float x);
int floor(float x);
int round(float x);
int min(int a, int b);
int max(int a, int b);
int clamp(int value, int min, int max);
void swap(int *a, int *b);
int pow_int(int base, int exp);
int log2_int(uint32_t value);
int popcount(uint32_t x);
int clz(uint32_t x);
```

## 参考资料

- [Linux Kernel Lib Functions](https://www.kernel.org/doc/Documentation/kernel-hacking/locking.rst)
- [Linux List Implementation](https://www.kernel.org/doc/Documentation/RCU/listRCU.rst)
- [C Standard Library Functions](https://en.cppreference.com/w/c/string)
