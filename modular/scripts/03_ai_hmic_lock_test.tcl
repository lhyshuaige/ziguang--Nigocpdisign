# Candidate CPU experiment with AI/HMIC exact-site constraints and the frozen
# parent placement database. The candidate map is from the RS2 late-bypass
# synthesis; CPU remains unlocked so its changed cells may move.
open_project {D:/PDS/project/NAX/pds/stageB_ai_hmic_lock_test_m0017_20261010/pgl50h_soc_hmic_clockgroup_PGL50H.pds}
add_constraint -copy {D:/PDS/project/NAX/modular/constraints/52_ai_hmic_lock_combined_20261010.pcf}
pnr -force_to_run -input_db_file {D:/PDS/project/NAX/pds/stageB_eu0_late_bypass_rs2_m0017_20261010/device_map/pgl50h_top_map.adf} -input_place_db_file {D:/PDS/project/NAX/pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/pds/pgl50h_hmic_cdc_reset_20261007/place_route/pgl50h_top_plc.adf} -report_timing
report_timing -force_to_run -delay_type {max} -max_path 20000 -slack_less_than 0.30 -clock_group_limit {pll_clk_sys pll_clk_sys}
report_timing -force_to_run -delay_type {min} -max_path 20000 -slack_less_than 0
exit
