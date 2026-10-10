library verilog;
use verilog.vl_types.all;
entity pgl50h_mem_fabric is
    generic(
        MEM_WORDS       : integer := 4096
    );
    port(
        clk             : in     vl_logic;
        reset           : in     vl_logic;
        if_cmd_valid    : in     vl_logic;
        if_cmd_ready    : out    vl_logic;
        if_cmd_address  : in     vl_logic_vector(31 downto 0);
        if_rsp_valid    : out    vl_logic;
        if_rsp_ready    : in     vl_logic;
        if_rsp_data     : out    vl_logic_vector(63 downto 0);
        if_rsp_error    : out    vl_logic;
        d_read_cmd_valid: in     vl_logic;
        d_read_cmd_ready: out    vl_logic;
        d_read_cmd_id   : in     vl_logic_vector(0 downto 0);
        d_read_cmd_address: in     vl_logic_vector(31 downto 0);
        d_read_rsp_valid: out    vl_logic;
        d_read_rsp_ready: in     vl_logic;
        d_read_rsp_id   : out    vl_logic_vector(0 downto 0);
        d_read_rsp_data : out    vl_logic_vector(63 downto 0);
        d_read_rsp_error: out    vl_logic;
        d_write_cmd_valid: in     vl_logic;
        d_write_cmd_ready: out    vl_logic;
        d_write_cmd_last: in     vl_logic;
        d_write_cmd_address: in     vl_logic_vector(31 downto 0);
        d_write_cmd_data: in     vl_logic_vector(63 downto 0);
        d_write_cmd_id  : in     vl_logic_vector(0 downto 0);
        d_write_rsp_valid: out    vl_logic;
        d_write_rsp_ready: in     vl_logic;
        d_write_rsp_id  : out    vl_logic_vector(0 downto 0);
        d_write_rsp_error: out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of MEM_WORDS : constant is 2;
end pgl50h_mem_fabric;
