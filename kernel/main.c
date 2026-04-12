/*
 * EgoKernel C内核入口
 *
 * 这是内核的主函数，从汇编启动代码跳转而来
 * 此时代码已运行在EL1异常级别
 */

#include <kernel.h>
#include <config.h>

/* ===== USER IMPLEMENTATION REQUIRED =====
 *
 * 你需要实现以下函数：
 *
 * 1. uart_init() - UART串口驱动初始化
 *    - 禁用控制流和中断
 *    - 设置波特率115200
 *    - 设置数据格式8N1
 *    - 启用UART
 *
 * 2. uart_putc(char c) - 输出单个字符
 *    - 等待发送寄存器为空
 *    - 写入字符
 *
 * 3. uart_puts(const char *str) - 输出字符串
 *    - 遍历字符串，逐个字符输出
 *
 * 4. strlen(const char *str) - 计算字符串长度
 *
 * 参考: docs/drivers.md, docs/lib.md
 * ===== END USER IMPLEMENTATION ===== */

static inline void uart_init(void) {
    /* TODO: 实现UART初始化 */
}

static inline void uart_putc(char c) {
    /* TODO: 实现字符输出 */
}

void uart_puts(const char *str) {
    /* TODO: 实现字符串输出 */
}

/* ===== USER IMPLEMENTATION REQUIRED =====
 *
 * kernel_main() 是内核的主入口函数
 *
 * 建议流程：
 * 1. 调用 uart_init() 初始化串口
 * 2. 输出启动横幅 (使用 uart_puts)
 * 3. 输出配置信息 (页大小、栈大小、CPU数)
 * 4. 输出当前异常级别 (使用 get_current_el())
 * 5. 输出完成信息
 * 6. 进入无限循环，调用 wfi()
 * ===== END USER IMPLEMENTATION ===== */

void kernel_main(void) {
    /* TODO: 实现内核主函数 */

    /* 主循环 */
    while (1) {
        wfi();  /* Wait For Interrupt */
    }
}
