# PGL50H SoC modular implementation flow

This directory defines the modular build contract for `pgl50h_soc`. It is
deliberately kept beside the current production RTL. Existing RTL and the
`-0.017 ns` parent P&R database remain the signoff reference until a modular
candidate passes the parent-context checks.

The PDS implementation model is:

1. compile/synthesize/map each module top with the same clock and boundary
   protocol used by the SoC;
2. validate each module logically and against a timing budget;
3. implement the complete parent once, with non-overlapping physical regions;
4. preserve the parent placement database for later P&R;
5. when a module changes, reuse the parent map and placement database, apply
   only the changed module's region/constraints, and prove that the frozen
   module instance set did not move.

PDS `.adf` files are the database artifacts used by this flow. They are not
   treated as interchangeable module checkpoints. A PDS placement database
   is accepted by `pnr -input_place_db_file`, while a selective module lock is
   accepted only after exact per-instance site names have been obtained and
   verified.

See `module_manifest.json`, `interface_contract.md`, and the scripts under
`scripts/` for the concrete contract and invocation order.
