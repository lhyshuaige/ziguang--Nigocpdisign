# P3 时序复现

参考工具：PDS 2022.2-SP6.7.1，build 188940。器件 PG2L100H，-6，FBG676。

## 复查已有结果

```sh
python tools/check_timing.py
```

它解析归档的 setup / hold 摘要，并将全部非空的 setup、hold、recovery、removal、minimum pulse width slow/fast 汇总与 `reference/p3_setup25/timing_result.json` 比较。不会启动 PDS。

| 项目 | Slow | Fast |
|---|---:|---:|
| Setup 最差裕量 | +0.024 ns | +0.269 ns |
| Hold 最差裕量 | +0.138 ns | +0.040 ns |

显式 sys100 setup 为 25 ps，工具自动 PLL 项为 150 ps，实际 setup 扣减为 175 ps；hold 为 0 ps。DDR、RGMII 输入输出延时和已有 CDC 约束都随包保存。此结论覆盖已约束路径，Flash 外部 SPI AC 与全板电气签核另行进行。

## 在相同布线数据库上重新运行 STA

精确参考数据库压缩存放在 `reference/p3_setup25/routed_db.zip`，SHA-256 和解压后文件哈希见同目录 `database.json`。这是包含 Flash 输入复用 LUT 修正与 setup25 预算的最终数据库。

```powershell
# 仅校验、解压数据库并生成 TCL，不执行 PDS：
python tools/pds_flow.py sta

# 真正运行；将路径替换为本机已安装 PDS 的 bin 目录：
python tools/pds_flow.py sta --run --pds-bin 'C:\PDS\bin'
```

原生 TCL 的核心步骤是 `set_arch` 后分别以 `-delay_type max`、`-delay_type min` 执行 `report_timing`。保留多角分析、3000 条路径输出、IO datasheet、max skew 和 exception 报告。结果位于 `build/p3_reference_sta/`，脚本完成后自动比较汇总。

已有运行日志时脚本拒绝覆盖；下一次使用 `--work build/sta_run_02`。数据库文件自身不能修正或替换后继续沿用原哈希。

原始逐路径报告超过 500 MB，不随仓库复制。仓库保留摘要、签核结果、约束改动证明和实际数据库；上述命令可以重新生成完整报告。路径审计记录证明预算调整没有改变原逻辑、位置、打包或布线。

## 从 RTL 开始新实现

```powershell
python tools/pds_flow.py prepare --use-reference-placement
```

打开生成的 `build/p3_source/Nigo_P3.pds`。源文件清单在 `pds/sources.json`，模板没有历史综合/布线输出路径。准备脚本将 Boot ROM 文件定位到本仓库，避免 PDS 工作目录变化造成找不到 `.hex`。

`--use-reference-placement` 带入 `constraints/frozen_sites.pcf` 的显式位置约束；未加此参数时不加载这份参考 PCF。新的 PNR 配置保留多角优化、Hold 修复、跨 SRB 阈值 50 和最大 Hold 路径数 50000。它不会复用不存在的中间 placement 数据库。

参考设计经历过局部位置修复和最终路由数据库 LUT INIT ECO。重新综合可能改变打包、对象名和路由，因此即使使用同一 RTL、FDC、PCF，也不承诺复现相同裕量。新实现应先审计 PCF 匹配，再做完整 STA；当前签核只对应所附精确数据库。

## 用参考数据库生成位流

```powershell
python tools/pds_flow.py bitstream --run --pds-bin 'C:\PDS\bin'
```

本步骤只生成配置文件，不执行 JTAG 或 Flash 下载。`.bin` 应与 `release/fpga/pg2l100h_soc_p3_top.bin` 比较；`.sbit` 头中时间信息可能不同。用户选择的 setup25 只改变 STA 预算，参考 `.bin` 与原 setup50 物理配置完全相同。

本次仓库整理仅验证文件引用、数据库哈希、已有摘要和固件构建，没有补跑 FPGA 综合、布局布线或 STA。
