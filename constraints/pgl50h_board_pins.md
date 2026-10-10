# PGL50H 盘古网口板板级信号表

来源：`50k/盘古50K网口板硬件使用手册.pdf`（PGL50H-6IFBG484，MES50H-Ethernet）。

本文件是 PDS Pin Planner 的信号命名基准。PDS 工程中的实际 `set_io`/管脚约束由 Pin Planner 导出，不在 RTL 仓库中猜写工具专用语法。

## 时钟与复位

| RTL 信号 | 管脚 | 说明 |
| --- | --- | --- |
| `clk_50m` | P20 | 50 MHz 单端系统时钟 |
| `clk_27m` | K21 | 27 MHz 板载时钟，当前 SoC 不使用 |
| `hsst_refclk_p/n` | A10/B10 | 125 MHz 差分 HSST/SFP 参考时钟，当前不进入 CPU 时钟树 |
| `reset_n` | W17 | 板级低有效复位；位置沿用随板 DDR3 示例约束，正式上板前按硬件手册/板卡丝印复核 |

## 用户按键和 LED

按键在 `pgl50h_top` 中命名为 `key_n[7:0]`，RTL 转换为高有效 `keys[7:0] = ~key_n`；LED 为高电平点亮。

| 位号 | `key_n` | `led` |
| ---: | --- | --- |
| 0 | U6 | F9 |
| 1 | T7 | G8 |
| 2 | W9 | E6 |
| 3 | Y8 | E5 |
| 4 | Y7 | A4 |
| 5 | AB7 | C4 |
| 6 | AA6 | D5 |
| 7 | AB6 | D4 |

## QSPI Flash

| RTL 信号 | 管脚 |
| --- | --- |
| `qspi_cs_n` | AA3 |
| `qspi_dq[0]` | AB20 |
| `qspi_dq[1]` | AA20 |
| `qspi_dq[2]` | R13 |
| `qspi_dq[3]` | T14 |
| `qspi_sck` | Y20 |

## DDR3（32 bit，Bank 3）

| 信号组 | 管脚 |
| --- | --- |
| `ddr3_addr[0:15]` | N6, R4, P6, F3, V5, E4, V3, D2, U4, P5, P8, T4, P7, P4, T3, R7 |
| `ddr3_ba[0:2]` | F5, W4, N7 |
| `ddr3_cas_n` | H8 |
| `ddr3_ck_n/p` | T5 / T6 |
| `ddr3_cke` | Y3 |
| `ddr3_cs_n` | G6 |
| `ddr3_odt` | G7 |
| `ddr3_ras_n` | J7 |
| `ddr3_reset_n` | C1 |
| `ddr3_we_n` | H6 |
| `ddr3_dm[0:3]` | W3, L1, K2, G1 |
| `ddr3_dqs_p/n[0]` | V2 / V1 |
| `ddr3_dqs_p/n[1]` | N3 / N1 |
| `ddr3_dqs_p/n[2]` | M6 / L6 |
| `ddr3_dqs_p/n[3]` | E3 / E1 |
| `ddr3_dq[0:31]` | U1, U3, T2, Y2, T1, Y1, M7, W1, P1, M2, R1, M1, P2, L3, P3, N4, K4, K1, J3, L4, K3, M3, J1, M4, J6, F1, K7, F2, H5, H3, J4, G3 |

DDR3 的 PDS HMIC IP 参考时钟仍接 50 MHz，PHY PLL 和训练由 IP 内部完成；SoC 只等待 `ddr_init_done` 后释放 CPU 复位。

## 当前未在第一版顶层启用的接口

- 两路 SFP/HSST 和两路 YT8614 QSGMII 网口：保留给后续以太网/摄像头数据通路。
- 40-pin 扩展口：RTL 作为 `ext_io[33:0]` 三态端口暴露，具体 J8 管脚按手册 Pin Planner 表接入。
