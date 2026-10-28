# A30 工程结构与数据流

## 目标和实际边界

目标板卡是 MES2L676-100HP（PG2L100H-6IFBG676）。NaxRiscv CPU 负责网络命令、模型与图像上传、AI 描述符调度、结果解码和事件上报；AI 加速器执行 UltraFace-Slim-320 的 INT8 运算。当前输入是 PC 通过 Ethernet 上传的 320×240 图像。OV7670 接口 RTL 已保留，但板级顶层把相机输入固定为零，尚不能接实物相机。

```text
PC 图像/模型 → RGMII Ethernet/UDP → CPU 固件 → DDR3
                                     ↓ 调度
                         AI CSR → INT8 AI AXI 主设备
                                     ↓
                         CPU 解码检测框、匹配 ID 和事件
                                     ↓
                             Ethernet → PC 上位机
```

## 主要模块

| 层次 | 入口文件 | 功能 |
| --- | --- | --- |
| 板级顶层 | [`rtl/pg2l100h_soc_top.v`](../rtl/pg2l100h_soc_top.v) | 125 MHz 参考时钟、PLL、DDR3 引脚、RGMII 引脚、复位与 SoC 连接；相机输入当前固定为零。 |
| SoC 核心 | [`rtl/pg2l100h_soc_core.v`](../rtl/pg2l100h_soc_core.v) | 实例化 CPU、AXI 主设备与互连、AI、视觉流水线、Ethernet 控制桥和中断。 |
| CPU 与启动 ROM | [`rtl/NaxRiscvContest.v`](../rtl/NaxRiscvContest.v)、[`rtl/cpu_boot_rom.sv`](../rtl/cpu_boot_rom.sv) | 32 位 CPU；32 KiB 片上 ROM 启动固件，等待 DDR 校准后释放 SoC。 |
| AI 控制与计算 | [`rtl/ai_native_csr_bridge.sv`](../rtl/ai_native_csr_bridge.sv)、[`rtl/ai_accel/ai_accelerator_top.sv`](../rtl/ai_accel/ai_accelerator_top.sv)、[`rtl/ai_accel/ai_stream_tile_executor_v2.sv`](../rtl/ai_accel/ai_stream_tile_executor_v2.sv) | CPU CSR 桥、描述符队列、8 路 INT8 tile 计算和 Q24 后处理；AI 通过 AXI 读写 DDR。 |
| 内存系统 | [`rtl/pgl50h_axi4_mem_fabric.v`](../rtl/pgl50h_axi4_mem_fabric.v)、[`rtl/pgl50h_axi_hmic_cdc.v`](../rtl/pgl50h_axi_hmic_cdc.v)、[`rtl/pg2l100h_ddr3_wrapper.v`](../rtl/pg2l100h_ddr3_wrapper.v) | CPU 指令/数据、AI、视觉 DMA 四个 AXI 主设备仲裁；跨至 HMIC/DDR 时钟域。厂商生成的 HMIC/DDR IP 位于 `ip/`。 |
| Ethernet | [`rtl/ethernet/soc/ethernet_soc_subsystem.sv`](../rtl/ethernet/soc/ethernet_soc_subsystem.sv)、[`rtl/ethernet/soc/ethernet_soc_dma_link.sv`](../rtl/ethernet/soc/ethernet_soc_dma_link.sv) | RGMII PHY、MAC、UDP 命令邮箱、SoC 控制与 DMA 链接；底层开源依赖位于 `third_party/verilog-ethernet/`。 |
| 视觉与相机预留 | [`rtl/vision/vision_pipeline_top.sv`](../rtl/vision/vision_pipeline_top.sv)、[`rtl/pgl50h_camera_dma.v`](../rtl/pgl50h_camera_dma.v) | DDR 回放/相机输入选择、灰度/resize/流处理。板级相机未接通。 |
| 固件 | [`firmware/main.c`](../firmware/main.c)、[`firmware/ultraface_runtime.c`](../firmware/ultraface_runtime.c)、[`firmware/face_events.c`](../firmware/face_events.c) | 上传协议、模型装载、AI 调度、检测框解码、检测结果之间的 IoU ID 匹配与出现/离开事件。 |
| PC 上位机 | [`pc/app.py`](../pc/app.py)、[`pc/upload.py`](../pc/upload.py)、[`pc/protocol.py`](../pc/protocol.py) | 上传模型和图像，通过 UDP 接收检测框与事件并显示。 |
| 模型 | [`assets/ultraface.ngm`](../assets/ultraface.ngm)、[`assets/manifest.json`](../assets/manifest.json) | UltraFace-Slim-320 转换后的板端模型与来源/哈希。 |

AI CSR 位于 `0x1001_0000`（另有 `0x4001_0000` 别名），Ethernet 控制寄存器位于 `0x1002_0000`（`0x4002_0000` 别名）；DDR CPU 地址窗口从 `0x8000_0000` 开始。具体寄存器布局以 RTL 和 `firmware/*.h` 为准。

## 时钟和复位

`clk_125m_p/n` 提供 125 MHz 参考。系统 PLL 生成 CPU/AXI/视觉/AI 的 `sys100`（100 MHz）与 Ethernet `net125`（125 MHz）。RGMII RX 使用 PHY 输入 `rx125`。DDR PHY 还有独立的 125 MHz/数据选通信号派生时钟。HMIC、Ethernet 异步 FIFO 使用工程内的 CDC 结构及相应约束。完整时钟、IO、CDC 和引脚约束在 [`constraints/`](../constraints/)；不要只加载 `system.fdc`。

## 当前功能边界

- 上位机按需上传图像；低频检测由上传/调度频率控制，尚无 OV7670 连续采集与自动抽帧。
- CPU 的 `face_events` 在**两次检测结果之间**按 IoU 关联 ID，连续 2 次命中报告出现、连续 3 次丢失报告离开。这不是未检测帧上的图像跟踪，也不做人员身份识别。
- `rtl/pgl50h_ai_accel_stub.v` 是未选中配置的旧桩模块；A30 的 `USE_AXI_FABRIC=1` 路径使用 `ai_accelerator_top`。
- 已有完整网络与 CPU 的仿真资格结果见 [`a30/evidence/full_network_qualification.json`](../a30/evidence/full_network_qualification.json)。该结果不等于实板 Ethernet、DDR 或模型性能签核。
