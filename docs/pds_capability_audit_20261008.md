# PDS 2022.2-SP6.7.1 capability audit

The audit was run against the installed PDS shell at
`D:/PDS/PDSAPP/PDS_2022.2-SP6.7.1/PDS_2022/PDS_2022.2-SP6.7.1-ads/bin/pds_shell.exe`.

Commands present in the shell include:

* `compile`, `synthesize`, `dev_map`, `pnr`, `report_timing`;
* `def_region`, `def_inst_region`, `def_inst_site`;
* `enable_pr_flow`, `create_partition_def`, `remove_partition_def`;
* `save_adif`, `.switch_db`, `export_fdc`.

The `pnr -help` output confirms both `-input_db_file` and
`-input_place_db_file`. This is the basis of the parent placement reuse flow.
The same help output has no generic `read_checkpoint`, `write_checkpoint`,
module import, or module assembly option. The shell exposes Partition Definition
commands, but the installed PDS user guide describes that flow as local dynamic
reconfiguration and lists PG2L100H and PG2T390H as the supported devices. It
does not list PGL50H in that support statement.

The practical conclusion is that this project should use fixed RTL boundaries,
physical regions, exact instance site constraints, and parent map/placement
database reuse. A standalone module `.adf` is retained as a module diagnostic
artifact; it is not imported as a composable PGL50H module checkpoint.

The raw command captures used during the audit are kept in the task workspace as
`D:/PDS/tmp_pds_help_pnr.out` and `D:/PDS/tmp_pds_help_pr.out`.
