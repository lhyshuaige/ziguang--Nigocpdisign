open_project {D:/PDS/project/NAX/pds/eu0_local_bypass_wrapper_full_m0017_20261008/pgl50h_soc_hmic_clockgroup_PGL50H.pds}
compile -force_to_run -top_module {pgl50h_top}
synthesize -force_to_run -ads -selected_syn_tool_opt 2
dev_map -force_to_run
pnr -force_to_run -input_db_file {D:/PDS/project/NAX/pds/eu0_local_bypass_wrapper_full_m0017_20261008/device_map/pgl50h_top_map.adf} -input_place_db_file {D:/PDS/project/NAX/pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/pds/pgl50h_hmic_cdc_reset_20261007/place_route/pgl50h_top_plc.adf} -optimize_multi_corner_timing -fix_hold_violation -report_timing -slack_prior_in_global_router TRUE
report_timing -force_to_run -delay_type {max} -max_path 20000 -slack_less_than 0
report_timing -force_to_run -delay_type {min} -max_path 20000 -slack_less_than 0
