set PROJECT "D:/PDS/project/NAX/pds/stageB_ai_hmic_lock_test_m0017_20261010/pgl50h_soc_hmic_clockgroup_PGL50H.pds"
open_project $PROJECT
foreach cmd {add_constraint import_constraint def_inst_site def_preserve pnr} {
  puts "=== $cmd ==="
  catch {help $cmd} result
  puts $result
}
exit
