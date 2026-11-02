# Nigo CPU SoC · LG100 P3

面向盘古 100Pro+ / MES2L676-100HP 开发板的 FPGA SoC。Nigo CPU 负责调度，集成 DDR3、千兆 Ethernet、INT8 AI 加速器、图像接收 DMA、双 SPI Flash 控制器、GPIO 和启动 ROM；配套 Python 上位机提供程序下载、图片输入、人脸检测、CoreMark 和四款小游戏。

本仓库整理于 **2026-11-01**，包含当前实板验证采用的 **P3 Flash 引脚修正版 + setup25 / hold0**。CPU 生成 RTL 文件沿用 `NaxRiscvContest.v` 名称，其上游来源和许可见 [第三方说明](THIRD_PARTY.md)。

## 当前版本

| 项目 | 版本 / 状态 |
|---|---|
| FPGA | PG2L100H，速度等级 -6，FBG676 |
| 时钟 | Nigo CPU 100 MHz；DDR 用户侧、Ethernet 侧 125 MHz |
| 顶层 | [`rtl/pg2l100h_soc_rx_top.v`](rtl/pg2l100h_soc_rx_top.v)，模块 `pg2l100h_soc_p3_top` |
| 内部 SoC | [`rtl/pg2l100h_soc_core_rx.v`](rtl/pg2l100h_soc_core_rx.v) |
| 上位机默认统一固件 | `9700ce2a`，载荷 125,336 字节，含头 `.ngb` 为 125,368 字节 |
| FPGA 位流 | [`release/fpga/pg2l100h_soc_p3_top.sbit`](release/fpga/pg2l100h_soc_p3_top.sbit) |
| 布线数据库 | [`reference/p3_setup25/routed_db.zip`](reference/p3_setup25/routed_db.zip)，保存已签核的实际数据库 |

位流 SHA-256：

```text
43fc76db3db726b4eb9ec2648f9dcda1a946bb90f45481da4fbfec925c3d009a
```

统一固件 SHA-256：

```text
5047392f58056cc307995d6eabd8afe76bdddf0a8b6c3690551674ea403bf661
```

## 能做什么

- **网络启动**：PC 将最多 2 MiB 的 CPU 应用下载到 DDR，校验 CRC 后从 `0x82000000` 执行；Boot ROM 支持 Flash A/B 应用启动和按键恢复。
- **图像接收**：通过 Ethernet 接收 Gray8 / RGB565，使用接收 DMA 和帧缓冲管理器写 DDR。
- **人脸检测**：CPU 调度 AI 加速器执行 UltraFace-Slim-320，回传人脸框、置信度和出现/离开事件。用于低频检测；不识别人员身份。
- **统一应用切换**：上位机切页后，通过网络在待机、图像接收、AI、CoreMark、游戏和按键诊断之间切换，正常切换不需要 KEY0。
- **游戏**：Nigo CPU 执行逻辑、绘图和 RLE 编码，PC 接收并显示 320×240 图像。包含飞机大战 + Boss、贪吃蛇、打砖块、落块。
- **Flash**：两颗 Flash 的 ID、读写、擦除、应用槽校验和启动流程已有实板验证。

Camera/Vision 模块源码保留，但当前板级顶层没有接入 OV7670 实际管脚；图像输入来自 PC。本版也没有 HDMI 板级输出。AI 当前通过 CPU mailbox 接收 320×240 RGB888；RX DMA 帧直接交给 AI 的软件流程尚未接入。RX 提交成功尚不包含 DDR 像素逐字节回读证明。

## 快速开始

1. 安装适配的 PDS 工具和下载器驱动，在 PDS 下载工具中将上述 `.sbit` 下载到 FPGA SRAM 并校验。这里的 `.sbit` 与 CPU `.ngb` 是两种不同镜像。
2. 板卡与 PC 用网线连接。板卡默认 `192.168.1.50`；PC 接板网卡配置 `192.168.1.100/24`。上位机不会自行修改系统网卡配置。
3. 安装带 Tkinter 的 Python 3.10+，在仓库根目录执行：

   ```powershell
   python -m pip install -r upper/requirements.txt
   python -B upper/app.py
   ```

   Windows 也可以双击 `upper/start.cmd`。

4. 如果 Flash 自动启动了旧应用：**按住 KEY1，按下并松开 KEY0，继续按住 KEY1 约 3 秒后松开**，进入网络恢复。不要按 REST。随后点击上位机“连接 / 安装统一固件”，确认状态栏构建号为 **9700ce2a**。
5. 正常切页只切换 CPU 模式。游戏菜单 KEY1 / KEY2 选择、KEY3 进入；游戏内按住 KEY1 + KEY2 约 0.75 秒返回菜单。

当前测试板 Flash 内保留旧统一应用 `946fbc9b`。普通 KEY0 复位仍会启动它；安装新版到 DDR 不会自动覆盖 Flash。首次检测需上传附带模型，复位或断电后需要重新上传。

## 目录

```text
rtl/                     当前 P3 与复用模块的完整 RTL
ip/                      Pango DDR3 / PLL IP 输入文件
third_party/             Ethernet 上游依赖
constraints/             8 份 FDC 与参考固定位置 PCF
pds/                     可迁移的源工程模板、文件清单
firmware/bootloader/     P3 Bootloader 源码和实际使用的 ROM hex
firmware/recipes/        实测应用的完整构建参数、源码哈希
upper/                   Python 上位机、CPU 应用源码、模型及固件
release/fpga/            当前实测 FPGA 位流
reference/p3_setup25/    精确布线数据库、STA 摘要、审计证明
validation/             Flash / 游戏实板记录及本次迁移验证
tools/                  校验、构建、STA 复现和 Flash 应用工具
docs/                   架构、软件和时序复现说明
```

## 构建和验证

```powershell
python -B verify_package.py
Push-Location upper
python -B -m unittest discover -s tests -v
Pop-Location
python -B tools/check_timing.py
python -B tools/pds_flow.py prepare --use-reference-placement
```

上位机测试也可先进入 `upper`，运行 `python -B -m unittest discover -s tests -v`。离线网络测试仅使用 `127.0.0.1`。

8 组 Native C 回归可运行 `python tools/test_native.py`；需要主机 GCC 位于 PATH，或用环境变量 `CC` 指定 GCC 可执行文件。测试使用模拟 MMIO，不操作开发板。

`pds_flow.py prepare` 生成 `build/p3_source/Nigo_P3.pds`，供 PDS 打开源码工程。它只准备文件，不运行 FPGA 实现。新综合、布局布线的结果需要重新验证，不能继承参考数据库的签核结果。

CPU 固件可用 GNU RISC-V GCC 13.2.0 重编译。示例（Linux / WSL，路径自行设为工具链目录）：

```sh
export NIGO_RISCV_TOOLS=/path/to/riscv/bin
python3 tools/build_firmware.py runtime
python3 tools/build_firmware.py arcade
python3 tools/build_firmware.py bootloader
```

输出保存在 `build/firmware/`，脚本不会覆盖随包固件或下载实板。固定构建配方会核对源码和最终镜像哈希；修改源码后应建立新构建版本。完整说明见 [架构与模块](docs/ARCHITECTURE.md)、[软件构建](docs/SOFTWARE.md)、[时序复现](docs/TIMING_REPRODUCTION.md)、[上板顺序](docs/BOARD_TEST.md)。

独立参数实验见 [CoreMark 32 / 4 / 8 对齐实板对照](experiments/coremark_align32_20261101/README.md)，包含重建脚本、候选镜像及逐次原始回传记录。该候选没有替换本仓库发布固件。

在同一组编译参数上，将 2,000 字节工作区从静态区移到栈上的试验见 [CoreMark MEM_STACK 对照](experiments/coremark_stack_20261101/README.md)。栈仍位于 DDR，RTL 和发布镜像保留。

进一步复用原仿真机器码和段内布局的 [独立 CoreMark 复刻](experiments/coremark_replay_20261101/README.md)：同镜像 100 轮仿真为 5.21074 CoreMark/MHz；实板三次 11,000 轮均值为 5.14218，CRC 和受控外设静默审计通过。短测与长测、行为内存与实板 DDR 的差异均在记录中保留；该候选没有替换默认统一固件。

## 已有验证及边界

| 检查 | 结果 |
|---|---|
| P3 setup slow / fast | +0.024 / +0.269 ns，失败端点 0 |
| P3 hold slow / fast | +0.138 / +0.040 ns，失败端点 0 |
| Recovery / removal / minimum pulse width | 报告中的 slow / fast 检查通过 |
| 新版游戏 | 四款基本操作分两轮完成；补测 321.734 秒、9,655 帧、29.98 FPS、丢帧及无效包 0，318 次版本核对一致 |
| 包迁移 | 62 项上位机离线回归通过；统一固件、独立游戏及 Boot ROM 重建内容与原镜像一致 |

显式 sys100 setup uncertainty 为 **25 ps**；PDS 自动 PLL 抖动项 **150 ps** 保留，报告实际扣减 **175 ps**；hold uncertainty 为 **0 ps**。这属于既有约束范围内的 STA 签核，Flash 外部 SPI AC 和全板电气特性尚未完成独立签核。

前次游戏测试曾回到旧 Flash 固件，用户随后表示可能误按复位，原因未确认；该事件保留在记录中。后续有限时长补测没有重现，不能据此宣称长期稳定性已完全验证。新统一固件的 CoreMark 地址布局已经变化，历史 5.08 CoreMark/MHz 不能直接当作本镜像成绩。

本包包含厂商 IP 原始文件及其版权声明，详见 [THIRD_PARTY.md](THIRD_PARTY.md)。没有为厂商或第三方文件新增授权。
