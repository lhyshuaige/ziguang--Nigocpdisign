# Nigo CPU 上位机

从仓库根目录运行 `python upper/app.py`，或双击本目录的 `start.cmd`。需要带 Tkinter 的 Python 3.10+ 和 `requirements.txt` 中的 Pillow。

本发布包默认 CPU 固件为 **9700ce2a**，完整镜像哈希在 `assets/firmware/runtime.json`。`app.py` 和主协议实现沿用原上位机；新游戏绘图运行在 Nigo CPU，PC 负责校验、解码、显示。

| 页面 | 功能 |
|---|---|
| 程序与连接 | 网络 Bootloader 安装 CPU `.ngb` 程序、查询统一模式 |
| 图像接收 | PC 输入图片转换为 Gray8 / RGB565，经网口写板端 DDR |
| 人脸检测 | 模型上传、低频检测、人脸框及事件显示、原图坐标映射 |
| CoreMark | 运行、校验并取回 Nigo CPU 的 CoreMark 1.0 日志 |
| 游戏 | 显示板端游戏菜单及帧流，通过开发板按键控制 |

默认 PC `192.168.1.100/24`，板卡 `192.168.1.50`。UDP 5000 接收图像数据，5001 控制/程序/模型上传，5002 AI 结果，5003 游戏帧。请只运行一个游戏接收窗口。日志和个人输入图片不纳入 Git。

已运行统一应用时切页不会重新下载固件。要替换 Flash 中自动启动的旧应用，先用 KEY1 + KEY0 进入网络恢复，再安装本包固件。当前 GUI 不写 Flash，不自动修改网卡配置；断电后 DDR 程序与模型丢失。

AI 默认把原图直接缩放至 320×240 RGB888 作为输入，上位机保留原图，把返回框按横纵比例映射回原尺寸。当前是人脸检测，不做人脸身份识别；没有 PC 摄像头连续输入。检测完成后日志保存在 `logs/faces/`。

离线回归：

```sh
cd upper
python -B -m unittest discover -s tests -v
```

`assets/samples/` 为已有参考素材，`assets/mysample/` 不随包复制。`assets/SHA256SUMS.json` 和 `provenance.json` 记录资源校验。`source://` 前缀仅表示原工作区的历史来源，不是运行时需要访问的路径。

完整硬件说明与操作步骤见仓库 [README](../README.md) 和 [上板顺序](../docs/BOARD_TEST.md)。
