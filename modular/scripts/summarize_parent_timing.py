"""Summarize PDS .rtr paths by logical module and slack."""
from __future__ import annotations

import argparse
import re
from pathlib import Path

START = re.compile(r"^Startpoint\s+:\s+(.*)$")
END = re.compile(r"^Endpoint\s+:\s+(.*)$")
GROUP = re.compile(r"^Path Group\s+:\s+(.*)$")
SLACK = re.compile(r"^Slack \((?:VIOLATED|MET)\)\s+(-?\d+\.\d+)")
LOGIC_ROUTE = re.compile(r"Logic:\s+([0-9.]+)ns\([^)]*\), Route:\s+([0-9.]+)ns")


def owner(path: str) -> str:
    p = path.lower()
    if "u_soc_core/u_cpu" in p:
        return "CPU"
    if "u_ai_engine" in p:
        return "AI"
    if "u_camera_dma" in p:
        return "DMA"
    if "u_axi_fabric" in p or "g_axi_fabric" in p:
        return "AXI"
    if "u_ddr3" in p or "ddrphy" in p or "hmic" in p:
        return "DDR/HMIC"
    if "u_clock_reset" in p:
        return "CLOCK/RESET"
    return "OTHER"


def parse(path: Path):
    current: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        raw = raw_line.strip()
        for rx, key in ((START, "start"), (END, "end"), (GROUP, "group")):
            m = rx.match(raw)
            if m:
                current[key] = m.group(1).strip()
                break
        else:
            m = SLACK.match(raw)
            if m:
                current["slack"] = m.group(1)
                current["owner"] = owner(current.get("start", "") + " " + current.get("end", ""))
                yield current
                current = {}
                continue
            m = LOGIC_ROUTE.search(raw)
            if m and "slack" not in current:
                current["logic"] = m.group(1)
                current["route"] = m.group(2)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("report", type=Path)
    ap.add_argument("--near", type=float, default=0.30)
    args = ap.parse_args()
    rows = [r for r in parse(args.report) if float(r["slack"]) <= args.near]
    rows.sort(key=lambda r: float(r["slack"]))
    print("rank\towner\tslack_ns\tgroup\tstartpoint\tendpoint")
    for i, row in enumerate(rows, 1):
        print(f"{i}\t{row.get('owner','')}\t{row['slack']}\t{row.get('group','')}\t{row.get('start','')}\t{row.get('end','')}")
    print("\nCOUNTS")
    counts: dict[str, int] = {}
    for row in rows:
        counts[row.get("owner", "OTHER")] = counts.get(row.get("owner", "OTHER"), 0) + 1
    for key, count in sorted(counts.items()):
        print(f"{key}\t{count}")


if __name__ == "__main__":
    main()
