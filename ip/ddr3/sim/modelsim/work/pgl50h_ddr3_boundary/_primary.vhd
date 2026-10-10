library verilog;
use verilog.vl_types.all;
entity pgl50h_ddr3_boundary is
    generic(
        HMIC_ADDR_WIDTH : integer := 28;
        HMIC_DATA_WIDTH : integer := 256
    );
    port(
        clk_sys         : in     vl_logic;
        reset           : in     vl_logic;
        ref_clk         : in     vl_logic;
        reset_n         : in     vl_logic;
        init_done       : out    vl_logic;
        ddrphy_clkin    : out    vl_logic;
        pll_lock        : out    vl_logic;
        axi_awaddr      : in     vl_logic_vector;
        axi_awuser_ap   : in     vl_logic;
        axi_awuser_id   : in     vl_logic_vector(3 downto 0);
        axi_awlen       : in     vl_logic_vector(3 downto 0);
        axi_awready     : out    vl_logic;
        axi_awvalid     : in     vl_logic;
        axi_wdata       : in     vl_logic_vector;
        axi_wstrb       : in     vl_logic_vector;
        axi_wready      : out    vl_logic;
        axi_wusero_id   : out    vl_logic_vector(3 downto 0);
        axi_wusero_last : out    vl_logic;
        axi_araddr      : in     vl_logic_vector;
        axi_aruser_ap   : in     vl_logic;
        axi_aruser_id   : in     vl_logic_vector(3 downto 0);
        axi_arlen       : in     vl_logic_vector(3 downto 0);
        axi_arready     : out    vl_logic;
        axi_arvalid     : in     vl_logic;
        axi_rdata       : out    vl_logic_vector;
        axi_rid         : out    vl_logic_vector(3 downto 0);
        axi_rlast       : out    vl_logic;
        axi_rvalid      : out    vl_logic;
        ddr3_addr       : out    vl_logic_vector(15 downto 0);
        ddr3_ba         : out    vl_logic_vector(2 downto 0);
        ddr3_ras_n      : out    vl_logic;
        ddr3_cas_n      : out    vl_logic;
        ddr3_we_n       : out    vl_logic;
        ddr3_reset_n    : out    vl_logic;
        ddr3_ck_p       : out    vl_logic;
        ddr3_ck_n       : out    vl_logic;
        ddr3_cke        : out    vl_logic;
        ddr3_cs_n       : out    vl_logic;
        ddr3_odt        : out    vl_logic;
        ddr3_dm         : out    vl_logic_vector(3 downto 0);
        ddr3_dq         : inout  vl_logic_vector(31 downto 0);
        ddr3_dqs_p      : inout  vl_logic_vector(3 downto 0);
        ddr3_dqs_n      : inout  vl_logic_vector(3 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of HMIC_ADDR_WIDTH : constant is 2;
    attribute mti_svvh_generic_type of HMIC_DATA_WIDTH : constant is 2;
end pgl50h_ddr3_boundary;
