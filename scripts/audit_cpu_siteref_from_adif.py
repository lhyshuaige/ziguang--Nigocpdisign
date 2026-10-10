"""Compare every mapped CPU SITEREF in placed and routed PDS ADIF exports.

The exported SITEREF is an internal grid reference, not a complete PCF
`def_inst_site` name. This script intentionally does not emit a lock PCF.
"""

from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path


INSTANCE = re.compile(r"^\s*\(INSTANCE \\([^\s]+).*?\(OPERAREF ([^\s()]+)")
SITE_REF = re.compile(r"\(SITEREF (\d+) (\d+)\)")
INSTANCE_END = re.compile(r"^          \)\s*$")
CPU_PREFIX = "u_soc_core/u_cpu/"


def hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def parse_cpu_instances(path: Path) -> dict[str, tuple[str, str, int | None, int | None]]:
    result: dict[str, tuple[str, str, int | None, int | None]] = {}
    name: str | None = None
    op: str | None = None
    site: tuple[int, int] | None = None

    def finish() -> None:
        if name is None or not name.startswith(CPU_PREFIX):
            return
        canonical = re.sub(r"_perm$", "", name)
        if canonical in result:
            raise RuntimeError(f"Duplicate canonical CPU instance in {path}: {canonical}")
        result[canonical] = (name, op or "", *(site if site is not None else (None, None)))

    with path.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            match = INSTANCE.match(line)
            if match:
                finish()
                name, op, site = match.group(1), match.group(2), None
                continue
            if name is not None:
                match = SITE_REF.search(line)
                if match:
                    site = (int(match.group(1)), int(match.group(2)))
                if INSTANCE_END.match(line):
                    finish()
                    name = op = None
                    site = None
    finish()
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--placed", type=Path, required=True)
    parser.add_argument("--routed", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()

    placed = parse_cpu_instances(args.placed)
    routed = parse_cpu_instances(args.routed)
    missing_place = [name for name, (_, _, x, y) in placed.items() if x is None or y is None]
    missing_route = [name for name, (_, _, x, y) in routed.items() if x is None or y is None]
    only_placed = sorted(placed.keys() - routed.keys())
    only_routed = sorted(routed.keys() - placed.keys())
    mismatched = [
        name
        for name in placed.keys() & routed.keys()
        if placed[name][1:] != routed[name][1:]
    ]

    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    with args.manifest.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write("placed_instance\trouted_instance\top\tgrid_x\tgrid_y\tverified_in_routed_db\n")
        for name in sorted(placed):
            raw, op, x, y = placed[name]
            routed_raw = routed[name][0] if name in routed else ""
            stream.write(
                f"{raw}\t{routed_raw}\t{op}\t{x if x is not None else ''}\t"
                f"{y if y is not None else ''}\t"
                f"{int(name in routed and placed[name][1:] == routed[name][1:])}\n"
            )

    print(f"PLACED_ADIF_SHA256={hash_file(args.placed)}")
    print(f"ROUTED_ADIF_SHA256={hash_file(args.routed)}")
    print(f"CPU_PLACED_INSTANCE_COUNT={len(placed)}")
    print(f"CPU_ROUTED_INSTANCE_COUNT={len(routed)}")
    print(f"CPU_MISSING_PLACED_SITEREF={len(missing_place)}")
    print(f"CPU_MISSING_ROUTED_SITEREF={len(missing_route)}")
    print(f"CPU_ONLY_PLACED={len(only_placed)}")
    print(f"CPU_ONLY_ROUTED={len(only_routed)}")
    print(f"CPU_PLACEMENT_MISMATCHES={len(mismatched)}")
    print(f"MANIFEST={args.manifest}")
    for label, names in [
        ("MISSING_PLACE", missing_place),
        ("MISSING_ROUTE", missing_route),
        ("ONLY_PLACED", only_placed),
        ("ONLY_ROUTED", only_routed),
        ("MISMATCHED", mismatched),
    ]:
        for name in names[:10]:
            print(label, name)
    if missing_place or missing_route or only_placed or only_routed or mismatched:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
