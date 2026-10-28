# Nigo-2 — LG100 SoC + UltraFace A30 snapshot

项目文档：[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) 说明模块、数据流和当前功能边界；[`docs/TIMING_REPRODUCTION.md`](docs/TIMING_REPRODUCTION.md) 给出 A30 时序证据核验、原生数据库独立 STA 和源码重建步骤。

Target: MES2L676-100HP, PG2L100H-6IFBG676. CPU schedules inference; the PC uploads images over Ethernet and receives face events. The OV7670 input is deferred until the FMC adapter is available.

This repository contains the **A30** mapped design's 184 ordered RTL/IP/constraint inputs, firmware source and 32 KiB boot image, PC uploader, UltraFace-Slim-320 model asset, physical site constraints, and compact timing evidence. `a30/project_sources.json` records every input's original hash, including 75 Pango-generated IP files now in `ip/`.

The working `rtl/pg2l100h_soc_top.v` changes only the old machine-specific boot-ROM file path to `firmware/build/boot64.hex`; the byte-exact A30 top file is in `a30/exact/`. The ROM image is byte-identical to the one used by A30. All other mapped open-source/design inputs retain their A30 hashes.

**A30 timing:** setup slow corner +0.146 ns, setup fast corner +0.269 ns; hold slow corner +0.049 ns, hold fast corner −0.033 ns at 5 endpoints. DDR and RGMII timing groups passed. **A30 has not passed hold signoff.** See `a30/evidence/timing_result.json` and `a30/evidence/all_negative_paths.json`. The full-network functional qualification is in `a30/evidence/full_network_qualification.json`. The native PDS databases and full 800 MB timing reports are intentionally outside this source export.

The Pango-generated DDR/PLL IP in `ip/` retains its proprietary headers. The PLL source explicitly requires written authorization before reproduction or disclosure; inclusion in this local copy does not grant permission to publish it. Review `THIRD_PARTY.md` before a public GitHub upload. PDS version used for A30: 2022.2-SP6.7.1. Exact physical replay also depends on that toolchain and its native implementation database; the included PCFs preserve the measured placement/reference.

Firmware: install a `riscv64-unknown-elf-*` toolchain, then run `sh build_firmware.sh` from this directory. Set `RISCV_TOOLCHAIN_BIN` if it is outside `PATH`. The PC app requires Python with Tkinter and Pillow (`pip install -r pc/requirements.txt`), then run `python pc/app.py`.

Run `python verify_package.py` to verify the copied file hashes. Third-party licenses are in `LICENSES/` and `third_party/verilog-ethernet/`.
