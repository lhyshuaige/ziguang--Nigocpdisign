"""Isolated CoreMark compiler experiment; never overwrites the release or Flash."""
import argparse
import hashlib
import json
import os
import re
import secrets
import shutil
import statistics
import subprocess
import sys
import time
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'upper'))
from nigo_host.program import pack_image, validate_image

FLAGS = '''-march=rv32im_zicsr -mabi=ilp32 -mcmodel=medany
-O3 -fno-common -funroll-loops -funroll-all-loops
-finline-functions -finline-limit=1000
-fno-if-conversion2 -fselective-scheduling
-fno-crossjumping -freorder-blocks-and-partition
-mtune=sifive-7-series
-falign-functions=32 -falign-loops=4 -falign-jumps=8
-ffreestanding -fno-builtin -nostdlib -nostartfiles'''.split()
LINK_ONLY = ['-nostdlib', '-nostartfiles']
PLATFORM = ['-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra',
            '-Werror', '-Wno-misleading-indentation']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def recipe():
    return json.loads((ROOT / 'firmware/recipes/runtime.json').read_text())


def build(args):
    ref = recipe()
    for rel, digest in ref['input_sha256'].items():
        assert sha(ROOT / rel) == digest, 'Reference source changed: ' + rel
    out = HERE / 'build/candidate'
    out.mkdir(parents=True, exist_ok=False)
    (out / 'obj').mkdir()
    tools = Path(args.tools)
    gcc = str(tools / 'riscv64-unknown-elf-gcc')
    compiler = subprocess.check_output([gcc, '--version'], text=True).splitlines()[0]
    assert '13.2.0' in compiler, compiler
    identity = hashlib.sha256(json.dumps(dict(reference=ref['binary_sha256'],
        flags=FLAGS, platform=PLATFORM, compiler=compiler), sort_keys=True).encode()).hexdigest()[:8]
    cflags = [flag for flag in FLAGS if flag not in LINK_ONLY]
    (out / 'build_info.h').write_text(''.join('#define %s 0x%su\n' % (name, identity)
        for name in ['RUNTIME_BUILD_ID', 'FACE_BUILD_ID', 'CM_BUILD_ID']) +
        '#define CM_COMPILER_FLAGS ' + json.dumps(' '.join(FLAGS + PLATFORM)) + '\n')
    commands = []
    changed = []
    def run(cmd, label):
        commands.append(cmd)
        result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        (out / (label + '.log')).write_text(result.stdout + result.stderr)
        if result.returncode:
            print(result.stdout + result.stderr, flush=True)
            result.check_returncode()
        return result.stdout
    for index, raw in enumerate(ref['commands']):
        raw = list(raw)
        if '-O3' in raw:
            # Keep includes, source/object order, definitions and linker script.
            # Replace compiler options in the existing CoreMark group and link.
            tail = [a for a in raw[1:] if a.startswith(('-I', '-D', '@OUT@/', '@REPO@/', '-Wl,'))
                    or a in ['-c', '-o', '-lgcc']]
            raw = ['@TOOLS@/riscv64-unknown-elf-gcc', *cflags, *PLATFORM, *tail]
            if '-c' not in raw:
                raw[1:1] = LINK_ONLY
            changed.append(index)
        cmd = [a.replace('@REPO@', ROOT.as_posix()).replace('@OUT@', out.as_posix())
               .replace('@TOOLS@', tools.as_posix()) for a in raw]
        run(cmd, '%02d_compile' % index)
    assert changed == list(range(19, 27)) + [30], changed
    for group in ['target', 'optimizers']:
        value = run([gcc, *cflags, '-Q', '--help=' + group, '-c', '-x', 'c',
                     '/dev/null', '-o', str(out / 'option_probe.o')], 'probe_' + group)
        (out / ('effective_' + group + '.txt')).write_text(value)
    opts = (out / 'effective_optimizers.txt').read_text()
    for name, expected in [('functions', '32'), ('loops', '4'), ('jumps', '8')]:
        match = re.search(r'-falign-' + name + r'=\s+(\S+)', opts)
        assert match and match[1] == expected, (name, match)
    run([str(tools / 'riscv64-unknown-elf-objcopy'), '-O', 'binary',
         str(out / 'runtime.elf'), str(out / 'runtime.bin')], 'objcopy')
    attrs = run([str(tools / 'riscv64-unknown-elf-readelf'), '-A', str(out / 'runtime.elf')], 'attributes')
    assert 'rv32i' in attrs and '_m' in attrs and '_zicsr' in attrs, attrs
    undefined = run([str(tools / 'riscv64-unknown-elf-nm'), '-u', str(out / 'runtime.elf')], 'undefined')
    assert not undefined.strip(), undefined
    size = run([str(tools / 'riscv64-unknown-elf-size'), str(out / 'runtime.elf')], 'size')
    symbols = run([str(tools / 'riscv64-unknown-elf-nm'), '-n', str(out / 'runtime.elf')], 'symbols')
    assert re.search(r'^82000000 T _start$', symbols, re.M), 'Wrong entry'
    image = pack_image((out / 'runtime.bin').read_bytes())
    validate_image(image)
    (out / 'runtime.ngb').write_bytes(image)
    report = dict(status='BUILT_BOARD_PENDING', profile='align32_loop4_jump8',
        build_id=identity, compiler=compiler, requested_flags=FLAGS, platform_flags=PLATFORM,
        changed_recipe_commands=changed, commands=commands, input_sha256=ref['input_sha256'],
        reference_build_id=ref['build_id'], reference_binary_sha256=ref['binary_sha256'],
        binary_bytes=len(image)-32, binary_sha256=sha(out/'runtime.bin'),
        ngb_sha256=sha(out/'runtime.ngb'), ngb_bytes=len(image), size=size,
        release_assets_modified=False, rtl_modified=False, physical_flash_written=False)
    save(out / 'build.json', report)
    print(json.dumps({k: report[k] for k in ['status', 'build_id', 'binary_bytes', 'size']}), flush=True)


def measure(args):
    from nigo_host.client import Endpoint, Host
    from nigo_host.coremark import CoreMarkClient, parse_result
    from nigo_host.modes import ModeClient
    ref = recipe()
    candidate = HERE / 'build/candidate'
    metadata = ref if args.profile == 'baseline' else json.loads((candidate/'build.json').read_text())
    expected_build = int(metadata['build_id'], 16)
    out = HERE / 'results' / (args.profile + '_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    out.mkdir(parents=True, exist_ok=False)
    report = dict(status='RUNNING', profile=args.profile, build_id=metadata['build_id'],
        iterations=args.iterations, repetitions=args.repeats, cpu_hz=100000000,
        ngb_sha256=metadata['ngb_sha256'], results=[], fpga_programmed=False,
        physical_flash_written=False, explicit_peripheral_disable=False,
        workload='Unified runtime mode 3, no network polling in measured region')
    save(out/'summary.json', report)
    endpoint = Endpoint()
    try:
        if args.install:
            assert args.profile == 'candidate', 'Install only the isolated candidate'
            blob = (candidate/'runtime.ngb').read_bytes()
            assert hashlib.sha256(blob).hexdigest() == metadata['ngb_sha256']
            host = Host(endpoint)
            boot = host.boot_query()  # Must positively identify ROM before any DDR writes.
            download = host.program(blob)
            save(out/'download.json', dict(boot=boot, download=download, build_id=metadata['build_id']))
            time.sleep(1)
        with closing(ModeClient(endpoint)) as mode:
            state = mode.call(1)
            assert state['build_id'] == expected_build, 'Unexpected resident firmware: %08x' % state['build_id']
            report['initial_mode'] = state
            state = mode.select(3)
            assert state['build_id'] == expected_build and not state['busy'] and not state['flags'], state
            report['selected_mode'] = state
            save(out/'summary.json', report)
            with closing(CoreMarkClient(endpoint)) as cm:
                for index in range(1, args.repeats+1):
                    before = mode.call(1)
                    assert before['build_id'] == expected_build and before['active'] == before['target'] == 3
                    assert cm.call(1)['state'] != 1, 'A benchmark is already running'
                    run_id = secrets.randbits(32) or 1
                    prefix = out / ('%02d' % index)
                    save(prefix.with_suffix('.request.json'), dict(run_id=run_id,
                         iterations=args.iterations, before=before, started_utc=datetime.now(timezone.utc).isoformat()))
                    print('START', args.profile, index, 'iterations', args.iterations, 'run_id', run_id, flush=True)
                    try:
                        cm.call(2, run_id, args.iterations)
                    except TimeoutError:
                        pass  # A lost START ACK never justifies inventing a second run.
                    deadline = time.monotonic() + 180
                    while time.monotonic() < deadline:
                        try:
                            state = cm.call(1, run_id, retries=2)
                            if state['state'] == 2:
                                break
                        except TimeoutError:
                            pass
                        time.sleep(.3)
                    else:
                        raise TimeoutError('Result pending; do not restart without querying the same run ID')
                    raw = bytearray()
                    while len(raw) < state['log_length']:
                        part = cm.call(3, run_id, len(raw))
                        assert part['offset'] == len(raw) and part['data']
                        assert all(part[k] == state[k] for k in ['build_id', 'log_length', 'log_crc', 'performance_ticks', 'validation_ticks'])
                        raw.extend(part['data'])
                    prefix.with_suffix('.txt').write_bytes(raw)
                    save(prefix.with_suffix('.state.json'), {k: v for k, v in state.items() if k != 'data'})
                    result = parse_result(state, bytes(raw))
                    save(prefix.with_suffix('.json'), result)
                    assert result['valid'] and result['build_id'] == metadata['build_id'], result
                    assert all(r['iterations'] == args.iterations for r in result['runs'])
                    after = mode.call(1)
                    assert all(before[k] == after[k] for k in ['build_id', 'generation', 'active', 'target']), after
                    report['results'].append(dict(index=index, coremark=result['coremark'],
                        coremark_per_mhz=result['coremark_per_mhz'], runs=result['runs'], run_id=run_id))
                    save(out/'summary.json', report)
                    print('PASS', args.profile, index, 'CoreMark', result['coremark'],
                          'CoreMark/MHz', result['coremark_per_mhz'], flush=True)
        values = [r['coremark'] for r in report['results']]
        report.update(status='PASS', mean=statistics.mean(values), median=statistics.median(values),
                      minimum=min(values), maximum=max(values))
    except Exception as error:
        report.update(status='FAIL_OR_PENDING', error=repr(error))
        raise
    finally:
        save(out/'summary.json', report)
        print('EVIDENCE', out/'summary.json', flush=True)


def native(args):
    """Existing CRC/RPC regression on host; never report host speed as CPU speed."""
    out = HERE / 'build/candidate'
    assert (out/'build_info.h').is_file(), 'Build the candidate first'
    cm = ROOT/'upper/firmware/coremark'
    flags = [f for f in FLAGS if f not in LINK_ONLY and not f.startswith(
        ('-march=', '-mabi=', '-mcmodel=', '-mtune='))]
    sources = [cm/'tests/native.c', cm/'port/service.c', cm/'port/core_portme.c']
    sources += [cm/'upstream'/n for n in ['core_main.c', 'core_list_join.c',
                                        'core_matrix.c', 'core_state.c', 'core_util.c']]
    executable = out/'native_test.exe'
    command = [args.cc, '-std=c11', *flags, '-Wall', '-Wextra', '-Werror',
        '-DTOTAL_DATA_SIZE=2000', '-DCM_HOST_TEST', '-Dmain=coremark_main',
        *['-I'+str(p) for p in [cm/'port', cm/'upstream', out]],
        *map(str, sources), '-o', str(executable)]
    subprocess.run(command, check=True)
    result = subprocess.run([str(executable)], capture_output=True, text=True)
    (out/'native_result.txt').write_text(result.stdout+result.stderr)
    result.check_returncode()
    assert 'NATIVE_FUNCTIONAL_AND_RPC_PASS' in result.stdout
    save(HERE/'results/native.json', dict(status='PASS',
        scope='Native CRC and RPC regression; does not measure Nigo CPU performance',
        build_id=json.loads((out/'build.json').read_text())['build_id'], command=command,
        excluded_host_inapplicable_flags=[f for f in FLAGS if f not in flags]))
    print('NATIVE_CRC_RPC_PASS (not a board score)', flush=True)


def compare(args):
    reports = []
    for name, path in [('baseline', args.baseline), ('candidate', args.candidate)]:
        path = Path(path).resolve()
        data = json.loads(path.read_text())
        assert data['status'] == 'PASS' and data['profile'] == name
        values = []
        for item in data['results']:
            prefix = path.parent / ('%02d' % item['index'])
            state = json.loads(prefix.with_suffix('.state.json').read_text())
            raw = prefix.with_suffix('.txt').read_bytes()
            from nigo_host.coremark import parse_result
            result = parse_result(state, raw)
            assert result['valid'] and result['build_id'] == data['build_id']
            assert all(r['iterations'] == data['iterations'] for r in result['runs'])
            assert result['coremark'] == item['coremark']
            values.append(result['coremark'])
        assert len(values) == data['repetitions']
        reports.append(dict(profile=name, build_id=data['build_id'],
            ngb_sha256=data['ngb_sha256'], evidence=path.relative_to(HERE).as_posix(),
            iterations_per_group=data['iterations'], repetitions=data['repetitions'],
            scores=values, mean=statistics.mean(values), median=statistics.median(values),
            minimum=min(values), maximum=max(values), stdev=statistics.stdev(values) if len(values)>1 else 0,
            coremark_per_mhz_mean=statistics.mean(values)/100))
    a, b = reports
    assert a['iterations_per_group'] == b['iterations_per_group']
    assert a['build_id'] == recipe()['build_id']
    build_meta = json.loads((HERE/'build/candidate/build.json').read_text())
    assert b['build_id'] == build_meta['build_id']
    image = HERE/'build/candidate/runtime.ngb'
    assert sha(image) == b['ngb_sha256']
    destination = HERE/'images'/('runtime_'+b['build_id']+'.ngb')
    destination.parent.mkdir(exist_ok=True)
    shutil.copy2(image, destination)
    report = dict(status='PASS', kind='Physical Nigo CPU CoreMark compiler comparison',
        baseline=a, candidate=b, delta_percent=100*(b['mean']/a['mean']-1),
        selected_release=recipe()['build_id'], candidate_image=destination.relative_to(HERE).as_posix(),
        board_resident_after_test=b['build_id'], flash_written=False, fpga_programmed=False,
        current_rtl_and_published_firmware_unchanged=True,
        limitations='Three sequential runs per image; no EEMBC certification; this is not a clock or RTL change')
    save(HERE/'results/comparison.json', report)
    print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    b = sub.add_parser('build')
    b.add_argument('--tools', default=os.environ.get('NIGO_RISCV_TOOLS', ''))
    m = sub.add_parser('measure')
    m.add_argument('profile', choices=['baseline', 'candidate'])
    m.add_argument('--install', action='store_true')
    m.add_argument('--iterations', type=int, default=11000)
    m.add_argument('--repeats', type=int, default=3)
    n = sub.add_parser('native')
    n.add_argument('--cc', default=os.environ.get('CC', 'gcc'))
    c = sub.add_parser('compare')
    c.add_argument('baseline')
    c.add_argument('candidate')
    args = parser.parse_args()
    if args.action == 'build':
        build(args)
    elif args.action == 'native':
        native(args)
    elif args.action == 'compare':
        compare(args)
    else:
        assert 1 <= args.iterations <= 1000000 and 1 <= args.repeats <= 10
        measure(args)
