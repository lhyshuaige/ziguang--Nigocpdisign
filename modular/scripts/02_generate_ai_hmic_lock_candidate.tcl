# Generate candidate exact-site placement constraints from the frozen parent
# PNR database. This is a read-only export of constraints; the generated PCF
# is not signoff until every instance binds in the changed-module map DB.
set PROJECT "D:/PDS/project/NAX/pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_soc_hmic_clockgroup_PGL50H.pds"
set PNR_DB "D:/PDS/project/NAX/pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/pds/pgl50h_hmic_cdc_reset_20261007/place_route/pgl50h_top_pnr.adf"
set PLC_DB "D:/PDS/project/NAX/pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/pds/pgl50h_hmic_cdc_reset_20261007/place_route/pgl50h_top_plc.adf"
open_project $PROJECT
generate_constraint -module_inst {u_soc_core/g_axi_fabric.u_ai_engine} -file {D:/PDS/project/NAX/modular/constraints/50_ai_lock_generated_20261010.pcf} -db $PNR_DB -place_db
generate_constraint -module_inst {u_ddr3/u_pds_ddr3/u_hmic} -file {D:/PDS/project/NAX/modular/constraints/51_hmic_lock_generated_20261010.pcf} -db $PNR_DB -place_db
exit
