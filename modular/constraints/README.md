# Constraint layers

Constraint files are applied in this order:

1. `00_board_pins.fdc` / official HMIC constraints: board I/O, DDR3 pin and
   clock declarations;
2. `10_clocks_resets.fdc`: `pll_clk_sys`, `ddrphy_clkin`, generated clocks,
   uncertainty and CDC reset exceptions;
3. `20_module_timing_budget.fdc`: visible `set_max_delay` contracts at the
   registered partition boundaries;
4. `30_regions.pcf`: `def_region` and `def_inst_region` for the parent
   physical partition seed;
5. `40_hmic_official.pcf`: the generated PDS HMIC site/CA/DQS constraints;
6. `50_verified_instance_lock.pcf`: only exact, reviewed
   `def_inst_site {hierarchical_instance} SITE [SYMBOL]` entries.

The first four layers can be edited during architectural bring-up. The HMIC
layer is copied from the official generated IP project. The last layer is
generated only after a parent database export has been validated; internal
ADIF `SITEREF (x y)` coordinates are not accepted as physical site names.

Regions are soft physical partitions. They are not a substitute for a module
checkpoint. A region is first selected from a fresh parent-context placement
seed and then frozen as a reviewed constraint.
