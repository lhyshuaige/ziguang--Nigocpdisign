# CoreMark 工作区移到栈上的实板实验

基线为前一轮已上板的 `32f1ce51`，保留用户指定的函数 / 循环 / 跳转对齐 **32 / 4 / 8** 及其余编译参数。仅将 CoreMark 移植头中的 `MEM_METHOD` 从 `MEM_STATIC` 改为 `MEM_STACK`，形成独立候选 `85a0e6af`。

原发布版 `9700ce2a`、前一轮候选、算法源码、RTL、位流、Flash 应用和链接脚本都保留。构建复制移植层到本实验的临时目录，只替换这一行宏；计时器、`HAS_FLOAT`、日志字符串和通信协议继续沿用上板版本。编译额外使用 `-fstack-usage` 生成栈帧报告。

**移到栈上的是 2,000 字节的 CoreMark 工作数据，不是整个程序。** 栈和原静态区都由 DDR 提供存储；该改动不意味着工作数据进入片上 RAM，也不能预先保证提分。

## 编译检查

| 项目 | 结果 |
|---|---:|
| 候选构建号 | `85a0e6af` |
| CPU 程序大小 | 126,360 字节 |
| BSS | 14,544 字节，比静态工作区版本少 2,000 字节 |
| `coremark_main` 栈帧 | 2,176 字节，编译器标记 `static` |
| CoreMark 各函数栈帧报告之和 | 3,536 字节 |
| 链接脚本保证的栈空间 | 至少 32 KiB |
| 静态数据末尾到栈顶的空间 | 116,512 字节 |

栈帧报告之和是函数清单的统计，不是完整调用图证明；本实验不宣称测量了运行时最大栈占用。本机 CRC / RPC 回归及后述实板性能种子、校验种子的完整校验都已通过。

## 2026-11-01 实板结果

三次性能组和校验组都通过标准 CRC、日志 CRC、计时一致性及固件身份检查，每组 11,000 轮。测试后 CoreMark → 待机 → CoreMark 切换也通过，最近成绩仍能取回。

| 工作区 | 第 1 次 CoreMark/MHz | 第 2 次 | 第 3 次 | 平均 | 中位数 |
|---|---:|---:|---:|---:|---:|
| 静态区 `32f1ce51`（复用上一轮实测） | 4.985207 | 5.015489 | 5.014081 | 5.004926 | 5.014081 |
| 栈 `85a0e6af` | 5.010463 | 5.014434 | 5.011277 | 5.012058 | 5.011277 |

平均变化 **+0.1425%**，中位数变化 **−0.0559%**，没有一致的性能提升。静态版首轮较低使平均值更容易上升，不能仅凭平均值认定移栈优化成功。该结果不能解释仿真 5.2108 与当前实板约 5.01 之间的差距，也没有证明 HMIC/CDC 是差距来源。

实验结束时板卡 DDR 中仍是 `85a0e6af`，处于 CoreMark 模式。仓库默认发布固件继续为 `9700ce2a`，没有写 Flash 或下载 FPGA 位流。

- [完整对照](results/comparison.json)
- [逐次回传与计时](results/candidate_20261101T185045Z/summary.json)
- [切换返回验证](results/mode_return.json)
- [栈占用清单](results/stack.json)
- [候选镜像](images/runtime_85a0e6af.ngb)

## 复现

从仓库根目录，在 Linux / WSL 使用与基线相同的 GCC 13.2.0：

```sh
python3 -B experiments/coremark_stack_20261101/experiment.py build --tools /path/to/gcc/bin
```

构建输出 `build/candidate`，已有目录时拒绝覆盖。通过 `port/core_portme.h`、`stack.json`、`symbols.log` 和 `build.json` 核对宏、栈占用、静态工作区符号消失及完整编译命令。

本机功能回归：

```sh
python -B experiments/coremark_stack_20261101/experiment.py native --cc gcc
```

板卡进入恢复 Bootloader 后，下列命令才会通过网口装载到 DDR 并测试；不写 Flash：

```sh
python -B experiments/coremark_stack_20261101/experiment.py measure --install --iterations 11000 --repeats 3
```

恢复方法：按住 KEY1，按下并松开 KEY0，继续按住 KEY1 约 3 秒后松开；不要按 REST。PC 有线 IP 为 `192.168.1.100`，板卡为 `192.168.1.50`。已经加载候选时去掉 `--install`。

每次性能组和校验组各 11,000 轮，共运行三次。原始请求、计时、日志和 CRC 都保留；协议与回传检查复用上一轮已使用的 `experiment.py`，不会覆盖它。对照基线取自上一轮的三次 `32f1ce51` 实测，不冒充本轮重新测量。
