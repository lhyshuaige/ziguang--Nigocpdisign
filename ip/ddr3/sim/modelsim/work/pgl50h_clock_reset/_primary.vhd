library verilog;
use verilog.vl_types.all;
entity pgl50h_clock_reset is
    generic(
        RESET_SYNC_STAGES: integer := 2
    );
    port(
        clk_50m         : in     vl_logic;
        reset_ext_n     : in     vl_logic;
        ddr_init_done   : in     vl_logic;
        clk_sys_ext     : in     vl_logic;
        ext_pll_locked  : in     vl_logic;
        use_external_clk: in     vl_logic;
        clk_sys         : out    vl_logic;
        pll_locked      : out    vl_logic;
        soc_reset       : out    vl_logic;
        soc_reset_n     : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of RESET_SYNC_STAGES : constant is 2;
end pgl50h_clock_reset;
