# A0 回退与 CPU 时序重新分析（2026-10-07）

## 回退状态

- 已从 `SrcPlugin.scala` 删除 A0 的显式 32 位 full-adder/carry `Vec`。
- 当前 ALU0/ALU1 均恢复为原始表达式：

  ```scala
  ss.ADD_SUB := carryIn(ss.SRC1 + rs2Patched)
  ```

- `rtl/NaxRiscvContest.v` 未被 A0 覆盖；A0 生成文件和 PDS 工程仅保留为对照。
- 由于当前环境没有可调用的 sbt launcher，回退后的 Scala 编译未重新执行；回退是对原语句的精确恢复，生产 Verilog 仍是已验证的基线文件。

## A0 为什么退化

基线的最差路径属于已局部化的 ALU0 RF 副本：

```text
RF alu0 bank_24
  -> N3881/N3885 operand formatting
  -> ALU0 addsub/carry
  -> ALU0 ALU_RESULT
  -> EU0 RS2 mux
```

基线数据为逻辑 4.405 ns、布线 5.236 ns、WNS -0.017 ns；布线已经占 54.31%，不是单纯的加法器逻辑深度问题。

A0 PDS 中，最差路径变成：

```text
RF bank_26
  -> N4273 operand formatting
  -> ALU1 SRC2 高扇出网
  -> writeMerges_2_bypass_port_data
  -> ALU0 SRC2
```

结果是 WNS -1.464 ns、TNS -274.241 ns、862 个失败端点，估算 Fmax 87.23 MHz。该变化说明显式 Scala 位级链触发了重新综合/重聚类，破坏了基线的 RF 副本 ownership 和物理邻近关系；PDS 也没有把它实现成更短的有效专用 carry 路径。A0 因此不能作为下一轮基础。

## 基线负路径簇

基线 `pgl50h_hmic_cdc_reset_20261007` 的 `pll_clk_sys` setup WNS 为 -0.017 ns。主要端点簇为：

| 簇 | 最差量级 | 结构 |
|---|---:|---|
| RF-ALU0-EU0 | -0.017 ns | `rf_alu0 bank_24 -> ALU0 ALU_RESULT[20] -> EU0 RS2[20]` |
| RF-EU0-MUL | -0.002 ns | `rf_eu0 bank_3 -> APM MUL_VALUES[*]` |
| 其余邻近路径 | 约 0 至 -0.10 ns | RF 写端口、ALU1 operand/PC target、DataCache 地址 |

结论是：真正需要保护的是基线已经存在的 RF 副本和路径拓扑，而不是重新描述 32 位加法器。

## 重新排序后的方案

### B0：保持基线算术网表，只做物理/网表审计

先不改 `SrcPlugin.scala`。从基线报告确认每一个 `rf_alu0`、`rf_eu0` 读副本与其 consumer 的配对，并记录：

- 起点/终点和对应 bit；
- logic/route 分解；
- bypass port fanout；
- 0 ns 到 +0.10 ns 的邻近端点。

这是为了避免再次把局部路径改成全局 `bank_26 -> ALU1 -> writeMerges` 网络。

### B1：完整 payload 的 consumer-local bypass

在 `ExecutionUnitBase.scala` 与 `RegFilePlugin.scala` 中只做局部 ownership：

```text
ALU0 producer
  -> local {valid,address,data} lane
  -> EU0 RF read consumer

legacy global {valid,address,data} lane
  -> all other consumers / fallback
```

要求：

1. `valid/address/data` 必须一起复制；不能只复制 data。
2. 保留 global lane，避免跨 EU 同周期依赖失效。
3. 只改变 bypass 选择和 consumer scope，不改变 execute stage、写回延迟、ROB 或 wakeup。
4. 生成后检查 PDS 是否仍保留 `rf_alu0` 和 `rf_eu0` 的局部驱动；如果被重新合并，立即放弃该候选。

这是优先级最高的 RTL 方案，因为基线关键路径的 route 占比高，目标是减少跨副本/跨 EU 的长网，而非增加算术逻辑。

### B2：operand formatting 局部化

在 RF 输出之后、ALU 入口之前，为 ALU0、EU0、ALU1 分别建立只读的格式化线网（符号扩展、零扩展、立即数选择），但不增加寄存器、不重写加法器：

```text
rf_alu0_data -> alu0_fmt -> ALU0
rf_eu0_data  -> eu0_fmt  -> EU0
rf_alu1_data -> alu1_fmt -> ALU1
```

禁止将 `ALU1 SRC2` 或 `writeMerges_*_bypass_port_data` 作为 ALU0 的中间共享源。目标是降低高扇出和 route delay；如果综合后共享网仍存在，则该候选不进入 PDS。

### B3：仅在 B1/B2 无法达到目标时增加局部流水

只考虑执行边界的单一寄存器，不给全核加深流水：

```text
RF read / operand format -> execute-local register -> ALU/consumer
```

该方案会增加同周期依赖一拍，必须同步修改 wakeup、early bypass、load-use 和 CoreMark 参考结果；预计性能/MHz 有下降风险，因此最后采用。

## 验收门槛

每个候选都必须独立完成：

1. 生成 Verilog 与 Verilator lint；
2. SoC CoreMark，周期数不增加或明确记录增加量；
3. PDS 全流程；
4. 同时比较 setup WNS/TNS、负端点数和 `0~+0.10 ns` 临界端点；
5. WNS 不得比 -0.017 ns 基线更差，且不能出现新的跨 EU 大负簇。

## 当前结论

回退是正确动作。下一轮应从 `-0.017 ns` 基线开始，先做 B1 的完整 payload consumer-local bypass，再做 B2 的 operand formatting 局部化；不再尝试 A0 这种改变 ALU 算术网表的方案，也不立即增加流水级。
