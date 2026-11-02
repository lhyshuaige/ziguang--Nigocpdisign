"""Run the canonical image in the frozen reference model and audit the 100-round result."""
import hashlib,json,os,re,shutil,subprocess,time
from pathlib import Path
HERE=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 meta=json.loads((HERE/'build/build.json').read_text())
 assert sha(HERE/'build/coremark.memh')==meta['memh_sha256']
 out=HERE/'sim/build/run';out.mkdir(exist_ok=False)
 shutil.copy2(HERE/'build/coremark.memh',out/'coremark.memh')
 exe=HERE/'sim/build/Vpgl50h_soc_coremark_tb.exe'
 if not exe.exists():exe=exe.with_suffix('')
 env=dict(os.environ);env['PATH']='D:/PDS/w64devkit/w64devkit/bin'+os.pathsep+env.get('PATH','')
 started=time.monotonic()
 with (out/'run.log').open('w') as stdout,(out/'progress.log').open('w') as stderr:
  result=subprocess.run([str(exe),'60000000'],cwd=out,stdout=stdout,stderr=stderr,env=env,timeout=300)
 text=(out/'run.log').read_text()
 records={k:int(v,16) for k,v in re.findall(r'(seedcrc|crclist|crcmatrix|crcstate|crcfinal)\s*:\s*0x([0-9a-fA-F]+)',text)}
 count=re.search(r'Iterations\s*:\s*(\d+)',text);ticks=re.search(r'Total ticks\s*:\s*(\d+)',text)
 profile=re.search(r'PROFILE (.+)',text)
 counters={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',profile[1])} if profile else {}
 errors=re.findall(r'^.*(?:ERROR!|Errors detected).*$',text,re.M)
 passed=(result.returncode==0 and count and int(count[1])==100 and ticks and int(ticks[1])==counters.get('timed_cycles')
         and records==dict(seedcrc=0xe9f5,crclist=0xe714,crcmatrix=0x1fd7,crcstate=0x8e3a,crcfinal=0x988c)
         and errors==['ERROR! Must execute for at least 10 secs for a valid result!','Errors detected'])
 report=dict(status='SHORT_DIAGNOSTIC_PASS' if passed else 'FAIL',elf_sha256=meta['elf_sha256'],
    ngb_sha256=meta['ngb_sha256'],simulator_sha256=sha(exe),build_id=meta['build_id'],
    cpu_hz=100000000,iterations=100,ticks=int(ticks[1]) if ticks else None,
    crc=records,counters=counters,errors=errors,wall_seconds=time.monotonic()-started,
    memory_model='Frozen one-cycle HMIC behavioral memory, remapped; not a DDR PHY model',
    official_reportable=False)
 if passed:
  report['coremark_per_mhz']=100e6/report['ticks']
  report['original_reference_ticks']=19190862
  report['delta_reference_percent']=100*(19190862/report['ticks']-1)
 dest=HERE/'results/simulation';dest.mkdir(parents=True,exist_ok=True)
 (dest/'result.json').write_text(json.dumps(report,indent=2)+'\n');shutil.copy2(out/'run.log',dest/'console.txt')
 print(json.dumps(report,indent=2),flush=True)
 if not passed:raise SystemExit('Canonical simulation failed; inspect retained console/progress')
if __name__=='__main__':main()
