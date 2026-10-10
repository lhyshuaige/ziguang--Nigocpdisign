library verilog;
use verilog.vl_types.all;
entity AllocatorMultiPortMem is
    port(
        io_push_0_valid : in     vl_logic;
        io_push_0_payload: in     vl_logic_vector(5 downto 0);
        io_push_1_valid : in     vl_logic;
        io_push_1_payload: in     vl_logic_vector(5 downto 0);
        io_pop_mask     : in     vl_logic_vector(1 downto 0);
        io_pop_ready    : out    vl_logic;
        io_pop_fire     : in     vl_logic;
        io_pop_values_0 : out    vl_logic_vector(5 downto 0);
        io_pop_values_1 : out    vl_logic_vector(5 downto 0);
        clk             : in     vl_logic;
        reset           : in     vl_logic
    );
end AllocatorMultiPortMem;
