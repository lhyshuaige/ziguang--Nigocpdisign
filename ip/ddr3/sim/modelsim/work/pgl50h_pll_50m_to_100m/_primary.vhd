library verilog;
use verilog.vl_types.all;
entity pgl50h_pll_50m_to_100m is
    port(
        clkin1          : in     vl_logic;
        clkout0         : out    vl_logic;
        clkout4         : out    vl_logic;
        pll_lock        : out    vl_logic
    );
end pgl50h_pll_50m_to_100m;
