-- Created by IP Generator (Version 2022.2-SP6.7.1 build 188940)
-- Instantiation Template
--
-- Insert the following codes into your VHDL file.
--   * Change the_instance_name to your own instance name.
--   * Change the net names in the port map.


COMPONENT pgl50h_hmic_ddr3
  PORT (
    ref_clk : IN STD_LOGIC;
    resetn : IN STD_LOGIC;
    ddr_init_done : OUT STD_LOGIC;
    ddrphy_clkin : OUT STD_LOGIC;
    pll_lock : OUT STD_LOGIC
  );
END COMPONENT;


the_instance_name : pgl50h_hmic_ddr3
  PORT MAP (
    ref_clk => ref_clk,
    resetn => resetn,
    ddr_init_done => ddr_init_done,
    ddrphy_clkin => ddrphy_clkin,
    pll_lock => pll_lock
  );
