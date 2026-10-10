# PDS capability audit. Run with pds_shell -f.
puts "PDS_COMMANDS=[info commands]"
foreach cmd {create_partition_def enable_pr_flow def_region def_inst_region def_inst_site pnr report_timing save_adif export_fdc} {
  puts "=== $cmd ==="
  catch {help $cmd} result
  puts $result
}
exit
