# 独立 CoreMark 镜像：仿真与实板复刻

2026-11-01，候选 **56d1cdac**。恢复原仿真参考的编译器、参数顺序、算法机器码、段内布局和栈相对位置，再用同一份镜像做仿真和 P3 实板测试。没有替换仓库默认统一固件 `9700ce2a`，也没有修改 RTL、FPGA 位流或 Flash。

## 实测结果

单位为 CoreMark/MHz；板上 Nigo CPU 为 100 MHz。

| 测试 | 外层迭代数 | 结果 |
|---|---:|---:|
| 原冻结仿真参考 | 100 | 5.21081335 |
| 本次同镜像仿真 | 100 | 5.21073869 |
| 实板刚加载后的自动样本 | 100 | 5.03760852 |
| 实板受控短测，三次 | 100 | 5.13234627 / 5.13651548 / 5.13574440 |
| 实板长测，第 1 次 | 11,000 | 5.14216957 |
| 实板长测，第 2 次 | 11,000 | 5.14218010 |
| 实板长测，第 3 次 | 11,000 | 5.14218615 |

长测平均 **5.14217861 CoreMark/MHz，即 514.21786 CoreMark**。比上一轮统一固件 MEM_STACK 候选均值 5.01205806 提高 **2.596%**。三次长测极差相对均值为 0.000322%，这是本次有限样本的稳定性结果。

每组分别运行性能种子与验证种子各 11,000 轮，约 21.392 秒与 21.328 秒；三组合计 66,000 次外层迭代。六次标准 CRC 校验全部通过。100 轮只有约 0.19 秒，属于诊断数据，不满足 CoreMark 至少 10 秒的时长要求；本目录成绩未经过 EEMBC 认证。

同镜像仿真比原冻结参考多 275 周期，成绩差约 0.00143%。实板长测仍比 100 轮仿真低约 1.316%，但两者迭代数、起跑状态和存储模型不同，不能把这个百分比直接归因于 DDR 或 HMIC/CDC。刚加载的实板 100 轮与后续受控短测不同，也说明起跑状态需要独立记录。

## 本次对齐了什么

- 使用原冻结参考 GCC 13.2.0、原始参数顺序和 `FLAGS_STR`；参数末尾为函数 / 循环 / 跳转对齐 `32 / 4 / 8`。保留前面被覆盖的对齐选项，避免参数字符串变化移动数据段。
- 算法源码、32 位 CLINT 计时 port、MEM_STACK 的 2,000 字节工作区均来自冻结参考。所有基准对象保持原链接顺序，没有引入函数分节和链接垃圾回收。
- 因为 P3 的 `0x80000000` 区域由启动 ROM 使用，将整个基准区域统一平移到 `0x82000000`，栈顶为 `0x8203fff0`。构建器逐字节验证平移后的 `.init`、`.text` 与原参考一致。
- 网口服务代码单独放到 `0x82080000`，服务 RAM / 栈位于 `0x82100000` 区域。构建器验证加入服务后，基准代码、常量、数据、BSS 的地址、大小和内容没有移动。
- 最终只补两条计时区外的跳转：`0x8200002c` 在 `main` 返回后回服务；`0x82008960` 在停止计时及原 CRC 检查后收集结果。算法和计时函数机器码保留。
- 每次受控测试关闭中断，检查 AI / DMA / RX / TX 空闲，关闭 Ethernet 使能并确认跨时钟状态，再运行两组种子；结束后审计活动计数器和使能状态并恢复网口。全部六组受控短 / 长测试的 `audit_errors`、`network_before`、`network_after` 都为 0。后台硬件时钟和 DDR 刷新仍存在。

因此这是一次完整的软件复刻实验。它同时改变了原统一应用的 port、链接布局和计时外服务方式，不能把改善单独归因于某一个编译选项或“把工作区放到栈上”。栈仍然在 DDR 内。

## 仿真的范围

`reference/simulator/` 保存原测量采用的 CPU / Cache / HMIC RTL 快照。`sim/pgl50h_soc_coremark_tb.v` 只为同镜像执行增加地址重映射、2 MiB 行为内存和跳到服务入口的两条引导指令，保持原有 HMIC 写就绪、下一拍读返回模型。

这不是 P3 全 RTL 加 DDR PHY 的仿真，不能代表真实 DDR 延迟。原 C++ harness 在第一个 `PORT_DONE` 后结束，因此仿真只覆盖自动性能种子的 100 轮；实板另外验证了验证种子及长测。

原 console 中 `STACK in modeled DDR` 字符串为保持布局而保留，实板运行时工作区实际位于板上 DDR。实板结果来自停止计时后读取的 `core_results` 与计时变量，经 UDP 回传；没有把仿真 console 冒充为实板串口输出。

## 文件和证据

- [比较汇总](results/comparison.json)、[原参考](results/original_simulation.json)、[同镜像仿真](results/simulation/result.json)、[仿真原始输出](results/simulation/console.txt)。
- [刚加载的 100 轮实板样本](results/install_11000_20261101T192200Z/summary.json)、[受控 100 轮三次](results/measure_100_20261101T192217Z/summary.json)、[11,000 轮三次](results/measure_11000_20261101T192232Z/summary.json)。相邻文件保留下载应答、请求 ID、回传字段和原始包十六进制。
- [候选 ELF](images/canonical_56d1cdac.elf)、[候选 NGB](images/canonical_56d1cdac.ngb)、[构建命令与布局检查](images/canonical_56d1cdac.json)、[链接脚本](images/combined.ld)、[符号](images/symbols.txt)。ELF 生成仿真内存镜像和实板 NGB，两种执行途径使用同一份载荷。
- [独立目录重建验证](results/rebuild.json)：仅使用本目录打包的参考源码，ELF、NGB、仿真 memh 三项哈希均一致。

NGB SHA-256：`b29348ad2891fc1ba3c12397eef9a4c5fb01187e56c1ea02fc4269f3f5a603a1`

ELF SHA-256：`d233d8146ab3a43e166f804372f72302c0cb8713719730af462e2a6ab4ea01a5`

含头 NGB 为 529,068 字节，其中包括隔离代码段所需的地址空隙；入口为 `0x82080000`。它是 CPU 应用，不是 FPGA 位流。

## 重建与复测

在本目录执行。构建器默认使用已打包的 `reference/`，不依赖原电脑上的参考项目路径；`--reference-root` 只用于从原实验重新导入参考。

```sh
# Linux / WSL，使用记录中的 GCC 13.2.0 工具链
python3 build.py --tools /path/to/riscv/bin
```

完成的 `build/` 不允许覆盖。可用 `--output build/rebuild_check` 在独立目录重建；`--retry` 只用于尚未产生 `build.json` 的失败构建。

```powershell
# Windows；默认工具位置与本机一致，也可通过参数指定
.\build_sim.ps1 -VerilatorRoot D:\PDS\Verilator -GccBin D:\PDS\w64devkit\w64devkit\bin
python -B run_sim.py
python -B test_board.py -v
```

`run_sim.py` 的主机 DLL 搜索路径默认使用 `D:/PDS/w64devkit/w64devkit/bin`；换电脑时把该工具链放进 PATH。仿真结果存入 `results/simulation/`，已有 `sim/build/run/` 时脚本拒绝覆盖。

实板使用已验证的 P3 位流；PC 接板网卡为 `192.168.1.100/24`，板卡为 `192.168.1.50`。关闭可能同时发送请求的上位机会话。按住 KEY1，按下并松开 KEY0，继续按住 KEY1 约 3 秒后松开，进入网络 Bootloader；不要按 REST。

```powershell
python -B board.py install
python -B board.py measure --iterations 100 --repeats 3
python -B board.py measure --iterations 11000 --repeats 3
python -B board.py query
```

`install` 自动保留刚启动的两组 100 轮结果；有本地构建时采用 `build/`，否则采用随包 `images/` 候选。`measure` 使用固定种子及请求 ID，保留不明确的超时记录，不会在超时后偷偷启动新一组。32 位计时采用最多 11,000 轮的当前测试范围，避免擅自扩大到计时溢出风险区间。

板上测试结束后停留在独立 CoreMark 服务 `56d1cdac`，不支持统一固件的游戏 / AI 页面切换。恢复原应用需进入网络恢复后重新安装默认统一固件；普通复位可能自动进入 Flash 中原有应用。本实验没有覆盖 Flash。

CoreMark 上游算法的许可见 [LICENSE](reference/src/LICENSE.md)，其余第三方来源沿用仓库 [第三方说明](../../THIRD_PARTY.md)。
