library verilog;
use verilog.vl_types.all;
entity pgl50h_ai_accel_stub is
    port(
        clk             : in     vl_logic;
        reset           : in     vl_logic;
        start           : in     vl_logic;
        control         : in     vl_logic_vector(31 downto 0);
        src_addr        : in     vl_logic_vector(31 downto 0);
        dst_addr        : in     vl_logic_vector(31 downto 0);
        length          : in     vl_logic_vector(31 downto 0);
        status          : out    vl_logic_vector(31 downto 0)
    );
end pgl50h_ai_accel_stub;
