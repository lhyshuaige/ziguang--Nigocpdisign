# Read-only capability query on the PGL50H parent project.
set PROJECT "D:/PDS/project/NAX/pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_soc_hmic_clockgroup_PGL50H.pds"
open_project $PROJECT
puts "EXPORTCMDS=[lsort [info commands *export*]]"
puts "WRITECMDS=[lsort [info commands *write*]]"
puts "PLACECMDS=[lsort [info commands *place*]]"
puts "ATTRCMDS=[lsort [info commands *attr*]]"
puts "OBJECTCMDS=[lsort [info commands *object*]]"
puts "SITECMDS=[lsort [info commands *site*]]"
foreach cmd {def_inst_site def_preserve generate_constraint save_adif export_fdc} {
  puts "=== $cmd ==="
  if {[catch {help $cmd} result]} { puts "UNAVAILABLE $result" } else { puts $result }
}
exit
