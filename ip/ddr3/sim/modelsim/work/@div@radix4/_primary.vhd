library verilog;
use verilog.vl_types.all;
entity DivRadix4 is
    port(
        io_flush        : in     vl_logic;
        io_cmd_valid    : in     vl_logic;
        io_cmd_ready    : out    vl_logic;
        io_cmd_payload_a: in     vl_logic_vector(31 downto 0);
        io_cmd_payload_b: in     vl_logic_vector(31 downto 0);
        io_rsp_valid    : out    vl_logic;
        io_rsp_ready    : in     vl_logic;
        io_rsp_payload_result: out    vl_logic_vector(34 downto 0);
        io_rsp_payload_remain: out    vl_logic_vector(32 downto 0);
        clk             : in     vl_logic;
        reset           : in     vl_logic
    );
end DivRadix4;
