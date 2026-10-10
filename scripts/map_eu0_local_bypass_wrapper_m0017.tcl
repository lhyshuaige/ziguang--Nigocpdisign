open_project {D:/PDS/project/NAX/pds/eu0_local_bypass_wrapper_m0017_20261008/pgl50h_soc_hmic_clockgroup_PGL50H.pds}
compile -force_to_run -top_module {pgl50h_top}
synthesize -force_to_run -ads -selected_syn_tool_opt 2
dev_map -force_to_run
