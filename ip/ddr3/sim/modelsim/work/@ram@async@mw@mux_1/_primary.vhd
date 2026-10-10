library verilog;
use verilog.vl_types.all;
entity RamAsyncMwMux_1 is
    port(
        io_writes_0_valid: in     vl_logic;
        io_writes_0_payload_address: in     vl_logic_vector(3 downto 0);
        io_writes_0_payload_data: in     vl_logic_vector(64 downto 0);
        io_writes_1_valid: in     vl_logic;
        io_writes_1_payload_address: in     vl_logic_vector(3 downto 0);
        io_writes_1_payload_data: in     vl_logic_vector(64 downto 0);
        io_read_0_cmd_valid: in     vl_logic;
        io_read_0_cmd_payload: in     vl_logic_vector(3 downto 0);
        io_read_0_rsp   : out    vl_logic_vector(64 downto 0);
        clk             : in     vl_logic;
        reset           : in     vl_logic
    );
end RamAsyncMwMux_1;
