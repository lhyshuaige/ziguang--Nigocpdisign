# AXI4 SoC 验证记录

## 当前 RTL 证据

| 测试 | 结果 | 关键观测 |
|---|---|---|
| CPU native→AXI adapter | PASS | 64-byte line 拆成 2×256-bit beat，ID/last/strobe/backpressure 正确；同时验证 DDR-relative `0x0` 归一化到 `0x8000_0000`；515 ns |
| AXI4→HMIC adapter | PASS | burst 拆分、HMIC 地址右移 3、读 holding、写完成响应、越界/非对齐 DECERR；255 ns |
| 四主 AXI fabric | PASS | 4 主争用、严格下游 AR=4、CPU 两拍 burst gap=1 cycle、写 B 路由；连续压力 AR=21/21/21/21、R=20/20/20/20、max_wait=18/18/18/18；4 us |
| CSR/IRQ fabric | PASS | GPIO/keys、QSPI、AI、DMA、legacy alias、byte strobe、DECERR、sticky clear、busy 写保护；590 ns |
| INT8 AI engine | PASS | 2-beat signed INT8 dot-product、Q8.8 scale（含 zero-scale）、AXI backpressure、结果回写、非法 descriptor error IRQ；550 ns |
| Camera/DMA | PASS | 2-beat memory-to-memory burst、FIFO、backpressure、数据顺序、非法 descriptor；200 ns |
| CPU→新 Fabric→HMIC | PASS | `USE_AXI_FABRIC=1` 下同一 boot/refill 程序，229 cycles、8 次 HMIC read、CPU memory response errors=0 |
| AI/DMA integrated contention | PASS | CSR 启动两引擎并发争用，AR=4、AW=3、AI max wait=9、DMA max wait=4；535 ns |

## CPU 路径对照

同一 `pgl50h_soc_ddr_path_tb` 行为模型下，旧 native bridge 记录 221 cycles，新
`USE_AXI_FABRIC=1` 记录 229 cycles，CPU memory response errors 为 0。HMIC 读地址
周期如下：

| 路径 | HMIC AR 周期（8 beats） | 同一 64B refill 内 beat gap | 总周期 |
|---|---|---:|---:|
| 旧 native bridge | 140, 147, 159, 166, 177, 184, 202, 209 | 7 | 221 |
| 四主 AXI fabric（fast path） | 142, 146, 163, 167, 183, 187, 210, 214 | 4 | 229 |

Fabric 的注册边界将每个独立 64B refill 的起始点推迟约 2 个系统时钟，累计为
8 个周期；同一 burst 内的 beat gap 反而从 7 降为 4。这个 directed workload 仍
不是 CoreMark 结论；真实 CoreMark 仍需在同一 DDR3 training、同一时钟和同一 firmware
下测量 UART/mtime。

## 约束和未完成项

- RTL 目标时钟为 100 MHz；当前环境没有可调用的 PDS 综合/布局布线工具，不能把
  100 MHz 说成已收敛。板级 PDS 工程应同时加载 `constraints/pgl50h_soc_timing.fdc`
  和生成 DDR3 IP 的 `ip/ddr3/pnr/ddr_test.fdc`。
- 没有真实板卡，因此 `ddr_init_done`、PHY training、PLL lock 只获得行为级/接口级
  证据，尚未获得 Bank3 DDR3 的板级证据。
- 当前回归已经证明 CPU-only refill 的每次新增 Fabric 边界开销约为 2 个系统时钟，
  但尚未证明 CoreMark 下降不超过 10%；`CoreMark/MHz` 仍不能由上述 229/221 数字
  推算。
- 连续四主机压力窗口观测到每个 master 的 `perf_max_wait=18`，并且四个 master
  都持续获得响应；这是 directed fairness evidence，不替代 PDS 时序报告或形式化
  的所有流量组合证明。
- Camera stream 端口已经预留，当前 DMA 骨架执行 DDR memory-to-memory；真实摄像头
  PHY、YOLO 层级算子和完整 QSPI controller 留在后续板级迭代。
