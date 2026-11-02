"""Preserve the reference benchmark bytes/layout; add an isolated board service."""
import argparse,hashlib,json,os,re,shutil,struct,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2)+'\n')
def sections(blob):
 off=struct.unpack_from('<I',blob,32)[0];size,count,index=struct.unpack_from('<HHH',blob,46)
 rows=[struct.unpack_from('<10I',blob,off+i*size) for i in range(count)]
 strings=blob[rows[index][4]:rows[index][4]+rows[index][5]]
 return {strings[r[0]:].split(b'\0')[0].decode():dict(address=r[3],offset=r[4],size=r[5],
     data=bytes(blob[r[4]:r[4]+r[5]]) if r[1]!=8 else b'') for r in rows}
def jal(pc,target):
 d=target-pc;assert d%2==0 and -(1<<20)<=d<(1<<20)
 u=d&0x1fffff
 return ((u>>20&1)<<31)|((u>>1&0x3ff)<<21)|((u>>11&1)<<20)|((u>>12&0xff)<<12)|0x6f

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--reference-root',type=Path);ap.add_argument('--tools',type=Path,required=True);ap.add_argument('--output',type=Path,default=HERE/'build');ap.add_argument('--retry',action='store_true');a=ap.parse_args()
 tools=a.tools
 out=a.output.resolve();assert not (out/'build.json').exists(),'Completed build is immutable';out.mkdir(parents=True,exist_ok=a.retry);(out/'obj').mkdir(exist_ok=a.retry);(out/'logs').mkdir(exist_ok=a.retry)
 frozen=HERE/'reference';frozen.mkdir(exist_ok=True)
 if a.reference_root:
  ref=a.reference_root/'sweep50_20261101/images/r2_a14_n100'
  for name in ['src','port']:
   dst=frozen/name;dst.mkdir(exist_ok=True)
   for p in (a.reference_root/name).glob('*'):
    if p.is_file() and p.suffix in ['.c','.h','.S','.ld','.md']:shutil.copy2(p,dst/p.name)
  shutil.copy2(ref/'build.json',frozen/'original_build.json');shutil.copy2(ref/'coremark.elf',frozen/'original.elf')
 meta=json.loads((frozen/'original_build.json').read_text())
 assert sha(frozen/'original.elf')==meta['elf_sha256']
 shutil.copy2(frozen/'original.elf',out/'original.elf')
 expected={Path(name).name:h for name,h in meta['source_sha256'].items()}
 for folder in ['src','port']:
  for p in (frozen/folder).iterdir():
   if p.name in expected:assert sha(p)==expected[p.name],str(p)
 gcc=str(tools/'riscv64-unknown-elf-gcc');commands=[]
 def run(cmd,name):
  commands.append(cmd);p=subprocess.run(cmd,cwd=HERE,capture_output=True,text=True)
  (out/'logs'/(name+'.txt')).write_text(p.stdout+p.stderr)
  if p.returncode:print(p.stdout+p.stderr,flush=True);p.check_returncode()
  return p.stdout
 compiler=run([gcc,'--version'],'compiler').splitlines()[0];assert compiler==meta['compiler']
 flags=['-B'+tools.as_posix()+'/', '-march=rv32im_zicsr','-mabi=ilp32','-mcmodel=medany',
        '-ffreestanding','-fno-builtin','-nostdlib','-nostartfiles',
        '-I'+str(frozen/'port'),'-I'+str(frozen/'src'),*meta['flags'],
        '-DITERATIONS=100','-DCORE_DEBUG=0','-DPERFORMANCE_RUN=1',
        '-DFLAGS_STR="'+' '.join(meta['flags'])+'"']
 paths=[frozen/'src'/n for n in ['core_main.c','core_list_join.c','core_matrix.c','core_state.c','core_util.c']]
 paths += [frozen/'port'/n for n in ['core_portme.c','runtime.c','start.S']]
 objects=[]
 for i,p in enumerate(paths):
  obj=out/'obj'/('bench_%02d.o'%i);objects.append(obj)
  run([gcc,*flags,'-c',str(p),'-o',str(obj)],'bench_%02d'%i)
 ld=(frozen/'port/link.ld').read_text().replace('0x80000000','0x82000000')
 (out/'relocated.ld').write_text(ld)
 run([gcc,*flags,*map(str,objects),'-T',str(out/'relocated.ld'),'-Wl,-Map,'+str(out/'relocated.map'),'-lgcc','-o',str(out/'relocated.elf')],'relocated_link')
 old=sections((out/'original.elf').read_bytes());rel=sections((out/'relocated.elf').read_bytes())
 for name in ['.init','.text']:
  assert old[name]['data']==rel[name]['data'],'Relocation changed instructions: '+name
  assert old[name]['address']+0x02000000==rel[name]['address']
 init=rel['.init'];retaddr=init['address']+init['size']-4;calladdr=retaddr-4
 assert struct.unpack_from('<I',init['data'],init['size']-4)[0]==0x6f
 assert struct.unpack_from('<I',init['data'],init['size']-8)[0]&0xfff==0xef
 identity=hashlib.sha256(json.dumps([meta['elf_sha256'],[(p.name,sha(p)) for p in sorted((HERE/'service').iterdir())]],sort_keys=True).encode()).hexdigest()[:8]
 data=rel['.data']
 (out/'reference.h').write_text('#define REPLAY_BUILD_ID 0x%su\n#define REFERENCE_DATA_ADDRESS 0x%xu\nstatic const unsigned char reference_data[]={%s};\n'%(identity,data['address'],','.join(str(x) for x in data['data'])))
 svcflags=['-march=rv32im_zicsr','-mabi=ilp32','-mcmodel=medany','-O2','-msmall-data-limit=0',
  '-ffreestanding','-fno-builtin','-nostdlib','-nostartfiles','-Wall','-Wextra','-Werror',
  '-I'+str(out),'-I'+str(frozen/'port'),'-I'+str(frozen/'src'),
  '-I'+str(ROOT/'upper/firmware/coremark/platform'),'-DFLAGS_STR="service outside benchmark"']
 svc=[]
 for i,p in enumerate([HERE/'service/start.S',HERE/'service/replay.c',ROOT/'upper/firmware/coremark/platform/ethernet.c']):
  obj=out/'obj'/('svc_%02d.o'%i);svc.append(obj)
  run([gcc,*svcflags,'-c',str(p),'-o',str(obj)],'service_%02d'%i)
 # Only benchmark objects occupy the original sections, in the original order.
 for pattern in ['.init','.text .text.*','.rodata .rodata.* .srodata .srodata.*','.data .data.*','.sdata .sdata.*','.sbss .sbss.* .bss .bss.* COMMON']:
  ld=ld.replace('*('+pattern+')','*bench_*.o('+pattern+')')
 ld=ld.replace('ENTRY(_start)','ENTRY(service_start)')
 ld=ld.replace('LENGTH = 256K }','LENGTH = 256K\n service(rx) : ORIGIN = 0x82080000, LENGTH = 256K\n service_ram(rw) : ORIGIN = 0x82100000, LENGTH = 256K }')
 marker='  /DISCARD/'
 tail='''  .service : { KEEP(*svc_*.o(.text.service_start)) *svc_*.o(.text .text.*) *(.text .text.*) } >service
  .service_rodata : { *svc_*.o(.rodata .rodata.* .srodata .srodata.*) } >service
  .service_data : { *svc_*.o(.data .data.* .sdata .sdata.*) } >service
  ASSERT(SIZEOF(.service_data)==0, "Service data must be initialized explicitly")
  .service_bss (NOLOAD) : { . = ALIGN(4); __service_bss_start = .; *svc_*.o(.sbss .sbss.* .bss .bss.* COMMON) . = ALIGN(4); __service_bss_end = .; } >service_ram
  __service_stack = ORIGIN(service_ram)+LENGTH(service_ram)-16;
  __reference_call_main = CALL_ADDRESS;
'''.replace('CALL_ADDRESS',hex(calladdr))
 ld=ld.replace(marker,tail+marker)
 (out/'combined.ld').write_text(ld)
 run([gcc,*flags,*map(str,objects+svc),'-T',str(out/'combined.ld'),'-Wl,-Map,'+str(out/'canonical.map'),'-lgcc','-o',str(out/'canonical_unpatched.elf')],'combined_link')
 blob=bytearray((out/'canonical_unpatched.elf').read_bytes());combined=sections(blob)
 for name in ['.init','.text','.rodata','.data','.bss']:
  assert all(combined[name][k]==rel[name][k] for k in ['address','size','data']),('Service moved reference',name)
 symbols=run([str(tools/'riscv64-unknown-elf-nm'),'-n',str(out/'canonical_unpatched.elf')],'symbols')
 syms={n:int(x,16) for x,k,n in re.findall(r'^(\w+) (\w) (\S+)$',symbols,re.M)}
 assert syms['service_start']==0x82080000 and syms['_sp']==0x8203fff0
 patches=[]
 for pc,target,reason in [(retaddr,syms['replay_return'],'after main returns'),
                         (syms['portable_fini'],syms['replay_capture'],'after timer stops and original CRC checks')]:
  sec=next(s for s in combined.values() if s['address']<=pc<s['address']+len(s['data']))
  offset=sec['offset']+pc-sec['address'];before=struct.unpack_from('<I',blob,offset)[0];after=jal(pc,target)
  struct.pack_into('<I',blob,offset,after);patches.append(dict(pc=hex(pc),target=hex(target),before=hex(before),after=hex(after),scope=reason))
 (out/'canonical.elf').write_bytes(blob)
 run([str(tools/'riscv64-unknown-elf-objcopy'),'-O','binary',str(out/'canonical.elf'),str(out/'canonical.bin')],'objcopy')
 sys.path.insert(0,str(ROOT/'upper'));from nigo_host.program import pack_image
 (out/'canonical.ngb').write_bytes(pack_image((out/'canonical.bin').read_bytes(),0x82080000))
 image=bytearray(2*1024*1024);phoff=struct.unpack_from('<I',blob,28)[0];phsize,phcount=struct.unpack_from('<HH',blob,42)
 for i in range(phcount):
  kind,offset,virtual,physical,filesz,memsz,_,_=struct.unpack_from('<8I',blob,phoff+i*phsize)
  if kind==1 and filesz:
   at=physical-0x82000000;assert 0<=at and at+memsz<=len(image)
   image[at:at+filesz]=blob[offset:offset+filesz]
 (out/'coremark.memh').write_text(''.join('%08x\n'%w[0] for w in struct.iter_unpack('<I',image)))
 result=dict(status='BUILD_AND_LAYOUT_PASS',build_id=identity,compiler=compiler,commands=commands,
  benchmark_source_hashes={str(p.relative_to(HERE)):sha(p) for p in paths},flags=meta['flags'],
  original_reference_elf_sha256=meta['elf_sha256'],relocated_instructions_identical=True,
  service_did_not_move_benchmark_sections=True,patches=patches,entry=hex(syms['service_start']),
  stack=hex(syms['_sp']),ngb_bytes=(out/'canonical.ngb').stat().st_size,
  ngb_sha256=sha(out/'canonical.ngb'),elf_sha256=sha(out/'canonical.elf'),
  memh_sha256=sha(out/'coremark.memh'),timed_algorithm_and_timer_bytes_preserved=True)
 save(out/'build.json',result);print(json.dumps({k:v for k,v in result.items() if k not in ['commands','benchmark_source_hashes','flags']},indent=2),flush=True)
if __name__=='__main__':main()
