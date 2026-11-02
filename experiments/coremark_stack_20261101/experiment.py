"""Compare MEM_STACK with the measured align32 MEM_STATIC image; DDR only."""
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PREVIOUS = HERE.parent/'coremark_align32_20261101'
spec = importlib.util.spec_from_file_location('alignment_experiment', PREVIOUS/'experiment.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
# Reuse the exact upload, retained-log and CRC checks in the preceding experiment.
# Redirect only that imported module's output directory, never its source files.
common.HERE = HERE


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, data):
    common.save(path, data)


def reference():
    return json.loads((PREVIOUS/'results/build.json').read_text())


def prepare_port(out):
    source = ROOT/'upper/firmware/coremark/port'
    destination = out/'port'
    shutil.copytree(source, destination)
    header = destination/'core_portme.h'
    blob = header.read_bytes()
    before = b'#define MEM_METHOD MEM_STATIC'
    after = b'#define MEM_METHOD MEM_STACK'
    assert blob.count(before) == 1
    header.write_bytes(blob.replace(before, after))
    for path in source.iterdir():
        if path.is_file():
            expected = path.read_bytes().replace(before, after) if path.name == 'core_portme.h' else path.read_bytes()
            assert (destination/path.name).read_bytes() == expected
    return destination


def build(args):
    original = reference()
    for rel, digest in original['input_sha256'].items():
        assert sha(ROOT/rel) == digest, 'Reference changed: '+rel
    out = HERE/'build/candidate'
    out.mkdir(parents=True, exist_ok=False)
    (out/'obj').mkdir()
    port = prepare_port(out)
    tools = Path(args.tools)
    gcc = str(tools/'riscv64-unknown-elf-gcc')
    compiler = subprocess.check_output([gcc, '--version'], text=True).splitlines()[0]
    assert compiler == original['compiler'], compiler
    identity = hashlib.sha256(json.dumps(dict(reference_ngb=original['ngb_sha256'],
        change='MEM_STATIC -> MEM_STACK', header_sha256=sha(port/'core_portme.h')),
        sort_keys=True).encode()).hexdigest()[:8]
    flags_text = ' '.join(original['requested_flags']+original['platform_flags'])
    (out/'build_info.h').write_text(''.join('#define %s 0x%su\n'%(name, identity)
        for name in ['RUNTIME_BUILD_ID','FACE_BUILD_ID','CM_BUILD_ID'])+
        '#define CM_COMPILER_FLAGS '+json.dumps(flags_text)+'\n')
    commands = []
    def run(command, label):
        commands.append(command)
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        (out/(label+'.log')).write_text(result.stdout+result.stderr)
        if result.returncode:
            print(result.stdout+result.stderr, flush=True)
            result.check_returncode()
        return result.stdout
    old_out = '@REPO@/experiments/coremark_align32_20261101/build/candidate'
    old_port = '@REPO@/upper/firmware/coremark/port'
    for index, raw in enumerate(original['commands'][:31]):
        command = [a.replace(old_out, out.as_posix()).replace(old_port, port.as_posix())
            .replace('@REPO@', ROOT.as_posix()).replace('@TOOLS@', tools.as_posix()) for a in raw]
        if '-c' in command:
            command.insert(1, '-fstack-usage')  # Report only; not an optimization option.
        run(command, '%02d_compile'%index)
    run([str(tools/'riscv64-unknown-elf-objcopy'), '-O', 'binary',
         str(out/'runtime.elf'), str(out/'runtime.bin')], 'objcopy')
    symbols = run([str(tools/'riscv64-unknown-elf-nm'), '-n', str(out/'runtime.elf')], 'symbols')
    assert re.search(r'^82000000 T _start$', symbols, re.M)
    assert 'static_memblk' not in symbols
    assert not run([str(tools/'riscv64-unknown-elf-nm'), '-u', str(out/'runtime.elf')], 'undefined').strip()
    addresses = {name: int(address,16) for address, kind, name in re.findall(r'^(\w+) (\w) (\S+)$', symbols, re.M)}
    available = addresses['__stack_top']-addresses['__bss_end']
    assert available >= 32768
    frames = []
    for path in sorted((out/'obj').glob('*.su')):
        for line in path.read_text().splitlines():
            source, size, qualifier = line.rsplit('\t',2)
            frames.append(dict(object=path.name, function=source.rsplit(':',1)[1],
                               bytes=int(size), qualifier=qualifier))
    main_frames = [f for f in frames if f['function']=='coremark_main']
    assert len(main_frames)==1 and 2000 <= main_frames[0]['bytes'] < 8192, main_frames
    cm_frames = [f for f in frames if 19 <= int(f['object'].split('_')[0]) <= 26]
    assert all(f['qualifier']=='static' for f in cm_frames), cm_frames
    # This is an inventory sum, not a call-graph proof or a measured high-water mark.
    stack = dict(linker_guarantee_bytes=32768, space_between_bss_and_stack_top=available,
        coremark_work_area_bytes=2000, coremark_main=main_frames[0],
        coremark_static_frame_inventory_sum=sum(f['bytes'] for f in cm_frames),
        coremark_frames=cm_frames, all_reported_frames=frames,
        static_memblk_removed=True, dynamic_stack_high_water_measured=False)
    save(out/'stack.json', stack)
    size = run([str(tools/'riscv64-unknown-elf-size'), str(out/'runtime.elf')], 'size')
    image = common.pack_image((out/'runtime.bin').read_bytes())
    common.validate_image(image)
    (out/'runtime.ngb').write_bytes(image)
    metadata = dict(status='BUILT_BOARD_PENDING', profile='align32_loop4_jump8_MEM_STACK',
        build_id=identity, reference_build_id=original['build_id'],
        reference_ngb_sha256=original['ngb_sha256'], compiler=compiler,
        requested_flags=original['requested_flags'], platform_flags=original['platform_flags'],
        functional_change='#define MEM_METHOD MEM_STATIC -> MEM_STACK',
        diagnostic_compile_flag='-fstack-usage', all_other_port_bytes_unchanged=True,
        input_sha256=original['input_sha256'], overlay_header_sha256=sha(port/'core_portme.h'),
        commands=commands, ngb_bytes=len(image), ngb_sha256=sha(out/'runtime.ngb'),
        binary_bytes=len(image)-32, binary_sha256=sha(out/'runtime.bin'), size=size,
        rtl_modified=False, release_assets_modified=False, flash_written=False)
    save(out/'build.json', metadata)
    print(json.dumps({k:metadata[k] for k in ['status','build_id','binary_bytes','size']}), flush=True)
    print('STACK_AUDIT', json.dumps({k:stack[k] for k in ['space_between_bss_and_stack_top',
        'coremark_main','coremark_static_frame_inventory_sum']}), flush=True)


def native(args):
    out = HERE/'build/candidate'
    cm = ROOT/'upper/firmware/coremark'
    port = out/'port'
    original = reference()
    flags = [f for f in original['requested_flags'] if f not in common.LINK_ONLY
             and not f.startswith(('-march=','-mabi=','-mcmodel=','-mtune='))]
    sources = [cm/'tests/native.c',port/'service.c',port/'core_portme.c']
    sources += [cm/'upstream'/name for name in ['core_main.c','core_list_join.c','core_matrix.c',
                                             'core_state.c','core_util.c']]
    exe = out/'native_test.exe'
    cmd = [args.cc,'-std=c11',*flags,'-Wall','-Wextra','-Werror','-DTOTAL_DATA_SIZE=2000',
        '-DCM_HOST_TEST','-Dmain=coremark_main',*['-I'+str(p) for p in [port,cm/'upstream',out]],
        *map(str,sources),'-o',str(exe)]
    subprocess.run(cmd,check=True)
    result = subprocess.run([str(exe)],capture_output=True,text=True)
    (out/'native_result.txt').write_text(result.stdout+result.stderr)
    result.check_returncode()
    assert 'NATIVE_FUNCTIONAL_AND_RPC_PASS' in result.stdout
    save(HERE/'results/native.json', dict(status='PASS',memory_method='MEM_STACK',
        scope='Existing native CRC and RPC regression; not a Nigo CPU performance score',command=cmd))
    print('MEM_STACK_NATIVE_CRC_RPC_PASS',flush=True)


def finish(args):
    from nigo_host.coremark import parse_result
    old_compare = json.loads((PREVIOUS/'results/comparison.json').read_text())
    original_path = PREVIOUS/old_compare['candidate']['evidence']
    candidate_path = Path(args.result).resolve()
    rows = []
    for label,path in [('MEM_STATIC',original_path),('MEM_STACK',candidate_path)]:
        summary = json.loads(path.read_text())
        assert summary['status']=='PASS'
        scores = []
        for item in summary['results']:
            prefix = path.parent/('%02d'%item['index'])
            state = json.loads(prefix.with_suffix('.state.json').read_text())
            result = parse_result(state,prefix.with_suffix('.txt').read_bytes())
            assert result['valid'] and result['build_id']==summary['build_id']
            assert all(r['iterations']==11000 for r in result['runs'])
            scores.append(result['coremark_per_mhz'])
        assert len(scores)==3
        rows.append(dict(memory_method=label,build_id=summary['build_id'],scores=scores,
            mean=statistics.mean(scores),median=statistics.median(scores),
            evidence=os.path.relpath(path,HERE).replace('\\','/')))
    a,b = rows
    assert a['build_id']==reference()['build_id']
    out=HERE/'build/candidate'
    metadata=json.loads((out/'build.json').read_text())
    assert b['build_id']==metadata['build_id'] and sha(out/'runtime.ngb')==metadata['ngb_sha256']
    images=HERE/'images';images.mkdir(exist_ok=True)
    image=images/('runtime_'+b['build_id']+'.ngb');shutil.copy2(out/'runtime.ngb',image)
    save(image.with_suffix('.json'),{k:metadata[k] for k in ['build_id','ngb_bytes','ngb_sha256']})
    for filename in ['build.json','stack.json']:
        data=json.loads((out/filename).read_text())
        if filename=='build.json':
            data['status']='PHYSICAL_COREMARK_PASS_NOT_PROMOTED'
            aliases=[ROOT.as_posix(),str(ROOT)]
            if ROOT.drive:
                aliases.append('/mnt/'+ROOT.drive[0].lower()+ROOT.as_posix()[2:])
            tool_dir=data['commands'][0][0].rsplit('/',1)[0]
            def portable(value):
                for alias in aliases:value=value.replace(alias,'@REPO@')
                return value.replace(tool_dir,'@TOOLS@')
            data['commands']=[[portable(a) for a in c] for c in data['commands']]
            data['size']=portable(data['size'])
        save(HERE/'results'/filename,data)
    report=dict(status='PASS',baseline=a,candidate=b,delta_percent=100*(b['mean']/a['mean']-1),
        median_delta_percent=100*(b['median']/a['median']-1),
        iterations_per_group=11000,repetitions=3,baseline_reused_from_previous_experiment=True,
        compiler_flags_unchanged=True,work_area_bytes=2000,work_area_backing_memory='DDR in both cases',
        rtl_modified=False,flash_written=False,release_firmware='9700ce2a',
        board_resident_at_test_end=b['build_id'],candidate_image=image.relative_to(HERE).as_posix())
    save(HERE/'results/comparison.json',report)
    print(json.dumps(report,indent=2),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='action',required=True)
    b=sub.add_parser('build');b.add_argument('--tools',required=True)
    n=sub.add_parser('native');n.add_argument('--cc',default=os.environ.get('CC','gcc'))
    m=sub.add_parser('measure');m.add_argument('--install',action='store_true')
    m.add_argument('--iterations',type=int,default=11000);m.add_argument('--repeats',type=int,default=3)
    f=sub.add_parser('finish');f.add_argument('result')
    args=parser.parse_args()
    if args.action=='build':build(args)
    elif args.action=='native':native(args)
    elif args.action=='finish':finish(args)
    else:
        assert 1<=args.iterations<=1000000 and 1<=args.repeats<=10
        args.profile='candidate';common.measure(args)
