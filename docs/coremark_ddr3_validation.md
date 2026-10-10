# DDR3 CoreMark validation

The existing functional baseline is the contest `Issue24/ROB32` image running
from the fallback memory fabric:

* `coremark.memh`: `coremark_divmul_run/coremark.memh`
* reference cycles: `2,100,965`
* reference score: about `4.76 CoreMark/MHz` at the existing ~100 MHz target

The current RTL CPU refill comparison is recorded in
`docs/axi_fabric_validation.md`: the legacy native bridge takes 221 cycles in
the deterministic CPU-to-DDR behavior test, while `USE_AXI_FABRIC=1` takes 229
cycles with zero CPU memory response errors.  The measured increase is about
two system clocks per independent 64-byte refill (eight clocks over this
four-refill directed program).  This is a path microbenchmark only; it must not
be reported as a CoreMark score or as proof of DDR3 timing closure.

## Board run

1. Build the PDS project with `PGL50H_USE_PDS_PLL` and
   `PGL50H_USE_PDS_DDR3` defined. Add the generated HMIC PDS project and the
   board timing/pin files from `constraints/`.
2. Place `coremark.memh` at the boot-memory load address used by the current
   NaxRiscv linker script (`0x8000_0000` in the bridge address map).
3. Wait for `ddr_init_done` before releasing the CPU. The top-level reset
   boundary already gates `soc_reset_n` with HMIC initialization and lock.
4. Run the same 10-iteration performance image used for the baseline and
   capture the UART result plus the start/end `mtime` values.
5. Compute `CoreMark/MHz = iterations * 1000 / elapsed_cycles` when the CPU
   clock is 100 MHz. Record DDR training status, clock frequency, cycles, and
   CRC values together; a CRC mismatch is a failed run even if the cycle count
   looks plausible.

## Acceptance check

The bridge contract test and the fallback SoC smoke tests are simulation gates,
not DDR3 performance measurements. The DDR3 result is accepted only after the
same CoreMark binary passes on hardware and the cycle count is within the
project's agreed tolerance of the fallback reference. A successful PDS IP
generation or RTL lint run alone does not constitute a DDR3 CoreMark result.
