# NaxRiscv 最高性能比赛配置备份

此目录是 `Issue24/ROB32` 比赛配置的 Verilog 副本，来源于：

`D:/PDS/project/NaxRiscv/generated/contest_sweep/iq24_rob32`

## 文件

- `rtl/NaxRiscvContest.v`：用于仿真/功能验证的核心 RTL，顶层模块为 `NaxRiscvContest`。
- `rtl/NaxRiscvContestSynt.v`：用于综合和时序测试的 RTL，顶层模块为 `NaxRiscvContestSynt`。
- `rtl/RamXilinx.v`：同步 RAM 适配模块。
- `constraints/contest_timing.fdc`：100 MHz 核心时钟约束和复位 false path。
- `constraints/pgl50h_board_pins.md`：PGL50H 板卡时钟、DDR3、QSPI、按键和 LED 的管脚信号表。

## SoC 骨架

在保持 `NaxRiscvContest.v` 不变的前提下，`rtl/` 现在增加了以下板级 SoC 层：

- `pgl50h_top.v`：PGL50H 板级顶层，LED/按键、DDR3、QSPI 和扩展口端口。
- `pgl50h_clock_reset.v`：50 MHz 时钟入口、PDS PLL wrapper 边界、PLL lock + DDR init 复位门控。
- `pgl50h_soc_core.v`：CPU 原生指令/数据/外设总线适配和中断汇聚。
- `pgl50h_mem_fabric.v`：仿真/早期 bring-up 的片上 fallback memory。
- `pgl50h_csr_fabric.v`、`pgl50h_interrupt_aggregator.v`：统一 GPIO/Timer/QSPI/AI/DMA CSR 窗口和 sticky 外部中断。
- `pgl50h_peripherals.v`：旧 native peripheralBus 的兼容壳，保持既有 smoke test 地址别名。
- `pgl50h_ai_engine.v`：第一阶段 INT8 signed dot-product、4-beat 内 AXI master、结果回写和 done/error IRQ。
- `pgl50h_camera_dma.v`：第一阶段 memory-to-memory Camera/DMA master，固定 4-beat 上限并预留 camera stream。
- `pgl50h_cpu_axi_adapter.v`、`pgl50h_axi4_mem_fabric.v`、`pgl50h_axi4_hmic_adapter.v`、`pgl50h_ddr3_boundary.v`：CPU native→AXI、四主 AXI4 仲裁、HMIC 边界与板级 DDR3 管脚边界；CPU-only fast path 将每个独立 64B refill 的新增边界开销压到约 2 个系统时钟。
- `pgl50h_native_axi_bridge.v`：CPU native I/D 请求到 HMIC 256-bit AXI 用户口的适配器。指令/数据 cache 的 64-byte line 被拆成两个 256-bit HMIC beat，写请求按 64-bit lane 生成字节 strobe。
- `pgl50h_pds_ddr3_wrapper.v`：固定为 PGL50H Bank3、DDR3 x32、15/10/3 行列 bank、800 MT/s 的 HMIC 实例包装。
- `rtl/pgl50h_soc.f`：默认 RTL/Verilator 源文件顺序；`rtl/pgl50h_soc_pds.f` 是真实 PDS 工程的入口模板。

默认 RTL 构建不依赖 PDS 原语：PLL 使用仿真旁路，DDR3 boundary 的 `init_done` 置高，CPU 先访问 `0x8000_0000` 映射的 fallback memory。真实板级构建定义 `PGL50H_USE_PDS_PLL` 与 `PGL50H_USE_PDS_DDR3`，并把 `ip/pll` 生成的 PLL、`ip/ddr3/pnr/pgl50h_hmic_ddr3.pds` 以及 `rtl/pgl50h_soc_pds.f` 加入 PDS 工程。

真实 DDR 构建时 SoC 时钟选择 HMIC 输出的 `ddrphy_clkin`，因此 CPU native bridge 与 DDR3 AXI user port 不跨异步时钟域；独立的 50→100 MHz PLL 仍用于非 DDR/bring-up 时钟入口和 lock 门控。定义 `PGL50H_USE_AXI_FABRIC`（或将 `USE_AXI_FABRIC=1`）即可启用 CPU I/D adapter、四主 AXI fabric、HMIC adapter、INT8 engine、Camera/DMA 和 IRQ aggregator；未定义时保留旧 direct/fallback 回归路径。

当前 RTL 已有以下端到端行为证据：CPU→Fabric→HMIC 取指/数据路径、AI/DMA 同时争用及 CSR/IRQ 均通过 Verilator 回归。AI 第一阶段的输入约定是交错 signed INT8 对 `(a0,b0,a1,b1,...)`，每个 descriptor 最多 128 bytes（4 个 256-bit beat），结果为 Q8.8 scale 后的 signed 32-bit 写回值。详细周期、HMIC 地址和未完成的板级验证见 `docs/axi_fabric_validation.md` 与 `docs/coremark_ddr3_validation.md`。

## 已知基线表现

- 配置：Issue24 / ROB32
- CoreMark：约 4.76 CoreMark/MHz
- CoreMark 迭代周期：2,100,965
- PGL50H PDS 后 PNR：约 96.93 MHz
- 资源：约 12,148 LUT、7,598 FF、35.5 DRM18K、4 APM
- 基线 PNR 时序：WNS 约 -0.317 ns

修改后先用 Verilator 做桥接/SoC 回归，再用 PDS 做综合和布局布线对比。当前可复现的 CoreMark 基线是 fallback memory 上约 4.76 CoreMark/MHz（2,100,965 cycles）；DDR3 版本必须在完成训练并上板运行同一 `coremark.memh` 后，用 UART/mtime 记录 cycles，再与该基线比较。
