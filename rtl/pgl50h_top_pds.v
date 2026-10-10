// PDS hardware entry point.
//
// The simulation top intentionally keeps the HMIC boundary behind a compile
// switch.  The PDS project cannot rely on a global Verilog define, so this
// small textual wrapper defines the hardware build contract and includes the
// canonical top exactly once in the PDS source list.
`define PGL50H_PDS_DDR3
`define PGL50H_USE_PDS_DDR3
`include "../../rtl/pgl50h_ddr3_boundary.v"
`include "../../rtl/pgl50h_top.v"
