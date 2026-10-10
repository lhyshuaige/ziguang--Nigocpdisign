# Parent timing clusters from the -0.017 ns reference

Source: `pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/.../place_route/pgl50h_top.rtr`.
The report was summarized with `modular/scripts/summarize_parent_timing.py` at a
0.30 ns near-critical threshold.

The global setup result is `pll_clk_sys` WNS `-0.017 ns`, TNS `-0.019 ns`,
two failing endpoints. Both failing endpoints belong to CPU. The next CPU path
is `+0.001 ns`, so the CPU cluster is concentrated at the boundary of failure.

| rank | owner | slack | path cluster |
|---:|---|---:|---|
| 1 | CPU | -0.017 ns | RF ALU0 `ram_24` → EU0 `fetch_1 RS2` mux; ALU add/sub and branch/operand select fanout |
| 2 | CPU | -0.002 ns | RF EU0 `ram_3` → EU0 MUL operand register, APM/multiply ingress |
| 3 | CPU | +0.001 ns | Same RF EU0 `ram_3` → EU0 MUL operand register, adjacent bit |
| 4–5 | CPU | +0.092 ns | frontend physical register dispatch → RF dependency RAM write ports |
| 6–8 | DDR/HMIC | +0.100 ns | HMIC write-data alignment → DDR PHY DFI write-data registers |
| 9 | CPU | +0.101 ns | ALU1 PC → branch final target memory |
| 10–12 | CPU | +0.138 ns | RF allocation pointer → allocator RAM write ports |
| 13–15 | DDR/HMIC | +0.171 ns | HMIC write-data alignment → DDR PHY DFI write-data registers |
| 16–21 | DDR/HMIC | +0.183 ns | DQS IO clock → read FIFO address bits |

The CPU critical paths are both RF consumer paths in the EU0 cone. The worst
path has 4.405 ns logic delay and 5.236 ns routing delay; the adjacent MUL path
has 5.399 ns logic delay and 4.305 ns routing delay. This points to two separate
actions: reduce the RF-to-EU0 route and fanout for the first path, and keep the
MUL ingress logic local for the second. A global extra pipeline stage would
change CPU latency and CoreMark behavior, so the first experiment should keep
latency unchanged and alter only local operand/bypass ownership.

The DDR/HMIC near-critical paths remain positive and are inside the official
HMIC topology. They are monitored as a separate cluster; the CPU optimization
pass must not change HMIC clock, reset, CA or DQS constraints.
