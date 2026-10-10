# PGL50H SoC 时序负路径簇分析

## 当前结论

当前可以在没有板卡的情况下继续优化。现有 PDS 报告是 100 MHz、10 ns 约束下的综合/布局布线 STA，负 setup 路径集中在生成式 NaxRiscv 的前端、分支上下文和 ROB 提交控制；没有证据表明 AXI fabric、DDR3 HMIC 或 AI/DMA 是当前最差路径。

需要注意：`pgl50h_top_timing_summary_after_hold_fix.txt` 和 `synthesize/snr.db` 的生成时间是 2026-09-25 15:30 左右，而 SoC 适配文件在此之后还有修改，因此这些数值应视为“最近一次完整 PDS 基线”，不是最新 RTL 的最终签核结果。

## 最近一次完整 SoC PDS 基线

| 项目 | Slow setup | Slow hold | Fast setup | Fast hold |
|---|---:|---:|---:|---:|
| WNS | -1.041 ns | +0.025 ns | +1.980 ns | +0.017 ns |
| TNS | -195.645 ns | 0 | 0 | 0 |
| failing endpoints | 605 | 0 | 0 | 0 |

布局布线日志显示设计成功完成，且没有 hold violation；问题是 slow-corner setup closure。

## 负路径簇

### 1. Fetch valid -> Aligner/Decoder exception

- 综合 WNS：`-1.297 ns`
- 逻辑级数：11
- 最高扇出：316
- 数据延迟：11.181 ns
- 其中逻辑延迟：2.914 ns（26.1%）
- 其中布线延迟：8.267 ns（73.9%）
- 起点：`FetchPlugin_stages_2_to_AlignerPlugin_setup_s2m_rValid`
- 终点：`DecoderPlugin_logic_exception_trigged`

这是典型的前端 valid/ready 和译码异常组合路径。布线延迟占比接近四分之三，优先级应是降低控制信号扇出、把异常判定从长的 ready/valid 链中隔离，而不是先改 AXI。

### 2. BranchContext ptr_free -> ROB line mask（两个并列终点）

- 综合 WNS：`-1.205 ns`（两个 endpoint 相同）
- 逻辑级数：8
- 最高扇出：452
- 数据延迟：10.709 ns
- 其中逻辑延迟：2.798 ns（26.1%）
- 其中布线延迟：7.911 ns（73.9%）
- 起点：`BranchContextPlugin_logic_ptr_free[1]`
- 终点：`CommitPlugin_logic_ptr_robLineMaskRsp[1:0]_1[0/1]`

路径中可以看到 `BranchContext` 的减法/占用判断、ROB mask 生成，以及扇出 452 的 `FrontendPlugin_serialized_isForked`。该簇本质是“分支序列化控制 -> ROB 提交资格”的全局控制网。

### 3. 时钟树高扇出（不是 RTL 数据路径）

- `u_clock_reset/pll_clk` 综合报告扇出约 9425。
- P&R 已使用全局时钟缓冲，P&R 时钟利用率报告中的全局缓冲扇出约 9088。

这部分不能用普通 RTL 复制逻辑解决；应保持 PLL→全局时钟缓冲的结构，并让 PDS 的 timing-driven placement/router 处理。只有在最新 P&R 仍显示 clock insertion/skew 异常时，才考虑时钟资源约束。

## 已知的配置级结果

当前 `D:\PDS\project\NAX\rtl\NaxRiscvContest.v` 与 `generated/contest_sweep/iq24_rob32/NaxRiscvContest.v` 相同，SoC 当前已经使用 Issue24/ROB32 配置，不需要再次切换到该配置。

独立 core-only sweep 表明：Issue24/ROB32 比 Issue16/ROB32 的估计 Fmax 从 93.46 MHz 提升到 96.93 MHz，CoreMark/MHz 从 4.72 提升到 4.76；ROB48 会把时序降到约 89--90 MHz。因此当前应保留 ROB32，继续针对上述两个控制簇优化。

## 优化顺序

1. 先重新生成最新 SoC PDS 基线，确认适配器/CSR/AXI 的后续改动没有改变路径排名。
2. 针对 Fetch→Decoder 簇，减少 `isForked`、fetch valid、ready/exception 控制的跨模块扇出；必要时增加一个前端控制寄存器边界，但不改变架构可见行为。
3. 针对 BranchContext→ROB 簇，局部复制/寄存 `serialized_isForked`，并把 branch pointer occupancy/ROB mask 的组合比较限制在本地扇出域。
4. 保持 AXI fabric、DDR adapter、AI/DMA 结构不动，除非最新报告把它们列入 top-N path。
5. 每个候选版本同时跑 PDS slow/fast setup/hold 和 SoC CoreMark；不能只看 WNS，因为当前 hold 裕量已经很小（slow +0.025 ns）。

## 签核边界

本环境目前没有可调用的 PDS 编译器命令，因此尚不能把本文件的分析冒充为最新 RTL 的重新布局布线结果。新的数值必须在 PDS 重新运行后更新；现有结果适合指导优化方向和做相对比较。

## 按紫光资料修正后的实施方案

紫光同创的 PGL/Logos 数据手册说明，器件提供区域化全局时钟、区域时钟和高速 IO 时钟；PGL50H 具备 5 个 PLL，且专用时钟输入/输出脚用于避免普通布线资源、改善时钟性能。当前 `clk_50m -> PLL -> 全局时钟缓冲` 的方向是正确的，不应把系统时钟改成普通逻辑布线。

PGL50H 的 HMIC_S 指南明确支持 PGL50H 的 FBG484/MBG324/MBG484 封装、DDR3 x32，DDR3 最高 800 Mbps、Burst Length 8。该指南同时要求：

1. 约束 `ref_clk`、`ddrphy_clkin` 和高速 `ioclk`；
2. 使用 HMIC 生成的 IO/位置约束，不能随意改动硬核相关位置；
3. DDR3 使用 1.5 V、SSTL15，DQS 为差分 SSTL15D，DQ/DQS 端接按 IP 建议配置；
4. 如果工程需要优先布线，必须把 IP 生成目录中的 `.rcf` 路由约束加载进自建 PDS 工程。

因此当前方案分成两层：

### A. 无板卡阶段：先收敛核心 100 MHz 时序

- 保留 Issue24/ROB32；
- 只针对 Fetch→Decoder 和 BranchContext→ROB 两个负路径簇做 RTL/生成器实验；
- 对 `FrontendPlugin_serialized_isForked` 做局部扇出隔离，对 BranchContext occupancy/full 判断做保守的时序版本；
- PDS 保持 slow/fast multi-corner timing、hold fixing 和全局时钟资源；
- 用 CoreMark 和 SoC DDR-path 仿真检查额外寄存器是否引入性能/协议回归。

### B. 真实 HMIC/板级阶段：再收敛 DDR 和 IO 时序

- 将 `ip/ddr3/pnr` 生成的时钟约束、Bank3 IO 约束和 `.rcf` 优先路由约束并入板级 PDS 工程；
- 把 HMIC 的 `ref_clk` 约束映射到当前顶层 `clk_50m`，把 `ddrphy_clkin` 和 `ioclk` 约束映射到实际实例层级；
- 不把当前 logic-only stub 的 WNS 当成 DDR PHY 签核结果；
- 重新检查 `ddr_init_done` 之后 CPU/AXI 才访问 DDR 的复位释放时序。

## 预期改善（工程估算，不是保证值）

| 阶段 | 主要动作 | 预期结果 |
|---|---|---|
| P&R 策略/seed | 在现有时序驱动 P&R 上做多 seed 比较 | 通常只能改善约 0.1–0.3 ns，不能解决结构性高扇出 |
| RTL 高扇出隔离 | 优化 `isForked`、fetch valid、BranchContext 控制网 | 关键簇路由延迟目标下降 15–30%，约释放 0.4–1.0 ns 的路径裕量 |
| 前端/ROB 局部寄存化 | 在不改变 ISA 的前提下增加控制边界 | 目标是把 Slow setup WNS 从约 -1.0 ns 推到 -0.3 ns 附近；需重新测 CoreMark |
| HMIC FDC + RCF 完整接入 | 正确约束 DDR PHY/IO/优先布线 | 消除“未约束/错误约束”的假象，得到可信 DDR/IO 时序；不直接等价于 CPU WNS 改善 |
| 综合/布局签核 | 最新 RTL 全 SoC 重跑 PDS | 最终以 WNS/TNS、hold、generated clock 覆盖率和 DDR training 通过为准 |

这里的 0.4–1.0 ns 是基于当前负路径中约 74% 为 route delay 的工程目标区间，不是紫光官方保证值；真实收益取决于 PDS 版本、seed、拥塞和新 RTL 的逻辑映射。
