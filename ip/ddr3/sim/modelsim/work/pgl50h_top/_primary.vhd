library verilog;
use verilog.vl_types.all;
entity pgl50h_top is
    generic(
        USE_DDR_AXI     : integer := 0;
        HMIC_ADDR_WIDTH : integer := 28;
        HMIC_DATA_WIDTH : integer := 256
    );
    port(
        clk_50m         : in     vl_logic;
        reset_n         : in     vl_logic;
        key_n           : in     vl_logic_vector(7 downto 0);
        led             : out    vl_logic_vector(7 downto 0);
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
        ddr3_dqs_n      : inout  vl_logic_vector(3 downto 0);
        qspi_cs_n       : out    vl_logic;
        qspi_sck        : out    vl_logic;
        qspi_dq         : inout  vl_logic_vector(3 downto 0);
        ext_io          : inout  vl_logic_vector(33 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of USE_DDR_AXI : constant is 2;
    attribute mti_svvh_generic_type of HMIC_ADDR_WIDTH : constant is 2;
    attribute mti_svvh_generic_type of HMIC_DATA_WIDTH : constant is 2;
end pgl50h_top;
