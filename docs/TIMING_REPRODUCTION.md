# A30 时序验证与复现

## 1. A30 测量结果

器件 `PG2L100H-6IFBG676`，PDS `2022.2-SP6.7.1`。A30 是 SoC+Ethernet+AI 的物理实现，不是独立 AI 模块的 STA。

| 检查 | 慢角 | 快角 |
| --- | ---: | ---: |
| Setup 最差余量 | +0.146 ns，0 违例 | +0.269 ns，0 违例 |
| Hold 最差余量 | +0.049 ns，0 违例 | **−0.033 ns，5 个端点** |
| Hold TNS | 0 | −0.110 ns |

DDR 相关时钟组、RGMII TX 以及已报告的 recovery/removal 约束通过。**整机 hold 尚未签核。** 精简证据位于 [`a30/evidence/`](../a30/evidence/)；`all_negative_paths.json` 含 5 个快角失败端点，`all_clock_groups.json` 含全部时钟组摘要。

## 2. 只核对仓库中的 A30 证据（不调用 PDS）

在仓库根目录运行：

```powershell
python -B verify_package.py
python -B tools/check_timing.py --expect-a30
```

第一条检查复制包中每个文件的 SHA256。第二条重新解析保存的 setup/hold 摘要，检查四个角的最差余量和违例端点数，并核对 5 个负余量路径。这只能验证**保存的证据和复制完整性**，不会重新计算网表延时。

## 3. 对原生 A30 布线数据库重新运行独立 STA

精确重算需要 A30 的 `soc_physical.pds` 和 `place_route/pg2l100h_soc_top_pnr.adf`。二进制数据库没有放进此源码包；它含本机工程元数据且较大。75 个厂商 IP 输入已补入 `ip/`。本机原始 A30 运行目录仍在 `D:\PDS\project\Nigo-LG100\build\mes2l676_soc_ai_ultraface_20261027_a30_targeted_hold_on`。`tools/make_sta_tcl.py` 会先核对该 routed DB 的 SHA256 是否为 A30 的 `fd5e0f60...5b4cb85f8`，然后只生成 Tcl，不执行工具。

以下命令供**以后需要独立重算时**使用；当前复制任务没有运行它们：

```powershell
$Repo = 'D:\PDS\project\Nigo-2'
$NativeRun = 'D:\PDS\project\Nigo-LG100\build\mes2l676_soc_ai_ultraface_20261027_a30_targeted_hold_on'
$Out = Join-Path $Repo 'out\a30_sta'
$PdsShell = 'D:\PDS\PDSAPP\PDS_2022.2-SP6.7.1\PDS_2022\PDS_2022.2-SP6.7.1-ads\bin\pds_shell.exe'

python -B (Join-Path $Repo 'tools\make_sta_tcl.py') --native-run $NativeRun --out $Out
$p = Start-Process -FilePath $PdsShell -WorkingDirectory $NativeRun -WindowStyle Hidden -PassThru -Wait `
  -RedirectStandardInput (Join-Path $Out 'independent_sta.tcl') `
  -RedirectStandardOutput (Join-Path $Out 'pds_stdout.log') `
  -RedirectStandardError (Join-Path $Out 'pds_stderr.log')
if ($p.ExitCode -ne 0 -or -not (Select-String -LiteralPath (Join-Path $Out 'pds_stdout.log') -Pattern 'INDEPENDENT_STA_DONE' -Quiet)) {
  throw 'PDS independent STA did not complete'
}
python -B (Join-Path $Repo 'tools\check_timing.py') `
  --setup (Join-Path $Out 'setup.rtr') --hold (Join-Path $Out 'hold.rtr') --expect-a30
```

Tcl 对**同一布线 DB**分别执行 `-delay_type max -max_path 1000` 和 `-delay_type min -max_path 10000`，并输出完整的 `setup.rtr`、`hold.rtr`。PDS 仍会改写原生运行目录的 `report_timing/pg2l100h_soc_top.rtr` 临时报告；已归档的精简证据和布线 DB 不因此改写。`out/` 已由 `.gitignore` 排除。若要检查别的 routed DB，生成 Tcl 时加 `--allow-other-db`，并**不要**加 `check_timing.py` 的 `--expect-a30`。

## 4. 从当前源码重新综合、布局布线

1. 安装相同版本的 PDS 和器件支持。运行 `python -B verify_package.py`，逐个核对 75 个 `ip/` 文件及其余 A30 输入的 SHA256。厂商 IP 的再分发权限说明见 [`THIRD_PARTY.md`](../THIRD_PARTY.md)。
2. 在新的 PDS 工程选 `PG2L100H-6IFBG676`，顶层设为 `pg2l100h_soc_top`。按 [`a30/project_sources.json`](../a30/project_sources.json) 的 `mapped_inputs` 数组顺序加入全部 184 个源码/约束输入。6 个 `.fdc` 均在 [`constraints/`](../constraints/)：`ddr`、`pins`、`system`、`ethernet_timing`、`cdc`、`ethernet_cdc`。从仓库根目录运行 PDS，以便 `firmware/build/boot64.hex` 的相对路径可解析。
3. 执行 compile、synthesize、device map 和 placement。路由选项与 A30 一致：`-optimize_multi_corner_timing -slack_prior_in_global_router TRUE -fix_hold_violation -max_hold_violated_paths_num 50000 -fix_hold_violation_in_route TRUE -fix_hold_violation_threshold_for_clk_tree 100 -fix_hold_violation_threshold_for_clock_path_cross_srb 50 -report_timing`。`a30/placement/restored_sites.pcf` 是原 A30 的兼容布局提示，必须先确认新映射的实例及宏占用仍匹配后再加载；`final_placement.pcf` 是结果参考，不是自动可用的重新布线输入。
4. 新布线 DB 用第 3 节的独立 STA 命令重算，并检查**全部**时钟组的 setup、hold、recovery/removal、DDR 与 RGMII 路径。对新 DB 使用 `--allow-other-db`，比较它与 A30 的差异，而不要把不同 DB 的数值称作 A30 复现。

原生 A30 布线数据库、旧 PLC 和完整报告未入库。**仅靠这份源码无法逐位复现 A30 的布线和 +0.146/−0.033 ns 数值**；重新打包、布局和布线可能改变路径。要验证原数值，使用第 3 节的**字节一致的 A30 routed DB**。本工程尚未进行实板 DDR/RGMII 电气与板级偏斜签核。
