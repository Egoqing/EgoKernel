# 设备驱动模块设计文档

## 概述

设备驱动模块负责管理树莓派4B的各种外设，包括UART、GPIO、定时器、帧缓冲区等。本模块提供统一的设备接口，屏蔽硬件细节，便于上层应用使用。

## 架构概览

```
设备驱动架构：
┌─────────────────────────────────────────────────────┐
│            设备抽象层 / 字符设备接口                 │
│    (open, read, write, ioctl, close)              │
└─────────────────────┬───────────────────────────────┘
                      │
         ┌────────────┼────────────┬────────────┐
         │            │            │            │
         ▼            ▼            ▼            ▼
    ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐
    │ UART   │  │ GPIO   │  │ Timer  │  │ Frame  │
    │ Driver │  │ Driver │  │ Driver │  │ Buffer │
    │        │  │        │  │        │  │ Driver │
    └────┬───┘  └────┬───┘  └────┬───┘  └────┬───┘
         │           │           │           │
         └───────────┼───────────┴───────────┘
                     │
                     ▼
              ┌──────────────┐
              │  BCM2711     │
              │  SoC外设     │
              └──────────────┘
```

## UART驱动 (PL011)

### 硬件信息

| 参数 | 值 |
|------|-----|
| 型号 | PL011 (PrimeCell UART) |
| 基地址 | 0xFE201000 (UART0) |
| 中断号 | 57 |
| GPIO引脚 | GPIO 14 (TX), GPIO 15 (RX) |
| 波特率 | 115200 (默认) |

### 寄存器定义

```c
// UART寄存器偏移
#define UART_DR     0x00    // 数据寄存器
#define UART_FR     0x18    // 标志寄存器
#define UART_ILPR   0x20    // IrDA低功耗计数寄存器
#define UART_IBRD   0x24    // 整数波特率除数
#define UART_FBRD   0x28    // 分数波特率除数
#define UART_LCRH   0x2C    // 线控制寄存器
#define UART_CR     0x30    // 控制寄存器
#define UART_IFLS   0x34    // 中断FIFO级别选择
#define UART_IMSC   0x38    // 中断屏蔽设置/清除
#define UART_RIS    0x3C    // 原始中断状态
#define UART_MIS    0x40    // 屏蔽后的中断状态
#define UART_ICR    0x44    // 中断清除寄存器
```

### 寄存器位定义

```c
// 标志寄存器 (FR)
#define UART_FR_TXFE    (1 << 7)   // 发送FIFO空
#define UART_FR_RXFF    (1 << 6)   // 接收FIFO满
#define UART_FR_TXFF    (1 << 5)   // 发送FIFO满
#define UART_FR_RXFE    (1 << 4)   // 接收FIFO空
#define UART_FR_BUSY    (1 << 3)   // UART忙

// 线控制寄存器 (LCRH)
#define UART_LCRH_WLEN_8BIT  (3 << 5)  // 8位数据
#define UART_LCRH_WLEN_7BIT  (2 << 5)  // 7位数据
#define UART_LCRH_WLEN_6BIT  (1 << 5)  // 6位数据
#define UART_LCRH_WLEN_5BIT  (0 << 5)  // 5位数据
#define UART_LCRH_FEN        (1 << 4)  // 使能FIFO
#define UART_LCRH_STP2       (1 << 3)  // 2停止位
#define UART_LCRH_PEN        (1 << 1)  // 奇偶校验使能

// 控制寄存器 (CR)
#define UART_CR_CTSEN     (1 << 15)  // CTS使能
#define UART_CR_RTSEN     (1 << 14)  // RTS使能
#define UART_CR_RTS       (1 << 11)  // RTS
#define UART_CR_RXE       (1 << 9)   // 接收使能
#define UART_CR_TXE       (1 << 8)   // 发送使能
#define UART_CR_LBE       (1 << 7)   // 环回使能
#define UART_CR_UARTEN    (1 << 0)   // UART使能

// 中断寄存器
#define UART_INT_RX    (1 << 4)   // 接收中断
#define UART_INT_TX    (1 << 5)   // 发送中断
```

### 初始化代码

```c
void uart_init(void) {
    volatile uint32_t *uart = (uint32_t *)UART_BASE;

    // 1. 禁用UART
    uart[UART_CR] = 0;

    // 2. 清除中断
    uart[UART_ICR] = 0x7FF;

    // 3. 计算波特率 (115200)
    // UARTCLK = 48MHz
    // BAUDDIV = UARTCLK / (16 * BaudRate)
    // BAUDDIV = 48000000 / (16 * 115200) = 26.04167
    // IBRD = 26, FBRD = (0.04167 * 64) + 0.5 = 3
    uart[UART_IBRD] = 26;
    uart[UART_FBRD] = 3;

    // 4. 配置线控制
    // 8位数据, 无奇偶校验, 1停止位, 使能FIFO
    uart[UART_LCRH] = UART_LCRH_WLEN_8BIT | UART_LCRH_FEN;

    // 5. 配置FIFO中断级别
    uart[UART_IFLS] = 0;  // RX FIFO >= 1/8, TX FIFO <= 7/8

    // 6. 禁用所有中断
    uart[UART_IMSC] = 0;

    // 7. 使能UART
    uart[UART_CR] = UART_CR_UARTEN | UART_CR_TXE | UART_CR_RXE;
}
```

### 数据读写

```c
// 发送一个字符
void uart_putc(char c) {
    volatile uint32_t *uart = (uint32_t *)UART_BASE;

    // 等待发送FIFO非满
    while (uart[UART_FR] & UART_FR_TXFF);

    // 写入数据寄存器
    uart[UART_DR] = c;
}

// 接收一个字符
char uart_getc(void) {
    volatile uint32_t *uart = (uint32_t *)UART_BASE;

    // 等待接收FIFO非空
    while (uart[UART_FR] & UART_FR_RXFE);

    // 读取数据寄存器
    return uart[UART_DR] & 0xFF;
}

// 发送字符串
void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') {
            uart_putc('\r');
        }
        uart_putc(*s);
        s++;
    }
}

// 接收字符串
void uart_gets(char *s, int max) {
    char c;
    int i = 0;

    while (i < max - 1) {
        c = uart_getc();
        if (c == '\r') {
            uart_putc('\r');
            uart_putc('\n');
            break;
        }
        uart_putc(c);
        s[i++] = c;
    }
    s[i] = '\0';
}
```

## GPIO驱动

### 硬件信息

| 参数 | 值 |
|------|-----|
| GPIO数量 | 54个 |
| 基地址 | 0xFE200000 |
| 复用功能 | 输入、输出、Alt0-Alt5 |

### 寄存器定义

```c
// GPIO寄存器偏移
#define GPIO_GPFSEL0    0x00    // 功能选择0-9
#define GPIO_GPFSEL1    0x04    // 功能选择10-19
#define GPIO_GPFSEL2    0x08    // 功能选择20-29
#define GPIO_GPFSEL3    0x0C    // 功能选择30-39
#define GPIO_GPFSEL4    0x10    // 功能选择40-49
#define GPIO_GPFSEL5    0x14    // 功能选择50-53

#define GPIO_GPSET0     0x1C    // 输出置位0-31
#define GPIO_GPSET1     0x20    // 输出置位32-53

#define GPIO_GPCLR0     0x28    // 输出清除0-31
#define GPIO_GPCLR1     0x2C    // 输出清除32-53

#define GPIO_GPLEV0     0x34    // 输入电平0-31
#define GPIO_GPLEV1     0x38    // 输入电平32-53

#define GPIO_GPEDS0     0x40    // 事件检测状态0-31
#define GPIO_GPEDS1     0x44    // 事件检测状态32-53

#define GPIO_GPREN0     0x4C    // 上升沿使能0-31
#define GPIO_GPREN1     0x50    // 上升沿使能32-53

#define GPIO_GPFEN0     0x58    // 下降沿使能0-31
#define GPIO_GPFEN1     0x5C    // 下降沿使能32-53

#define GPIO_GPHEN0     0x64    // 高电平使能0-31
#define GPIO_GPHEN1     0x68    // 高电平使能32-53

#define GPIO_GPLEN0     0x70    // 低电平使能0-31
#define GPIO_GPLEN1     0x74    // 低电平使能32-53

#define GPIO_GPPUD      0x94    // 上拉/下拉使能
#define GPIO_GPPUDCLK0  0x98    // 上拉/下拉时钟0-31
#define GPIO_GPPUDCLK1  0x9C    // 上拉/下拉时钟32-53
```

### 功能选择

```c
// GPIO功能选择
#define GPIO_FUNC_INPUT    0
#define GPIO_FUNC_OUTPUT   1
#define GPIO_FUNC_ALT0     4
#define GPIO_FUNC_ALT1     5
#define GPIO_FUNC_ALT2     6
#define GPIO_FUNC_ALT3     7
#define GPIO_FUNC_ALT4     3
#define GPIO_FUNC_ALT5     2
```

### GPIO操作

```c
void gpio_set_function(int pin, int func) {
    volatile uint32_t *gpio = (uint32_t *)GPIO_BASE;
    int reg = pin / 10;
    int shift = (pin % 10) * 3;
    uint32_t mask = 0x7 << shift;

    gpio[GPIO_GPFSEL0 + reg] = (gpio[GPIO_GPFSEL0 + reg] & ~mask) |
                               (func << shift);
}

void gpio_set_output(int pin) {
    gpio_set_function(pin, GPIO_FUNC_OUTPUT);
}

void gpio_set_input(int pin) {
    gpio_set_function(pin, GPIO_FUNC_INPUT);
}

void gpio_write(int pin, int value) {
    volatile uint32_t *gpio = (uint32_t *)GPIO_BASE;
    int reg = (pin < 32) ? GPIO_GPSET0 : GPIO_GPSET1;

    if (value) {
        gpio[reg] = 1 << (pin % 32);
    } else {
        reg = (pin < 32) ? GPIO_GPCLR0 : GPIO_GPCLR1;
        gpio[reg] = 1 << (pin % 32);
    }
}

int gpio_read(int pin) {
    volatile uint32_t *gpio = (uint32_t *)GPIO_BASE;
    int reg = (pin < 32) ? GPIO_GPLEV0 : GPIO_GPLEV1;

    return (gpio[reg] >> (pin % 32)) & 1;
}
```

## 定时器驱动

### ARM Generic Timer

树莓派4B使用ARM Generic Timer，频率约54MHz。

```c
// 寄存器定义
#define CNTP_CTL_EL0    mrs  x0, cntp_ctl_el0    // 物理定时器控制
#define CNTP_TVAL_EL0   mrs  x0, cntp_tval_el0   // 物理定时器值
#define CNTP_CVAL_EL0   mrs  x0, cntp_cval_el0   // 物理定时器比较值
#define CNTPCT_EL0      mrs  x0, cntpct_el0      // 物理计数器

// 定时器控制位
#define TIMER_ENABLE    (1 << 0)
#define TIMER_IMASK     (1 << 1)
#define TIMER_ISTATUS   (1 << 2)
```

### 初始化

```c
void timer_init(void) {
    // 获取定时器频率
    uint64_t freq;
    asm volatile("mrs %0, cntfrq_el0" : "=r"(freq));

    // 设置定时器周期 (10ms)
    uint64_t ticks = freq / 100;
    asm volatile("msr cntp_tval_el0, %0" : : "r"(ticks));

    // 使能定时器和中断
    uint64_t ctrl;
    asm volatile("mrs %0, cntp_ctl_el0" : "=r"(ctrl));
    ctrl |= TIMER_ENABLE;
    ctrl &= ~TIMER_IMASK;
    asm volatile("msr cntp_ctl_el0, %0" : : "r"(ctrl));

    // 注册中断处理
    request_irq(IRQ_TIMER, timer_handler, 0, "timer", NULL);
}

void timer_handler(void *data) {
    // 清除中断
    uint64_t ctrl;
    asm volatile("mrs %0, cntp_ctl_el0" : "=r"(ctrl));
    ctrl |= TIMER_ISTATUS;
    asm volatile("msr cntp_ctl_el0, %0" : : "r"(ctrl));

    // 更新系统时间
    system_ticks++;

    // 调度器tick
    scheduler_tick();

    // 重新加载定时器
    uint64_t freq;
    asm volatile("mrs %0, cntfrq_el0" : "=r"(freq));
    uint64_t ticks = freq / 100;
    asm volatile("msr cntp_tval_el0, %0" : : "r"(ticks));
}
```

### 延迟函数

```c
void udelay(uint64_t us) {
    uint64_t freq;
    uint64_t start, current;

    asm volatile("mrs %0, cntfrq_el0" : "=r"(freq));
    asm volatile("mrs %0, cntpct_el0" : "=r"(start));

    uint64_t end = start + (freq * us) / 1000000;

    do {
        asm volatile("mrs %0, cntpct_el0" : "=r"(current));
    } while (current < end);
}

void mdelay(uint64_t ms) {
    udelay(ms * 1000);
}
```

## 帧缓冲区驱动

### Mailbox接口

帧缓冲区通过VideoCore的Mailbox接口配置：

```c
#define MAILBOX_BASE    0xFE00B880

// Mailbox寄存器
#define MAILBOX_READ    0x00
#define MAILBOX_STATUS  0x18
#define MAILBOX_WRITE   0x20

// Mailbox状态
#define MAILBOX_FULL    (1 << 31)
#define MAILBOX_EMPTY   (1 << 30)

// Mailbox通道
#define MAILBOX_CHANNEL_PROP  8

// 帧缓冲区请求
#define MBOX_REQUEST_CODE     0x00000000
#define MBOX_TAG_GET_PHYSICAL  0x00040003
#define MBOX_TAG_GET_FB_SIZE   0x00040004
#define MBOX_TAG_ALLOCATE_FB   0x00040001
#define MBOX_TAG_GET_PITCH     0x00040008
#define MBOX_REQUEST_SUCCESS   0x80000000
```

### 帧缓冲区初始化

```c
uint32_t *fb_init(int width, int height) {
    uint32_t fb_info[32];
    uint64_t fb_addr;
    uint32_t fb_size, fb_pitch;

    // 准备Mailbox请求
    fb_info[0] = 35 * 4;  // 消息大小
    fb_info[1] = MBOX_REQUEST_CODE;

    // 分配帧缓冲区
    fb_info[2] = MBOX_TAG_ALLOCATE_FB;
    fb_info[3] = 8;
    fb_info[4] = 8;
    fb_info[5] = width;
    fb_info[6] = height;
    fb_info[7] = 0;  // 请求响应

    // 获取物理地址
    fb_info[8] = MBOX_TAG_GET_PHYSICAL;
    fb_info[9] = 4;
    fb_info[10] = 4;
    fb_info[11] = 0;
    fb_info[12] = 0;

    // 获取大小
    fb_info[13] = MBOX_TAG_GET_FB_SIZE;
    fb_info[14] = 4;
    fb_info[15] = 4;
    fb_info[16] = 0;
    fb_info[17] = 0;

    // 获取pitch
    fb_info[18] = MBOX_TAG_GET_PITCH;
    fb_info[19] = 4;
    fb_info[20] = 4;
    fb_info[21] = 0;
    fb_info[22] = 0;

    fb_info[23] = 0;  // 结束标签

    // 发送Mailbox请求
    mailbox_call(fb_info, MAILBOX_CHANNEL_PROP);

    // 解析响应
    fb_addr = ((uint64_t)fb_info[6] << 32) | fb_info[5];
    fb_size = fb_info[17];
    fb_pitch = fb_info[22];

    // 映射帧缓冲区内存
    uint32_t *fb = (uint32_t *)map_range(fb_addr, fb_addr, fb_size,
                                         PROT_READ | PROT_WRITE);

    return fb;
}

void mailbox_call(uint32_t *info, int channel) {
    uint64_t r = ((uint64_t)((uint32_t)info) & ~0xF) | (channel & 0xF);

    // 等待Mailbox非满
    while (*MAILBOX_STATUS & MAILBOX_FULL);

    // 写入请求
    *MAILBOX_WRITE = r;

    // 等待响应
    while (1) {
        while (*MAILBOX_STATUS & MAILBOX_EMPTY);
        if (r == *MAILBOX_READ) {
            return info[1] == MBOX_REQUEST_SUCCESS;
        }
    }
}
```

## 接口设计

```c
// include/drivers/uart.h
void uart_init(void);
void uart_putc(char c);
char uart_getc(void);
void uart_puts(const char *s);
void uart_gets(char *s, int max);

// include/drivers/gpio.h
void gpio_set_function(int pin, int func);
void gpio_set_output(int pin);
void gpio_set_input(int pin);
void gpio_write(int pin, int value);
int gpio_read(int pin);

// include/drivers/timer.h
void timer_init(void);
void udelay(uint64_t us);
void mdelay(uint64_t ms);
uint64_t get_ticks(void);

// include/drivers/framebuffer.h
uint32_t *fb_init(int width, int height);
void fb_put_pixel(int x, int y, uint32_t color);
void fb_clear(uint32_t color);
```

## 初始化顺序

```
设备驱动初始化顺序：

kernel_main()
    │
    ▼
uart_init()         // 最先初始化，用于调试输出
    │
    ▼
gpio_init()
    │
    ▼
timer_init()        // 定时器初始化后才能调度
    │
    ▼
gic_init()           // 中断控制器
    │
    ▼
fb_init()           // 帧缓冲区（可选）
```

## 调试技巧

1. **GPIO调试**：用GPIO LED指示状态
2. **UART日志**：详细打印设备状态
3. **定时器统计**：记录中断触发时间
4. **帧缓冲区测试**：绘制测试图案

## 参考资料

- [BCM2711 Peripherals Datasheet](https://datasheets.raspberrypi.com/bcm2711/bcm2711-peripherals.pdf)
- [PL011 UART Technical Reference Manual](https://developer.arm.com/documentation/ddi0183/latest/)
- [ARM Generic Timer](https://developer.arm.com/documentation/ddi0406/latest/)
- [Raspberry Pi Mailbox Interface](https://github.com/raspberrypi/firmware/wiki/Mailbox-property-interface)
