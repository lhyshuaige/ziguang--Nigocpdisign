"""Generate independent max/min PDS STA commands for a routed native database.

This prepares a script only; it does not invoke PDS or modify the routed DB.
"""
import argparse
import hashlib
import json
from pathlib import Path

TOP = 'pg2l100h_soc_top'
A30_SHA256 = 'fd5e0f609cc2ac83edbdac6b11894ec31eb87124573bbd0c8685f8c5b4cb85f8'


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def q(path):
    return '{' + path.resolve().as_posix() + '}'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--native-run', type=Path, required=True,
                    help='PDS run directory containing soc_physical.pds and place_route/*_pnr.adf')
    ap.add_argument('--out', type=Path, required=True,
                    help='separate output directory for the Tcl script and copied reports')
    ap.add_argument('--allow-other-db', action='store_true',
                    help='allow a new routed candidate instead of exact A30 DB')
    args = ap.parse_args()
    native = args.native_run.resolve()
    project = native / 'soc_physical.pds'
    routed = native / f'place_route/{TOP}_pnr.adf'
    report = native / f'report_timing/{TOP}.rtr'
    assert project.is_file() and routed.is_file(), 'missing native PDS project or routed DB'
    digest = sha(routed)
    assert args.allow_other_db or digest == A30_SHA256, (
        'This is not the byte-exact A30 routed DB; use --allow-other-db for a new candidate', digest)
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    script = out / 'independent_sta.tcl'
    assert not script.exists(), 'refusing to overwrite an existing STA Tcl script'
    lines = ['open_project ' + q(project)]
    for mode, limit, filename in [('max', 1000, 'setup.rtr'), ('min', 10000, 'hold.rtr')]:
        lines.append('report_timing -force_to_run -input_db_file ' + q(routed) +
                     f' -delay_type {mode} -max_path {limit} -report_io_datasheet -report_max_skew -report_exception TRUE')
        lines.append('file copy -force ' + q(report) + ' ' + q(out / filename))
    lines.extend(['puts {INDEPENDENT_STA_DONE}', 'exit'])
    script.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    (out / 'input.json').write_text(json.dumps({'project': str(project), 'routed_db': str(routed),
        'routed_db_sha256': digest, 'byte_exact_A30_DB': digest == A30_SHA256,
        'script': str(script)}, indent=2) + '\n', encoding='utf-8')
    print('STA_TCL_PREPARED', script, 'A30_DB_MATCH', digest == A30_SHA256)


if __name__ == '__main__':
    main()
