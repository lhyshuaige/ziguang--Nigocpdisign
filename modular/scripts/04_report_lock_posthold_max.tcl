open_project {D:/PDS/project/NAX/pds/stageB_ai_hmic_lock_test_m0017_20261010/pgl50h_soc_hmic_clockgroup_PGL50H.pds}
report_timing -force_to_run -delay_type {max} -max_path 20000 -slack_less_than 0.30 -clock_group_limit {pll_clk_sys pll_clk_sys}
file copy -force {D:/PDS/project/NAX/pds/stageB_ai_hmic_lock_test_m0017_20261010/report_timing/pgl50h_top.rtr} {D:/PDS/project/NAX/pds/stageB_ai_hmic_lock_test_m0017_20261010/posthold_setup_max.rtr}
exit
