# PGL50H SoC 基线工程使用说明

本文档对应 `D:\PDS\project\Nigo`，用于队友查看、仿真和复现当前 SoC 基线。

## 1. 基线信息

- FPGA：PGL50H / FBG484 / Speed Grade -6
- PDS：2022.2-SP6.7.1
- 顶层：`pgl50h_top`
- `pll_clk_sys`：100 MHz，10 ns
- `ddrphy_clkin`：100 MHz
- 活动 CPU RTL：`rtl/NaxRiscvContest.v`
- CPU RTL SHA-256：`B88BBD0AA5F60B591BDC3C60D8D70C0AD1720F095A20DC1C1F9AE5C1C7FA3262`

参考 P&R 数据库的 setup WNS：`pll_clk_sys = -0.017 ns`，`ddrphy_clkin = +1.815 ns`。完整报告在 `pds_baseline/pds/pgl50h_hmic_cdc_reset_20261007/`。该结果是 PDS 基线证据，不等同于真实板卡 DDR 训练或上板 CoreMark 结果。

## 2. 目录说明

- `rtl/`：活动 CPU、SoC、AXI、AI、DMA、时钟/复位和 DDR 边界 RTL；`pgl50h_soc.f` 是仿真源表，`pgl50h_soc_pds.f` 是 PDS 源表。
- `ip/`：PDS PLL 和 Bank3、32-bit DDR3 HMIC 生成文件。
- `constraints/`：顶层管脚、SoC 时钟和 HMIC 基线约束。
- `tb/`：CPU、AXI、DDR、AI、DMA 和 SoC 测试平台。
- `sim/coremark_soc/`：CoreMark 镜像、运行脚本和基线日志。
- `pds_baseline/`：基线 PDS 工程、综合/布局布线数据库和报告。
- `modular/`：模块接口合同、区域约束和层次化流程脚本。
- `docs/`：验证、时序和模块化流程记录。

活动 CPU 只认 `rtl/NaxRiscvContest.v`；候选版 RTL 没有放进活动目录。

## 3. CoreMark 仿真

现有脚本 `sim/coremark_soc/run_coremark_soc_verilator.ps1` 依赖：

```text
D:\PDS\Verilator\bin\verilator.exe
D:\PDS\w64devkit\w64devkit\bin\make.exe
D:\PDS\project\NaxRiscv\ext\NaxSoftware\baremetal\coremark\build\rv32im\coremark.elf
D:\PDS\project\NaxRiscv\pds\pgl50h\coremark_sim\elf32_to_hex.py
```

若工具链路径不同，先修改脚本中的路径；也可以使用已整理好的 `sim/coremark_soc/coremark.memh`，跳过 ELF 转换步骤。

运行命令：

```powershell
Set-Location D:\PDS\project\Nigo\sim\coremark_soc
PowerShell -ExecutionPolicy Bypass -File .\run_coremark_soc_verilator.ps1 -TimeoutCycles 50000000
```

日志写入 `sim/coremark_soc/coremark_soc_verilator.log`。建议顺序为：模块测试 → AXI/DDR/IRQ 回归 → SoC CoreMark → PDS。

常用测试平台包括：`tb/pgl50h_cpu_axi_adapter_tb.v`、`tb/pgl50h_axi4_mem_fabric_tb.v`、`tb/pgl50h_axi4_hmic_adapter_tb.v`、`tb/pgl50h_ddr_cdc_reset_tb.v`、`tb/pgl50h_ai_engine_tb.v`、`tb/pgl50h_camera_dma_tb.v`、`tb/pgl50h_csr_irq_tb.v` 和 `tb/pgl50h_soc_coremark_tb.v`。

## 4. PDS 基线查看

重点文件：

```text
pds_baseline/pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_top_setup.rtr
pds_baseline/pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_top_hold.rtr
pds_baseline/pds/pgl50h_hmic_cdc_reset_20261007/flow.log
pds_baseline/pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_soc_hmic_clockgroup_PGL50H.pds
```

快速检索报告：

```powershell
Select-String -Path D:\PDS\project\Nigo\pds_baseline\pds\pgl50h_hmic_cdc_reset_20261007\pgl50h_top_setup.rtr -Pattern 'pll_clk_sys|ddrphy_clkin|WNS'
```

推荐用 PDS GUI 打开：

```text
pds_baseline/pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_soc_hmic_clockgroup_PGL50H.pds
```

命令行重跑的核心顺序为：

```tcl
open_project {D:/PDS/project/Nigo/pds_baseline/pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_soc_hmic_clockgroup_PGL50H.pds}
compile -force_to_run -top_module {pgl50h_top}
synthesize -force_to_run -ads -selected_syn_tool_opt 2
dev_map -force_to_run
pnr -force_to_run -optimize_multi_corner_timing -fix_hold_violation -report_timing
report_timing -force_to_run -delay_type {max} -max_path 20000 -slack_less_than 0
report_timing -force_to_run -delay_type {min} -max_path 20000 -slack_less_than 0
```

快照中的部分 Tcl 仍保留原 `NAX` 绝对路径，重新运行前必须改成 `D:/PDS/project/Nigo/...`。真实板级构建要定义 `PGL50H_USE_PDS_PLL` 和 `PGL50H_USE_PDS_DDR3`，并使用 `ip/pll/`、`ip/ddr3/`、`rtl/pgl50h_soc_pds.f` 及官方 HMIC 约束；不要把仿真旁路定义用于真实 DDR。

## 5. 约束与模块化流程

推荐约束顺序：

1. `constraints/pgl50h_top_pins.fdc`：板级管脚和时钟；
2. `constraints/pgl50h_soc_timing.fdc`：系统/DDR 时钟、复位和 CDC；
3. `constraints/pgl50h_hmic_soc.fdc`：SoC/HMIC 关系；
4. PDS HMIC IP 官方 RCF/PCF/FDC；
5. `modular/constraints/20_module_timing_budget.fdc`、`30_regions_seed.pcf`：模块化试验；
6. 精确实例 site lock：只有在父数据库导出并核对真实 site 名称后才能加入。

模块化迭代应保存父设计的 map、placement、routed `.adf`，修改 AI/DMA/AXI 后使用父 placement DB 做增量 P&R，并比较 CPU、HMIC、时钟树、setup/hold 和路径簇。区域种子不是模块 checkpoint，内部 ADIF `SITEREF (x y)` 也不能直接当作 `def_inst_site`。

`modular/scripts/` 中的模板仍含原工程绝对路径，使用前需要重定位到 Nigo。

## 6. 已知限制

- 无真实板卡时，DDR3 training、UART、实际 Fmax 和上板 CoreMark 不能由仿真替代；
- BootROM/程序加载器尚未独立实现，仿真使用 CoreMark 镜像；
- AI 当前是第一阶段 INT8 MAC/AXI 版本，不是完整 YOLO/NPU；
- Camera/DMA 仍是 memory-to-memory 和预留像素流接口，真实 camera PHY/ISP 尚未接入；
- 当前 signoff 数字以 `BASELINE_MANIFEST.md` 和 `pds_baseline` 报告为准，根目录旧 README 中的历史 WNS 不作为当前基线。

## 7. 修改前检查

```text
[ ] 只修改目标模块及接口
[ ] 模块级测试通过
[ ] SoC CoreMark 回归通过
[ ] 未切换 NaxRiscvContest.v 活动版本
[ ] 未覆盖官方 HMIC 约束
[ ] setup 和 hold 均重新报告
[ ] 检查 CPU/AI/DMA/AXI/HMIC 路径簇和实例移动
[ ] 新 PDS 数据库另存为带日期的快照
```

基线包不应直接覆盖；新的实验应建立新日期目录，并保留 `-0.017 ns` 版本用于回退和比较。
