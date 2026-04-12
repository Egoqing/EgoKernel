/*
 * EgoKernel 链接脚本
 * 定义内核在内存中的布局
 */

ENTRY(_start)

SECTIONS {
    /* 内核加载地址：0x80000 */
    . = KERNEL_LOAD_ADDR;

    /* 启动代码放在最开始 */
    .text.boot : {
        *(.text.boot)
    }

    /* 代码段 */
    .text : {
        . = ALIGN(8);
        *(.text)
        *(.text.*)
    }

    /* 只读数据段 */
    .rodata : {
        . = ALIGN(8);
        *(.rodata)
        *(.rodata.*)
    }

    /* 只读代码和数据用于ARM的特殊段 */
    . = ALIGN(8);
    .ARM.extab : {
        *(.ARM.extab* .gnu.linkonce.armextab.*)
    }

    .ARM : {
        __exidx_start = .;
        *(.ARM.exidx* .gnu.linkonce.armexidx.*)
        __exidx_end = .;
    }

    /* 数据段 */
    .data : {
        . = ALIGN(8);
        *(.data)
        *(.data.*)
    }

    /* BSS段（未初始化数据） */
    .bss : {
        . = ALIGN(16);
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        __bss_end = .;
    }

    /* 内核栈 (16KB) */
    . = ALIGN(16);
    .stack : {
        __stack_bottom = .;
        . = . + KERNEL_STACK_SIZE;
        __stack_top = .;
    }

    /* 堆起始地址 */
    . = ALIGN(4096);
    __heap_start = .;

    /* 调试信息 */
    /DISCARD/ : {
        *(.comment)
        *(.note.*)
    }

    /* 符号表和字符串表 */
    .symtab 0 : { *(.symtab) }
    .strtab 0 : { *(.strtab) }
    .shstrtab 0 : { *(.shstrtab) }
}

/* 导出符号给C代码使用 */
__bss_size = __bss_end - __bss_start;
