library verilog;
use verilog.vl_types.all;
entity PrefetchPredictor is
    port(
        io_learn_valid  : in     vl_logic;
        io_learn_payload_physical: in     vl_logic_vector(31 downto 0);
        io_learn_payload_allocate: in     vl_logic;
        io_prediction_cmd_valid: out    vl_logic;
        io_prediction_cmd_ready: in     vl_logic;
        io_prediction_cmd_payload: out    vl_logic_vector(31 downto 0);
        io_prediction_rsp_valid: in     vl_logic;
        io_prediction_rsp_payload: in     vl_logic
    );
end PrefetchPredictor;
