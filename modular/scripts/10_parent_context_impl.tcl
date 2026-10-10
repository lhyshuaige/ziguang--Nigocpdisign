# Complete parent-context implementation. Set PROJECT to the real .pds file
# and keep all paths absolute in CI/reproducible runs.
set PROJECT "D:/PDS/project/NAX/pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_soc_hmic_clockgroup_PGL50H.pds"
open_project $PROJECT
compile -force_to_run -top_module {pgl50h_top} -top_module pgl50h_top
synthesize -force_to_run -ads -selected_syn_tool_opt 2
dev_map -force_to_run
pnr -force_to_run -optimize_multi_corner_timing -fix_hold_violation -report_timing
report_timing -force_to_run -delay_type {max} -max_path 20000 -slack_less_than 0.30 -clock_group_limit {pll_clk_sys pll_clk_sys}
report_timing -force_to_run -delay_type {min} -max_path 20000 -slack_less_than 0
