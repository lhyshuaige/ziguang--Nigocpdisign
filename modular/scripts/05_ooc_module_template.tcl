# Module-level logic/resource/timing run. This is a synthesis and mapping
# diagnostic flow, not a composable PGL50H module checkpoint.
# Replace TOP and SOURCES for one module. The CPU list below reuses the
# existing registered timing shell.
set ROOT "D:/PDS/project/NAX"
set TOP "nax_cpu_partition_shell_b11"
set SOURCES [list \
  "$ROOT/rtl/NaxRiscvContest.v" \
  "$ROOT/rtl/nax_cpu_partition_shell_b11.v"
]
set CONSTRAINT "$ROOT/constraints/nax_cpu_partition_timing_b11.fdc"

set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
foreach source $SOURCES { add_design $source }
add_constraint $CONSTRAINT
compile -force_to_run -top_module $TOP
synthesize -force_to_run -ads -selected_syn_tool_opt 2 -top_module $TOP
dev_map -force_to_run -top_module $TOP -detail -fanout 16 -fanout_number 200
pnr -force_to_run -place_only -report_timing
report_timing -force_to_run -delay_type {max} -max_path 20000 -slack_less_than 0.30
report_timing -force_to_run -delay_type {min} -max_path 20000 -slack_less_than 0
