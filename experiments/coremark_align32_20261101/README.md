# CoreMark 对齐参数实板对照

以发布版统一固件 `9700ce2a` 为基线，试验用户指定的参数。保留发布固件、RTL、位流、Flash 应用和原编译配方；候选只装载到 DDR。

```text
-march=rv32im_zicsr -mabi=ilp32 -mcmodel=medany
-O3 -fno-common -funroll-loops -funroll-all-loops
-finline-functions -finline-limit=1000
-fno-if-conversion2 -fselective-scheduling
-fno-crossjumping -freorder-blocks-and-partition
-mtune=sifive-7-series
-falign-functions=32 -falign-loops=4 -falign-jumps=8
-ffreestanding -fno-builtin -nostdlib -nostartfiles
```

相对旧参数，函数对齐从 8 改为 32 字节，循环对齐从 8 改为 4 字节，跳转对齐仍为 8 字节；链接增加 `-nostartfiles`。使用相同 GCC 13.2.0、未修改的 CoreMark 算法、启动代码、链接脚本、源文件及对象顺序。现有 `-ffunction-sections`、`-fdata-sections`、警告和程序入口定义继续保留。

新参数应用于统一固件的 8 个 CoreMark C 文件及链接命令，其余游戏、AI、驱动、调度器仍按发布配方的 `-O2` 编译。`-nostdlib -nostartfiles` 用于链接；独立启动汇编继续显式链接。每个候选有独立构建号及日志中的编译参数，不能冒充发布版。

## 2026-11-01 实板结果

同一块板、同一 P3 位流、CPU 100 MHz，先连续测旧版三次，再进入恢复 Bootloader 装载候选，连续测三次。每次性能组和校验组各 11,000 轮。六次均通过标准 CRC、日志完整性、计时以及固件身份检查；没有删去首轮或低分记录。

| 固件 | 第 1 次 CoreMark/MHz | 第 2 次 | 第 3 次 | 三次平均 |
|---|---:|---:|---:|---:|
| 旧版 `9700ce2a`，8 / 8 / 8 | 5.016804 | 5.024456 | 5.025871 | 5.022377 |
| 候选 `32f1ce51`，32 / 4 / 8 | 4.985207 | 5.015489 | 5.014081 | 5.004926 |

候选平均为 **500.4926 CoreMark**，旧版为 **502.2377 CoreMark**，本轮平均变化 **−0.3475%**。候选没有提分，因此本仓库发布参数和默认镜像保持原版。两组是顺序测试，起始缓存状态未强制相同；三次重复足以记录本轮现象，不能据此给出所有代码布局下的普遍性能结论。

候选 CPU 程序 125,848 字节，比原版增加 512 字节。最后一次测试结束时，板卡 DDR 内仍是候选 `32f1ce51`，处于 CoreMark 模式；没有写 Flash，没有重新下载 FPGA 位流。

- [完整对照结果](results/comparison.json)
- [旧版逐次结果](results/baseline_20261101T182921Z/summary.json)
- [候选逐次结果](results/candidate_20261101T183313Z/summary.json)
- [实测候选镜像](images/runtime_32f1ce51.ngb)
- [编译配方及审计](results/build.json)

候选镜像 SHA-256：`0f9be7440b8059ce65a3989ce6f5315a073ba2d500ab3f61cdeb0417ed5b4d48`。

## 复现

在仓库根目录执行。构建在 Linux / WSL 下进行，工具链路径按本机修改：

```sh
python3 -B experiments/coremark_align32_20261101/experiment.py build --tools /path/to/gcc-13.2/bin
```

输出到本目录 `build/candidate`，已有输出时拒绝覆盖。`build.json` 记录所有命令、输入与产物哈希；`effective_*.txt` 记录 GCC 实际生效的参数。构建不访问板卡。

已有本机 C 编译器时运行现成的 CRC / RPC 功能回归：

```sh
python -B experiments/coremark_align32_20261101/experiment.py native --cc gcc
```

本机回归不使用 RISC-V 专属选项，也不作为 Nigo CPU 分数。实板脚本会检查两组标准 CRC、每组至少运行 10 秒、原始计时与返回日志一致，以及运行前后固件号和模式切换序号稳定。

板卡 IP `192.168.1.50`，PC 有线 IP `192.168.1.100`。先用现有发布版记录基线：

```sh
python -B experiments/coremark_align32_20261101/experiment.py measure baseline --iterations 11000 --repeats 3
```

若当前应用不能软件退出，等待基线全部完成，再按住 KEY1、按下并松开 KEY0、继续按住 KEY1 约 3 秒后松开，进入恢复 Bootloader。下面命令会验证 Bootloader 身份，下载候选到 DDR 并运行三次：

```sh
python -B experiments/coremark_align32_20261101/experiment.py measure candidate --install --iterations 11000 --repeats 3
```

已装入候选时去掉 `--install`。每次运行含性能组 11,000 轮和校验组 11,000 轮；分数取性能组。统一固件在计时区不轮询网口，本次不额外改变外设开关。不要同时操作另一个上位机切换模式。

`results` 保留全部请求标识、原始回传文本、状态与结果，不丢弃低分或失败记录。超时后先查询相同请求，不自动重启一个新的跑分。发生复位或固件变化会报错停止。

本实验不修改 RTL 或重新做 FPGA 实现，也不改变当前发布版的时序签核结论。对齐会改变实际代码布局，得分须以实板结果为准。
