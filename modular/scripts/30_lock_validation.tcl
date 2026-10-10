# Selective lock validation. Populate LOCK_PCF only from a validated exact-site
# exporter. A SITEREF grid coordinate is not a valid SITE argument.
set PROJECT "D:/PDS/project/NAX/pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_soc_hmic_clockgroup_PGL50H.pds"
set MAP_DB "D:/PDS/project/NAX/pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/pds/pgl50h_hmic_cdc_reset_20261007/device_map/pgl50h_top_map.adf"
set PLC_DB "D:/PDS/project/NAX/pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/pds/pgl50h_hmic_cdc_reset_20261007/place_route/pgl50h_top_plc.adf"
set LOCK_PCF "D:/PDS/project/NAX/modular/constraints/50_verified_instance_lock.pcf"
if {![file exists $LOCK_PCF]} { error "No verified exact-site lock file exists" }
open_project $PROJECT
source $LOCK_PCF
pnr -force_to_run -input_db_file $MAP_DB -input_place_db_file $PLC_DB -report_timing
report_timing -force_to_run -delay_type {max} -max_path 20000 -slack_less_than 0.30 -clock_group_limit {pll_clk_sys pll_clk_sys}
report_timing -force_to_run -delay_type {min} -max_path 20000 -slack_less_than 0
