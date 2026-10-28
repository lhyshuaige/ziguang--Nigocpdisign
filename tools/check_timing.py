"""Check A30's archived STA summaries or freshly generated PDS reports."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'a30/evidence'


def header(path):
    lines = []
    with Path(path).open(encoding='utf-8-sig', errors='replace') as stream:
        for line in stream:
            if line.startswith('Startpoint  : '):
                break
            lines.append(line)
    return ''.join(lines)


def section(text, kind, corner):
    title = f'{kind} Summary({corner} Corner):'
    assert title in text, (title, 'not in report')
    body = text.split(title, 1)[1].split('================================', 1)[0]
    rows = []
    for m in re.finditer(r'^\s*(\w+)\s+(\w+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$', body, re.M):
        rows.append({'launch': m[1], 'capture': m[2], 'worst_ns': float(m[3]),
                     'tns_ns': float(m[4]), 'failing_endpoints': int(m[5])})
    assert rows, (title, 'has no timing rows')
    return {'worst_ns': min(x['worst_ns'] for x in rows),
            'failing_endpoints': sum(x['failing_endpoints'] for x in rows),
            'tns_ns': round(sum(x['tns_ns'] for x in rows), 3), 'groups': rows}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--setup', type=Path, default=EVIDENCE / 'setup_summary.txt')
    ap.add_argument('--hold', type=Path, default=EVIDENCE / 'hold_summary.txt')
    ap.add_argument('--expect-a30', action='store_true', help='require the recorded A30 endpoint counts and WNS/WHS')
    args = ap.parse_args()
    setup, hold = header(args.setup), header(args.hold)
    result = {}
    for corner in ('Slow', 'Fast'):
        result[f'setup_{corner.lower()}'] = section(setup, 'Setup', corner)
        result[f'hold_{corner.lower()}'] = section(hold, 'Hold', corner)
    if args.expect_a30:
        expected = json.loads((EVIDENCE / 'timing_result.json').read_text(encoding='utf-8'))
        for key, row in result.items():
            old = expected[key]
            assert abs(row['worst_ns'] - old['worst_ns']) < 0.0005, (key, row, old)
            assert row['failing_endpoints'] == old['failing_endpoints'], (key, row, old)
        negatives = json.loads((EVIDENCE / 'all_negative_paths.json').read_text(encoding='utf-8'))
        fast = {(p['clock'], p['endpoint']) for p in negatives if p['type'] == 'min (fast corner)'}
        assert len(fast) == result['hold_fast']['failing_endpoints'] == 5
    for key, row in result.items():
        print(f"{key:12s} worst={row['worst_ns']:+.3f} ns  failing_endpoints={row['failing_endpoints']}  TNS={row['tns_ns']:+.3f} ns")
    if args.expect_a30:
        print('A30_TIMING_EVIDENCE_PASS')


if __name__ == '__main__':
    main()
