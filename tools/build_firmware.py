"""Rebuild the frozen CPU image locally, preserving all shipped assets.

Requires GNU RISC-V GCC 13.2.0 for byte-for-byte reference reproduction.
Set NIGO_RISCV_TOOLS to the directory containing riscv64-unknown-elf-gcc.
"""
import argparse,hashlib,json,os,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('name',choices=['runtime','arcade','bootloader'])
    ap.add_argument('--tools',default=os.environ.get('NIGO_RISCV_TOOLS',''))
    a=ap.parse_args();found=shutil.which('riscv64-unknown-elf-gcc')
    tools=Path(a.tools) if a.tools else Path(found).parent if found else None
    if tools is None:raise SystemExit('Set NIGO_RISCV_TOOLS or --tools to the GCC tool directory')
    out=ROOT/'build/firmware'/a.name;out.mkdir(parents=True,exist_ok=True);(out/'obj').mkdir(exist_ok=True)
    commands=[]
    def run(cmd):
        commands.append(cmd);subprocess.run(cmd,cwd=ROOT,check=True)
    if a.name=='bootloader':
        src=ROOT/'firmware/bootloader/src'
        files=['start.S','jump.S','boot_entry.c','network_main.c','flash.c','flash_mmio.c','flash_store.c','flash_boot_service.c','loader.c','program_upload.c','memory.c','ethernet.c']
        cmd=[str(tools/'riscv64-unknown-elf-gcc'),'-B'+tools.as_posix()+'/',
            '-march=rv32im_zicsr','-mabi=ilp32','-mcmodel=medany','-O2','-g','-ffreestanding','-fno-builtin',
            '-ffunction-sections','-fdata-sections','-Wall','-Wextra','-Werror','-I'+str(src),'-I'+str(src/'freestanding'),
            *[str(src/n) for n in files],'-nostdlib','-Wl,-T,'+str(src/'link.ld')+',--gc-sections,-Map,'+str(out/'bootloader.map'),'-lgcc','-o',str(out/'bootloader.elf')]
        run(cmd)
    else:
        recipe=json.loads((ROOT/'firmware/recipes'/f'{a.name}.json').read_text())
        for rel,h in recipe['input_sha256'].items():
            assert sha(ROOT/rel)==h,'Reference source changed: '+rel
        shutil.copy2(ROOT/recipe['build_info'],out/'build_info.h')
        for raw in recipe['commands']:
            cmd=[arg.replace('@REPO@',ROOT.as_posix()).replace('@OUT@',out.as_posix()).replace('@TOOLS@',tools.as_posix()) for arg in raw]
            run(cmd)
    run([str(tools/'riscv64-unknown-elf-objcopy'),'-O','binary',str(out/(a.name+'.elf')),str(out/(a.name+'.bin'))])
    if a.name=='bootloader':
        blob=(out/'bootloader.bin').read_bytes();assert len(blob)<=32768;blob+=bytes(32768-len(blob))
        (out/'boot64.hex').write_text(''.join('%016x\n'%int.from_bytes(blob[i:i+8],'little') for i in range(0,32768,8)))
        match=(out/'boot64.hex').read_text()==(ROOT/'firmware/bootloader/boot64.hex').read_text()
    else:
        sys.path.insert(0,str(ROOT/'upper'));from nigo_host.program import pack_image
        (out/(a.name+'.ngb')).write_bytes(pack_image((out/(a.name+'.bin')).read_bytes()))
        match=sha(out/(a.name+'.bin'))==recipe['binary_sha256'] and sha(out/(a.name+'.ngb'))==recipe['ngb_sha256']
    report=dict(status='REFERENCE_BYTES_MATCH' if match else 'REFERENCE_BYTES_DIFFER',name=a.name,
        compiler=subprocess.check_output([str(tools/'riscv64-unknown-elf-gcc'),'--version'],text=True).splitlines()[0],
        commands=commands,shipped_assets_modified=False,binary_sha256=sha(out/(a.name+'.bin')))
    (out/'result.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='commands'}))
    if not match:raise SystemExit('Rebuild differs from frozen image; do not substitute it as a verified reference')
if __name__=='__main__':main()
