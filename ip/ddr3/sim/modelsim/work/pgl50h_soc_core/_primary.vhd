library verilog;
use verilog.vl_types.all;
entity pgl50h_soc_core is
    generic(
        USE_DDR_AXI     : integer := 0;
        HMIC_ADDR_WIDTH : integer := 28;
        HMIC_DATA_WIDTH : integer := 256
    );
    port(
        clk             : in     vl_logic;
        reset           : in     vl_logic;
        ddr_init_done   : in     vl_logic;
        keys            : in     vl_logic_vector(7 downto 0);
        leds            : out    vl_logic_vector(7 downto 0);
        timer_irq       : out    vl_logic;
        mtime           : out    vl_logic_vector(63 downto 0);
        software_irq    : in     vl_logic;
        external_irq    : in     vl_logic;
        ai_start        : out    vl_logic;
        ai_control      : out    vl_logic_vector(31 downto 0);
        ai_src_addr     : out    vl_logic_vector(31 downto 0);
        ai_dst_addr     : out    vl_logic_vector(31 downto 0);
        ai_length       : out    vl_logic_vector(31 downto 0);
        axi_awaddr      : out    vl_logic_vector;
        axi_awuser_ap   : out    vl_logic;
        axi_awuser_id   : out    vl_logic_vector(3 downto 0);
        axi_awlen       : out    vl_logic_vector(3 downto 0);
        axi_awready     : in     vl_logic;
        axi_awvalid     : out    vl_logic;
        axi_wdata       : out    vl_logic_vector;
        axi_wstrb       : out    vl_logic_vector;
        axi_wready      : in     vl_logic;
        axi_wusero_id   : in     vl_logic_vector(3 downto 0);
        axi_wusero_last : in     vl_logic;
        axi_araddr      : out    vl_logic_vector;
        axi_aruser_ap   : out    vl_logic;
        axi_aruser_id   : out    vl_logic_vector(3 downto 0);
        axi_arlen       : out    vl_logic_vector(3 downto 0);
        axi_arready     : in     vl_logic;
        axi_arvalid     : out    vl_logic;
        axi_rdata       : in     vl_logic_vector;
        axi_rid         : in     vl_logic_vector(3 downto 0);
        axi_rlast       : in     vl_logic;
        axi_rvalid      : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of USE_DDR_AXI : constant is 2;
    attribute mti_svvh_generic_type of HMIC_ADDR_WIDTH : constant is 2;
    attribute mti_svvh_generic_type of HMIC_DATA_WIDTH : constant is 2;
end pgl50h_soc_core;
