library verilog;
use verilog.vl_types.all;
entity pgl50h_axi4_mem_fabric is
    generic(
        ADDR_WIDTH      : integer := 32;
        DATA_WIDTH      : integer := 256;
        ID_WIDTH        : integer := 4
    );
    port(
        clk             : in     vl_logic;
        reset           : in     vl_logic;
        init_done       : out    vl_logic;
        axi_awid        : in     vl_logic_vector;
        axi_awaddr      : in     vl_logic_vector;
        axi_awlen       : in     vl_logic_vector(3 downto 0);
        axi_awvalid     : in     vl_logic;
        axi_awready     : out    vl_logic;
        axi_wdata       : in     vl_logic_vector;
        axi_wstrb       : in     vl_logic_vector;
        axi_wlast       : in     vl_logic;
        axi_wvalid      : in     vl_logic;
        axi_wready      : out    vl_logic;
        axi_bid         : out    vl_logic_vector;
        axi_bresp       : out    vl_logic_vector(1 downto 0);
        axi_bvalid      : out    vl_logic;
        axi_bready      : in     vl_logic;
        axi_arid        : in     vl_logic_vector;
        axi_araddr      : in     vl_logic_vector;
        axi_arlen       : in     vl_logic_vector(3 downto 0);
        axi_arvalid     : in     vl_logic;
        axi_arready     : out    vl_logic;
        axi_rid         : out    vl_logic_vector;
        axi_rdata       : out    vl_logic_vector;
        axi_rresp       : out    vl_logic_vector(1 downto 0);
        axi_rlast       : out    vl_logic;
        axi_rvalid      : out    vl_logic;
        axi_rready      : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of ADDR_WIDTH : constant is 2;
    attribute mti_svvh_generic_type of DATA_WIDTH : constant is 2;
    attribute mti_svvh_generic_type of ID_WIDTH : constant is 2;
end pgl50h_axi4_mem_fabric;
