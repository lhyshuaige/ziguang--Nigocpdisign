library verilog;
use verilog.vl_types.all;
entity pgl50h_pds_pll_wrapper is
    port(
        clk_in          : in     vl_logic;
        reset_n         : in     vl_logic;
        clk_out         : out    vl_logic;
        locked          : out    vl_logic
    );
end pgl50h_pds_pll_wrapper;
