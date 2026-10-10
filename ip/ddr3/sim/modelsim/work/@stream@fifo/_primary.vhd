library verilog;
use verilog.vl_types.all;
entity StreamFifo is
    port(
        io_push_valid   : in     vl_logic;
        io_push_ready   : out    vl_logic;
        io_push_payload_robId: in     vl_logic_vector(4 downto 0);
        io_push_payload_mask: in     vl_logic_vector(1 downto 0);
        io_pop_valid    : out    vl_logic;
        io_pop_ready    : in     vl_logic;
        io_pop_payload_robId: out    vl_logic_vector(4 downto 0);
        io_pop_payload_mask: out    vl_logic_vector(1 downto 0);
        io_flush        : in     vl_logic;
        io_occupancy    : out    vl_logic_vector(4 downto 0);
        io_availability : out    vl_logic_vector(4 downto 0);
        clk             : in     vl_logic;
        reset           : in     vl_logic
    );
end StreamFifo;
