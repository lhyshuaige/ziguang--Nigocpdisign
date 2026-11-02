# CPU 固件与上位机

## 两类镜像

- `.sbit` / `.bin`：配置 FPGA 的硬件设计。
- `.ngb`：带 NGB1 头和 CRC 的 Nigo CPU 应用，由网络 Bootloader 装入 DDR。

应用上限 2 MiB 来自 Bootloader 协议和链接窗口，不是板上 DDR 容量。当前统一程序载荷仅 125,336 字节，包含图像接收、AI、CoreMark、四款游戏和模式管理。

## 内存与模式

| 范围 / 地址 | 用途 |
|---|---|
| `0x82000000` 起，2 MiB | 应用代码和载入镜像 |
| `0x82800000` 起，128 KiB | 应用数据、BSS、栈 |
| `0x83000000` | 320×240 索引色游戏帧缓冲 |
| `0x83100000` | 游戏 RLE 编码缓冲 |
| `0x10000004` | KEY1～KEY4 输入，位 0～3 |

统一程序常驻；上位机发送 NMQ1/NMR1 模式命令。模式号 0 待机、1 收图、2 AI、3 CoreMark、4 游戏、5 按键诊断。切换等待正在执行的任务和 DMA 安全退出。CoreMark 计时段不轮询模式请求，完成后再响应切换。

## 复现被冻结的固件

`firmware/recipes/runtime.json` 与 `arcade.json` 保存每个源文件的哈希、编译顺序和完整命令。源码现位于 `upper/firmware/`。使用 GNU RISC-V GCC 13.2.0：

```sh
export NIGO_RISCV_TOOLS=/path/to/riscv/bin
python3 tools/build_firmware.py runtime
python3 tools/build_firmware.py arcade
python3 tools/build_firmware.py bootloader
```

也可传 `--tools /path/to/riscv/bin`。输出在根目录 `build/firmware/`，不覆盖 `upper/assets/firmware/`。成功必须显示 `REFERENCE_BYTES_MATCH`；更换编译器或源码后若镜像不同，不能继续视为该实测版本。

本次迁移已实际执行三种构建，统一固件、独立游戏二进制以及 Boot ROM 初始化数据均与参考一致。Bootloader ELF 含调试路径，其 ELF 文件自身不要求逐字节一致，比较的是 ROM 内容。

ISA 为 RV32IM + Zicsr，ABI 为 ILP32，medany。普通应用文件用 O2；CoreMark 文件和链接使用保留的优化组合，包括 `-mtune=sifive-7-series -funroll-all-loops` 以及 8 字节函数/循环/跳转对齐。完整参数以配方为准。`-mtune` 不改变目标 ISA。

当前 9700ce2a 的代码布局因游戏绘图变化而改变，未重新测定其 CoreMark 成绩；不能把旧独立程序的 5.08 CoreMark/MHz 填作它的结果。

## 变更开发

固定配方用于复现，源码哈希变化会主动拒绝。修改代码时，应复制配方并建立新构建号、更新资源清单，然后执行相应回归和实板验证；不要只修改旧版哈希以冒充原构建。

上位机 `app.py` 沿用原程序。迁移只把 CoreMark A/B 日志的纯解析函数抽到 `nigo_host/coremark_audit.py`，并将资源测试改为仓库内相对路径。`assets/firmware/runtime.ngb` 默认采用已经实测的新统一程序，旧 `946fbc9b` 单独保存在 `assets/firmware/legacy/`。

## Flash 应用工具

`tools/flash/flash_image.py` 处理应用槽镜像；`install_application.py` 通过恢复 Bootloader 保存 CPU 应用到 A/B 槽。它会真正写应用 Flash，操作前应明确准备保存的 `.ngb` 文件。它不烧录 FPGA 配置区，也不代替 FPGA 位流固化工具。

本次整理未执行 Flash 写入或实板下载。
