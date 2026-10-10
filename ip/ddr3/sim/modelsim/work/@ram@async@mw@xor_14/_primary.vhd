library verilog;
use verilog.vl_types.all;
entity RamAsyncMwXor_14 is
    port(
        io_writes_0_valid: in     vl_logic;
        io_writes_0_payload_address: in     vl_logic_vector(5 downto 0);
        io_writes_0_payload_data: in     vl_logic_vector(1 downto 0);
        io_writes_1_valid: in     vl_logic;
        io_writes_1_payload_address: in     vl_logic_vector(5 downto 0);
        io_writes_1_payload_data: in     vl_logic_vector(1 downto 0);
        io_writes_2_valid: in     vl_logic;
        io_writes_2_payload_address: in     vl_logic_vector(5 downto 0);
        io_writes_2_payload_data: in     vl_logic_vector(1 downto 0);
        io_writes_3_valid: in     vl_logic;
        io_writes_3_payload_address: in     vl_logic_vector(5 downto 0);
        io_writes_3_payload_data: in     vl_logic_vector(1 downto 0);
        io_read_0_cmd_valid: in     vl_logic;
        io_read_0_cmd_payload: in     vl_logic_vector(5 downto 0);
        io_read_0_rsp   : out    vl_logic_vector(1 downto 0);
        io_read_1_cmd_valid: in     vl_logic;
        io_read_1_cmd_payload: in     vl_logic_vector(5 downto 0);
        io_read_1_rsp   : out    vl_logic_vector(1 downto 0);
        io_read_2_cmd_valid: in     vl_logic;
        io_read_2_cmd_payload: in     vl_logic_vector(5 downto 0);
        io_read_2_rsp   : out    vl_logic_vector(1 downto 0);
        io_read_3_cmd_valid: in     vl_logic;
        io_read_3_cmd_payload: in     vl_logic_vector(5 downto 0);
        io_read_3_rsp   : out    vl_logic_vector(1 downto 0);
        io_read_4_cmd_valid: in     vl_logic;
        io_read_4_cmd_payload: in     vl_logic_vector(5 downto 0);
        io_read_4_rsp   : out    vl_logic_vector(1 downto 0);
        io_read_5_cmd_valid: in     vl_logic;
        io_read_5_cmd_payload: in     vl_logic_vector(5 downto 0);
        io_read_5_rsp   : out    vl_logic_vector(1 downto 0);
        clk             : in     vl_logic;
        reset           : in     vl_logic
    );
end RamAsyncMwXor_14;
