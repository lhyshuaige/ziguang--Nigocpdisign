# Parent placement observation used for partition planning

The current `-0.017 ns` parent placement was parsed from the copied ADIF
export. The ranges below are internal PDS grid references and are evidence of
the current global placement, not valid `def_region` coordinates for a final
partition:

| logical block | mapped instances | x range | y range |
|---|---:|---:|---:|
| CPU | 14,795 | 21..139 | 3..80 |
| AI | 527 | 31..68 | 14..60 |
| DMA | 1,321 | 9..81 | 13..77 |
| AXI fabric | 2,464 | 9..72 | 13..79 |
| DDR/HMIC | 5,065 | 0..84 | 4..89 |
| clock/reset | 4 | 48..79 | 13..17 |

The overlap is expected from a globally optimized placement, but it means the
current database cannot be converted directly into non-overlapping CPU/AI/DMA
regions. The next physical step is a fresh parent-context region seed that
keeps the official DDR/HMIC region intact, followed by a full P&R comparison
against the `-0.017 ns` parent. A region is accepted only if it closes with
the same or better global and module boundary timing and has no unrouted nets.
