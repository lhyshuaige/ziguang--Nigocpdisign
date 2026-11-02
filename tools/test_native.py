"""Native driver/exit regressions with mock MMIO, preserving baseline build outputs."""
import hashlib,json,subprocess,os,shutil
from pathlib import Path
REPO=Path(__file__).resolve().parents[1];ROOT=REPO/"upper/firmware/runtime";FW=ROOT.parent
GCC=os.environ.get("CC",shutil.which("gcc") or "gcc")
def main():
 out=ROOT/'build';out.mkdir(exist_ok=True);shutil.copy2(REPO/"firmware/recipes/runtime_build_info.h",out/"build_info.h");face=FW/'ultraface/src';rx=ROOT/'vendor/rx';cm=FW/'coremark'
 source=(ROOT/'src/main.c').read_text()
 before='static uint32_t rd(uint32_t a){uint32_t v=*(volatile uint32_t *)(uintptr_t)a;__asm__ volatile("fence iorw,iorw":::"memory");return v;}'
 assert source.count(before)==1;source=source.replace(before,'static uint32_t rd(uint32_t a){return fake_read(a);}')
 before='static void wr(uint32_t a,uint32_t v){__asm__ volatile("fence iorw,iorw":::"memory");*(volatile uint32_t *)(uintptr_t)a=v;__asm__ volatile("fence iorw,iorw":::"memory");}'
 assert source.count(before)==1;source=source.replace(before,'static void wr(uint32_t a,uint32_t v){fake_write(a,v);}')
 (out/'native_main.inc').write_text(source)
 source=(ROOT/'adapters/face.c').read_text()
 before='static uint32_t rd(uintptr_t base,unsigned off){uint32_t v=*(volatile uint32_t *)(base+off);ordered_io();return v;}'
 after='static uint32_t rd(uintptr_t base,unsigned off){ordered_io();return fake_mmio_read(base+off);}'
 assert source.count(before)==1;source=source.replace(before,after)
 before='static void wr(uintptr_t base,unsigned off,uint32_t v){ordered_io();*(volatile uint32_t *)(base+off)=v;ordered_io();}'
 assert source.count(before)==1;source=source.replace(before,'static void wr(uintptr_t base,unsigned off,uint32_t v){ordered_io();fake_mmio_write(base+off,v);}')
 (out/'native_face.inc').write_text(source)
 tests=[
  ('mode',[ROOT/'tests/mode_test.c',ROOT/'src/mode.c'],[ROOT/'src'],[]),
  ('router',[ROOT/'tests/router_test.c',ROOT/'src/mode.c'],[ROOT/'src',cm/'platform',out],[]),
  ('rx_exit',[ROOT/'tests/receiver_exit.c',ROOT/'adapters/receiver.c'],[ROOT/'src',rx,cm/'platform'],['-Dnigo_rx_nax_cache=runtime_native_cache','-include',str(ROOT/'tests/rx_native.h')]),
  ('face_exit',[ROOT/'tests/face_exit.c']+[p for p in face.glob('*.c') if p.name not in ['main.c','memory.c']],[ROOT/'src',face,out],[]),
  ('ai_driver',[FW/'ultraface/tests/software_test.c',face/'nigo_ai.c',face/'ngu_upload.c'],[face],[]),
  ('ai_rpc',[FW/'ultraface/tests/rpc_test.c',face/'face_rpc.c'],[face],[]),
  ('rx_driver',[REPO/"tests/native/rx_driver_test.c",rx/'ethernet_rx.c',rx/'ethernet_rx_service.c'],[rx],[]),
  ('coremark',[cm/'tests/native.c',cm/'port/service.c',cm/'port/core_portme.c']+[cm/'upstream'/n for n in ['core_main.c','core_list_join.c','core_matrix.c','core_state.c','core_util.c']],[cm/'port',cm/'upstream',out],['-DCM_HOST_TEST','-Dmain=coremark_main'])]
 reports=[]
 for name,paths,incs,flags in tests:
  exe=out/('test_'+name+'.exe');cmd=[GCC,'-std=c11','-O2','-Wall','-Wextra','-Werror','-Wno-misleading-indentation',*flags,*['-I'+str(p) for p in incs],*map(str,paths),'-o',str(exe)]
  subprocess.run(cmd,check=True);r=subprocess.run([str(exe)],capture_output=True,text=True);(out/(name+'_native.log')).write_text(r.stdout+r.stderr);r.check_returncode()
  print(name+': PASS',flush=True);reports.append(dict(name=name,status='PASS',command=cmd))
 (out/'native_result.json').write_text(json.dumps(dict(status='PASS',scope='CPU C logic and mock MMIO, not physical DMA or AI inference',tests=reports,face_adapter_sha256=hashlib.sha256((ROOT/'adapters/face.c').read_bytes()).hexdigest(),receiver_adapter_sha256=hashlib.sha256((ROOT/'adapters/receiver.c').read_bytes()).hexdigest()),indent=2)+'\n')
if __name__=='__main__':main()
