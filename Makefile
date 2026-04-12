# EgoKernel Makefile
# 用于编译ARM64树莓派4B内核

# ===== 配置 =====

# 工具链前缀
CROSS_COMPILE ?= aarch64-none-elf-

# 编译工具
CC      = $(CROSS_COMPILE)gcc
AS      = $(CROSS_COMPILE)as
LD      = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump

# 项目目录
SRC_DIR     = .
BOOT_DIR    = boot
KERNEL_DIR  = kernel
ARCH_DIR    = arch/arm64
INCLUDE_DIR = include
BUILD_DIR   = build

# 内核镜像名称
KERNEL_IMAGE = kernel8.img
KERNEL_ELF   = kernel8.elf

# ===== 编译选项 =====

# 汇编选项
ASFLAGS = -Wall

# C编译选项
CFLAGS = -Wall -Wextra -Werror -O2 -ffreestanding -nostdlib
CFLAGS += -I$(INCLUDE_DIR)
CFLAGS += -mgeneral-regs-only
CFLAGS += -std=gnu99

# 链接选项
LDFLAGS = -nostdlib -nostartfiles
LDFLAGS += -T $(BOOT_DIR)/linker.ld

# 调试选项 (添加 DEBUG=1 启用)
ifeq ($(DEBUG),1)
    CFLAGS += -g -DDEBUG
endif

# ===== 源文件 =====

# 启动汇编文件
BOOT_ASM = $(BOOT_DIR)/start.S

# 内核C文件
KERNEL_C = $(KERNEL_DIR)/main.c

# 生成目标文件
BOOT_ASM_OBJ   = $(BUILD_DIR)/boot/start.o
KERNEL_C_OBJ   = $(BUILD_DIR)/kernel/main.o

# 所有目标文件
OBJS = $(BOOT_ASM_OBJ) $(KERNEL_C_OBJ)

# ===== 规则 =====

.PHONY: all clean dump

# 默认目标
all: $(BUILD_DIR) $(KERNEL_IMAGE)

# 创建构建目录
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(BUILD_DIR)/boot
	@mkdir -p $(BUILD_DIR)/kernel

# 编译汇编文件
$(BOOT_ASM_OBJ): $(BOOT_ASM)
	@echo "[AS] $<"
	$(CC) $(ASFLAGS) -c $< -o $@

# 编译C文件
$(KERNEL_C_OBJ): $(KERNEL_C)
	@echo "[CC] $<"
	$(CC) $(CFLAGS) -c $< -o $@

# 链接生成ELF文件
$(BUILD_DIR)/$(KERNEL_ELF): $(OBJS)
	@echo "[LD] $@"
	$(LD) $(LDFLAGS) $(OBJS) -o $@

# 转换为二进制镜像
$(KERNEL_IMAGE): $(BUILD_DIR)/$(KERNEL_ELF)
	@echo "[OBJCOPY] $@"
	$(OBJCOPY) -O binary $< $@
	@echo ""
	@echo "Build complete: $@"

# 反汇编 (用于调试)
dump: $(BUILD_DIR)/$(KERNEL_ELF)
	@echo "[DUMP] Disassembly"
	$(OBJDUMP) -D $< | less

# 清理构建文件
clean:
	@echo "[CLEAN]"
	rm -rf $(BUILD_DIR)
	rm -f $(KERNEL_IMAGE)

# 显示帮助信息
help:
	@echo "EgoKernel Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  all          - Build kernel image (default)"
	@echo "  clean        - Remove build artifacts"
	@echo "  dump         - Show disassembly of kernel"
	@echo "  help         - Show this help message"
	@echo ""
	@echo "Options:"
	@echo "  DEBUG=1      - Build with debug symbols"
	@echo ""
	@echo "Example:"
	@echo "  make DEBUG=1"
	@echo "  make clean"
