# Fixed module boundary contract

All compute and interconnect partitions use `pll_clk_sys` (100 MHz). Every
boundary has registered valid/ready endpoints. There is no combinational
ready path from one physical region through another. The only clock-domain
boundary is the AXI mailbox between `pll_clk_sys` and the HMIC's
`ddrphy_clkin`; its reset is asynchronously asserted and synchronously
released in the destination domain.

## CPU partition

The CPU partition contains the NaxRiscv core and its CPU adapter. Its outward
interfaces are:

* instruction AXI4 read-only master: `ARID[3:0]`, `ARADDR[31:0]`, `ARLEN[3:0]`,
  `ARVALID/ARREADY`, `RID[3:0]`, `RDATA[255:0]`, `RRESP`, `RLAST`,
  `RVALID/RREADY`;
* data AXI4 read/write master with the same read channel plus `AWID`, `AWADDR`,
  `AWLEN`, `AWVALID/AWREADY`, `WDATA[255:0]`, `WSTRB[31:0]`, `WLAST`,
  `WVALID/WREADY`, `BID`, `BRESP`, `BVALID/BREADY`;
* registered AXI-Lite/native CSR sideband for debug and performance counters;
* `timer_irq`, `software_irq`, `external_irq`, `mtime`, `reset` and
  `ddr_init_done` status.

The CPU interface register bank belongs to the CPU partition. The fabric sees
only the registered AXI channels, so CPU timing reports can separate internal
paths from CPU-to-fabric paths.

## AI partition

The AI partition contains the INT8 MAC pipeline, its local control/status
registers and its AXI master. The CSR slave is 32-bit AXI4-Lite with explicit
`AW`, `W`, `B`, `AR` and `R` handshakes. The data master is the same 256-bit,
4-bit-ID AXI4 profile as the CPU. `done_irq` and `error_irq` are sticky until
cleared by the CSR interface.

## DMA partition

The DMA partition exposes the same AXI4-Lite CSR slave shape and a 256-bit AXI4
master. The pixel input is a registered stream (`valid`, `ready`, `data`,
`sof`, `eol`). DMA completion and error are registered interrupt outputs.

## AXI fabric partition

The fabric has four fixed AXI4 master slots: CPU I, CPU D, AI and DMA. It
exports one AXI4 memory master to the HMIC adapter. IDs are preserved through
the fabric. Arbitration and performance counters are local to the fabric;
they are not inferred from module hierarchy names.

## DDR partition

The DDR partition owns the PDS HMIC instance, its official wrapper, DDR3 pins,
training/reset logic and the `ddrphy_clkin` domain. It accepts only the AXI
user-port contract from the CDC mailbox. The HMIC IP hierarchy, clock buffers,
CA/DQS grouping and official physical constraints stay together in this
partition.
