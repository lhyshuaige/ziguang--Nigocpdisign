# Incremental parent-context P&R. This is the supported preservation flow in
# this PDS installation: reuse the mapped DB and parent placement DB. It does
# not constitute a module checkpoint import.
set PROJECT "D:/PDS/project/NAX/pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_soc_hmic_clockgroup_PGL50H.pds"
# For a real AI/DMA/AXI change, MAP_DB must be the newly synthesized and
# newly mapped full-SoC database. The parent placement DB may remain the
# frozen reference placement.
set MAP_DB "D:/PDS/project/NAX/pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/pds/pgl50h_hmic_cdc_reset_20261007/device_map/pgl50h_top_map.adf"
set PLC_DB "D:/PDS/project/NAX/pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/pds/pgl50h_hmic_cdc_reset_20261007/place_route/pgl50h_top_plc.adf"
open_project $PROJECT
pnr -force_to_run -input_db_file $MAP_DB -input_place_db_file $PLC_DB -report_timing
report_timing -force_to_run -delay_type {max} -max_path 20000 -slack_less_than 0.30 -clock_group_limit {pll_clk_sys pll_clk_sys}
report_timing -force_to_run -delay_type {min} -max_path 20000 -slack_less_than 0
