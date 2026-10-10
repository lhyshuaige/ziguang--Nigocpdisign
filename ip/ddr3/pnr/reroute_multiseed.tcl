set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
pnr -input_db_file {device_map/test_ddr_map.adf} \
    -input_place_db_file {place_route/test_ddr_plc.adf} \
    -groute_seed 7 -groute_times 4 -route_seed_step 31 \
    -route_saved_outcome 1 -route_parallel 4 \
    -fast_router TRUE -congest_overlap_limit 20 -report_timing
