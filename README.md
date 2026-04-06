# EgoKernel

一个面向树莓派4B (BCM2711, ARM64架构) 的操作系统内核。

## 项目信息

- **目标平台**: 树莓派4B (Quad-core ARM Cortex-A72, arm64)
- **开发工具**: aarch64-none-elf-gcc
- **启动地址**: 0x80000 (物理地址)
- **页大小**: 4KB
- **内核大小**: 目标 < 2MB

## 目录结构

```
myKernel/
├── boot/               # 启动代码
├── kernel/             # 内核代码
│   ├── int/           # 中断处理
│   ├── mm/            # 内存管理
│   ├── proc/          # 进程管理
│   ├── drivers/       # 设备驱动
│   ├── lib/           # 库函数
│   └── sync/          # 同步原语
├── arch/arm64/        # ARM64架构代码
├── include/           # 头文件
├── docs/              # 设计文档
├── scripts/           # 构建脚本
├── tests/             # 测试代码
└── Makefile           # 构建文件
```

## 文档

详细的设计文档请查看 `docs/` 目录：

- [boot.md](docs/boot.md) - 启动和引导
- [memory.md](docs/memory.md) - 内存管理
- [interrupt.md](docs/interrupt.md) - 中断处理
- [process.md](docs/process.md) - 进程管理
- [drivers.md](docs/drivers.md) - 设备驱动
- [lib.md](docs/lib.md) - 内核库函数
- [sync.md](docs/sync.md) - 同步原语

## 构建

```bash
# 安装工具链
sudo apt install gcc-aarch64-none-elf binutils-aarch64-none-elf

# 构建
make

# 清理
make clean
```

## 运行

### QEMU模拟（实验性）

```bash
qemu-system-aarch64 -M raspi4b \
  -kernel kernel8.img \
  -serial stdio \
  -nographic
```

### 树莓派实际运行

1. 将 `kernel8.img` 复制到SD卡根目录
2. 在 `config.txt` 中设置 `kernel=kernel8.img`
3. 通过UART串口 (GPIO 14/15, 115200波特率) 观察输出

## 开发状态

当前处于规划阶段，准备开始实现。

## 许可证

MIT License
