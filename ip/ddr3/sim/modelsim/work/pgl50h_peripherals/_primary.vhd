library verilog;
use verilog.vl_types.all;
entity pgl50h_peripherals is
    port(
        clk             : in     vl_logic;
        reset           : in     vl_logic;
        cmd_valid       : in     vl_logic;
        cmd_write       : in     vl_logic;
        cmd_addr        : in     vl_logic_vector(31 downto 0);
        cmd_wdata       : in     vl_logic_vector(31 downto 0);
        cmd_wstrb       : in     vl_logic_vector(3 downto 0);
        cmd_ready       : out    vl_logic;
        rsp_valid       : out    vl_logic;
        rsp_rdata       : out    vl_logic_vector(31 downto 0);
        rsp_error       : out    vl_logic;
        keys            : in     vl_logic_vector(7 downto 0);
        leds            : out    vl_logic_vector(7 downto 0);
        timer_irq       : out    vl_logic;
        mtime_value     : out    vl_logic_vector(63 downto 0);
        ai_start        : out    vl_logic;
        ai_control      : out    vl_logic_vector(31 downto 0);
        ai_src_addr     : out    vl_logic_vector(31 downto 0);
        ai_dst_addr     : out    vl_logic_vector(31 downto 0);
        ai_length       : out    vl_logic_vector(31 downto 0);
        ai_status_value : in     vl_logic_vector(31 downto 0)
    );
end pgl50h_peripherals;
