"""Clear selected non-CPU SITEREF entries from an exported PDS ADIF copy.

The parent export remains unchanged. The output is experimental until PDS
round-trip conversion and placement validation both pass.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


INSTANCE = re.compile(r"^\s*\(INSTANCE \\([^\s]+)")
SITE_REF = re.compile(r"^\s*\(SITEREF \d+ \d+\)\s*$")
INSTANCE_END = re.compile(r"^          \)\s*$")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--unplace-prefix", required=True)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--move-to", nargs=2, type=int, metavar=("GRID_X", "GRID_Y"))
    args = parser.parse_args()
    if args.input.resolve() == args.output.resolve():
        raise ValueError("Output must not overwrite the parent ADIF")

    current: str | None = None
    removed = 0
    with args.input.open(encoding="utf-8", errors="strict") as src, args.output.open(
        "w", encoding="utf-8", newline="\n"
    ) as dst:
        for line in src:
            match = INSTANCE.match(line)
            if match:
                current = match.group(1)
            if (
                current is not None
                and current.startswith(args.unplace_prefix)
                and SITE_REF.match(line)
                and (args.limit == 0 or removed < args.limit)
            ):
                removed += 1
                if args.move_to is not None:
                    dst.write(f"            (SITEREF {args.move_to[0]} {args.move_to[1]})\n")
                continue
            dst.write(line)
            if current is not None and INSTANCE_END.match(line):
                current = None
    print(f"Modified SITEREF entries: {removed}; move-to={args.move_to}")
    if removed == 0:
        raise RuntimeError("No matching placed instances were found")


if __name__ == "__main__":
    main()
