# 第三方来源与许可

- `rtl/NaxRiscvContest.v` 源自 NaxRiscv 生成 RTL，包含本地修改。保留的上游许可在 `LICENSES/NaxRiscv/`。项目对处理器使用 Nigo CPU 名称，不改变上游归属。
- `third_party/verilog-ethernet/` 为所需的选定源文件，上游参考提交 `77320a9471d19c7dd383914bc049e02d9f4f1ffb`。MIT 许可与各源文件版权头保留在 `COPYING` 及对应文件。
- UltraFace 模型源自 Ultra-Light-Fast-Generic-Face-Detector-1MB，上游参考提交 `dffdddda9794a50607cba8f318507a28c1c27cab`。许可在 `LICENSES/UltraFace/LICENSE`；输入模型哈希在 `upper/provenance.json`。
- CoreMark 1.0 官方算法文件选自 `1f483d5b8316753a742cbf5590caf5bd0a4e4777`，许可保留在 `upper/firmware/coremark/upstream/LICENSE.md`。`sources.json` 记录算法文件哈希，移植层单独存放。
- `ip/` 包含本工程使用的 Pango DDR3 / PLL 原始 IP 输入文件。其厂商版权和专有声明原样保留；部分文件声明复制或披露需厂商书面授权。本仓库的整理行为不授予这些文件新的公开再分发权。

没有把第三方或厂商文件统一改成 MIT，也没有替项目作者选择新的整体开源许可证。公开发布时应遵守各文件已有许可。PDS 软件、下载器驱动和 GNU 工具链可执行程序不包含在本包中。
