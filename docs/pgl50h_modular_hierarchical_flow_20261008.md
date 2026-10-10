# PGL50H SoC 模块化、层次化和物理复用流程

## 结论先行

`pgl50h_soc` 可以按层次化 RTL 和物理区域方式组织，但 PDS 2022.2-SP6.7.1 在本工程中没有表现出可把 CPU/AI/DDR 各自完成 P&R 后像 Vivado DCP 一样拼入 PGL50H 顶层的通用模块 checkpoint 接口。当前可验证、可复现的复用单位是：

* RTL/IP 源文件和固定模块边界；
* PDS 映射数据库 `.adf`；
* 父设计 placement 数据库 `.adf`，通过 `pnr -input_db_file ... -input_place_db_file ...` 继续实现；
* `def_region`、`def_inst_region` 和经过验证的 `def_inst_site` 约束；
* PDS HMIC 官方生成的 DDR 约束和数据库。

因此目标流程要分成“模块逻辑收敛”和“父上下文物理收敛”。模块的独立频率结果是筛选和资源分析结果，最终频率以带父上下文、时钟树、CDC、区域和邻接资源的 SoC P&R 报告为准。

## 推荐 hierarchy

```text
pgl50h_top
├── u_clock_reset
│   ├── u_pll_50m_to_100m                 -> pll_clk_sys
│   └── u_ddr_reset_sync                  -> ddrphy_clkin reset
├── u_soc_core
│   ├── u_cpu_partition
│   │   ├── NaxRiscvContest               -> 2-wide OoO CPU
│   │   ├── u_cpu_axi_adapter             -> I/D AXI4 boundary registers
│   │   └── u_cpu_csr_boundary
│   ├── u_ai_partition
│   │   ├── u_ai_csr_axi_lite
│   │   └── u_int8_mac_engine
│   ├── u_dma_partition
│   │   ├── u_dma_csr_axi_lite
│   │   └── u_camera_dma
│   ├── u_peripheral_partition
│   │   ├── u_uart / u_timer / u_gpio / u_qspi / u_ethernet
│   │   └── u_interrupt_aggregator
│   ├── u_axi_fabric_partition
│   │   ├── CPU I master
│   │   ├── CPU D master
│   │   ├── AI master
│   │   ├── DMA master
│   │   └── u_axi_memory_arbiter_qos
│   └── u_axi_hmic_cdc
└── u_ddr3
    └── u_pds_ddr3/u_hmic                 -> official PGL50H HMIC hierarchy
```

现有 RTL 中 `pgl50h_soc_core` 已经包含这些逻辑，但 CPU、AI、DMA、fabric 还应把边界寄存器和层次名字固定下来。重构时先保持端口行为和时延，再把实例搬进上述 wrapper；不要在同一个提交里同时改 CPU 微架构、AXI 协议和物理层次。

## 模块划分和接口

接口的完整方向、宽度和时钟见 [interface_contract.md](../modular/interface_contract.md)。关键原则是：

* CPU、AI、DMA、fabric 使用 `pll_clk_sys`；
* DDR 只使用 `ddrphy_clkin` 和官方 HMIC 复位/训练网络；
* CPU 分区边界放在 CPU adapter 的 AXI4 端口，而不是把 RF、ROB 或旁路网拆成跨分区端口；
* AI/DMA 的控制寄存器归各自分区，SoC CSR fabric 通过 AXI4-Lite 访问；
* AXI ID、burst 长度、`valid/ready` 和 response 必须在边界保持完整，不能只锁数据线；
* 所有边界信号打一层寄存器，避免跨 region 的组合 ready/valid 链。

## 模块级验证

### CPU

使用 `NaxRiscvContest` 加 CPU boundary wrapper 作为模块 top，使用真实 100 MHz `pll_clk_sys`、真实 I/D AXI handshake 和 CSR/IRQ 端口。先做编译、综合、dev_map、资源统计，再做带 CPU region 的 placement timing。CoreMark、分支恢复、load/store、除法和 AXI back-pressure 作为功能门槛。当前 SoC-context 参考是 CPU setup WNS `-0.006 ns`，不能把 standalone shell 的 placement-only 正 slack 当成 CPU signoff。

### AI

使用 AXI4-Lite CSR BFM 和 AXI4 memory BFM，验证 INT8 MAC pipeline、burst 对齐、scale/channels、done/error IRQ。资源报告至少记录 LUT/FF/BRAM/DRM/APM、最大扇出和 AXI boundary registers。AI 的 parent-context 负路径曾是全局 -0.017 ns 参考中的主要非 CPU 风险，因此 AI 变化必须走父 placement 增量流程。

### DDR

保持 PDS HMIC 生成工程独立验证。只接受官方 Bank、CA、DQS、时钟、训练和 reset 约束；SoC 侧只验证 AXI mailbox、CDC 和 `init_done` 顺序。不能把 DDR PHY 的内部路径混入 CPU/AI 的模块预算。

## Physical partition

第一轮不要直接从当前混合布局的 bbox 生成 exclusive region。当前父数据库的 CPU、AI、DMA 和 fabric 网格范围相互重叠，说明它是一个全局优化结果，不能直接当成已经分区的物理 floorplan。应执行一次“region seed”实现：

1. 保留 HMIC 官方约束和 DDR 资源；
2. 为 CPU、AI、DMA、fabric 规划互不重叠的 tile region；
3. 用 `def_region` 和 `def_inst_region` 绑定分区顶层或稳定的资源集合；
4. 运行完整父 P&R，检查每个 region 的使用率、跨区 net、时钟树和边界 slack；
5. 通过后才把 `30_regions_seed.pcf` 中的占位坐标替换成正式坐标。

Region 是物理边界约束，不会自动生成模块 checkpoint。CPU 的 RF/ALU/divider 局部 region 可以作为 region 内微调，但不能替代 CPU 整体边界。

## Timing budget

以 100 MHz、10 ns 周期为合同起点，先给每个 compute partition 8.0 ns 的可见边界到边界预算，保留约 0.2 ns 时钟不确定度和约 0.8 ns 父互连/边界余量。fabric 的预算可先设 7.8 ns，因为它承接四路 master 仲裁。最终预算必须由实际边界寄存器层次替换模板中的 endpoint 后再启用。所有 max-delay 约束保持可见；CDC 只排除同步器的合法路径。

## PDS 能力判断

| 能力 | PDS 2022.2-SP6.7.1 在本工程的结论 | 使用方式 |
|---|---|---|
| RTL hierarchy | 支持 | 固定 wrapper 层次和端口，完整顶层 compile |
| OOC synthesis | 可仿真式实现，不是独立物理签核接口 | 模块 top 单独 compile/synthesize/dev_map，结果用于逻辑/资源/预算 |
| module P&R checkpoint 拼接 | 未发现通用接口 | 不把独立 `.adf` 当成可拼接模块 checkpoint |
| parent placement reuse | 支持 | `pnr -input_db_file` + `-input_place_db_file` |
| exact placement preservation | 支持单实例约束 | `def_inst_site`，必须有真实 SITE/SYMBOL 映射并逐项验证 |
| soft physical partition | 支持 | `def_region` + `def_inst_region` |
| incremental compile | 支持父数据库增量 P&R | 适合 AI/DMA/AXI 变化时复用父 placement；不能自动保证 CPU-only freeze |
| Partition Definition/PR | 安装手册列为局部动态重配置，支持器件清单不含 PGL50H | 不作为本 SoC 的模块拼接方案 |

## 数据库管理

每个实现候选使用不可变目录：

```text
pds/<candidate>/
├── source_manifest.sha256
├── constraints_snapshot/
├── compile/
├── synthesize/
├── device_map/<top>_map.adf
├── place_route/<top>_plc.adf
├── place_route/<top>_pnr.adf
├── report_timing/
└── run.log
```

候选命名使用 `baseline_m0017`、`ai_m0001`、`dma_m0001` 等，不覆盖父目录。每个目录保存 RTL/constraint/IP 的 hash、PDS 版本、器件、seed、输入 map/placement DB hash、setup/hold WNS/TNS、unrouted nets 和 CoreMark 结果。父 placement DB 作为只读输入复制到候选目录后再运行。

## Tcl / script 顺序

`modular/scripts/00_capability_audit.tcl` 审计当前 PDS 命令；`10_parent_context_impl.tcl` 用于完整父实现；`20_reuse_parent_placement.tcl` 用于模块变化后的增量 P&R；`30_lock_validation.tcl` 只允许已经通过 exact-site 验收的 lock PCF；`40_module_change_flow.ps1` 是 AI/DMA/AXI 变化的外层入口。

## SoC 集成验收

集成候选必须同时满足：RTL hierarchy 和接口 hash 正确；AXI protocol、CDC/reset、DDR training 和 CoreMark 回归通过；完整父 P&R 无 unrouted net；HMIC 官方约束未被覆盖；CPU frozen-instance 清单与父数据库逐项一致；CPU 内部、CPU-to-fabric、AI/DMA/fabric 和 HMIC 各自报告分开审查；全局 setup/hold、recovery/removal、clock pulse width 都有记录。

当 exact-site 导出和单实例移动验收还没有通过时，结果只能称为“父 placement 复用”，不能称为“CPU selective lock”。
