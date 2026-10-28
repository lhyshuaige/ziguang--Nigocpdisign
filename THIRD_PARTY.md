# Third-party files

- `rtl/NaxRiscvContest.v` is generated from NaxRiscv and includes local modifications. Original license texts are retained in `LICENSES/NaxRiscv/`.
- `third_party/verilog-ethernet/` contains selected files at commit `77320a9471d19c7dd383914bc049e02d9f4f1ffb`; its MIT notices are retained in `COPYING` and `lib/axis/COPYING`.
- `assets/ultraface.ngm` derives from Ultra-Light-Fast-Generic-Face-Detector-1MB at commit `dffdddda9794a50607cba8f318507a28c1c27cab`; its upstream MIT license is in `LICENSES/UltraFace/LICENSE`, and source provenance is in `assets/upstream_source_manifest.json`.
- `ip/` now contains the 75 Pango DDR/PLL generated inputs used by A30. Their original copyright and proprietary notices are retained. The PLL source states that reproduction or disclosure requires written authorization from Pango. This project does not grant redistribution rights for those files; confirm authorization before a public upload. Exact hashes are in `a30/project_sources.json`.
