"""Read original CoreMark result structures through an out-of-timing UDP service."""
import argparse,hashlib,json,secrets,socket,statistics,struct,sys,time,zlib
from contextlib import closing
from datetime import datetime,timezone
from pathlib import Path
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT/'upper'))
HEAD=['version','op','sequence','error','build_id','state','run_id','iterations','completed','cpu_hz',
      'audit_errors','network_before','network_after','boot_sample']
RESULT=['iterations','ticks','size','seedcrc','crclist','crcmatrix','crcstate','crcfinal','errors',
        'seed1','seed2','work_address','result_address']
CRC=[(0xe9f5,0xe714,0x1fd7,0x8e3a),(0x18f2,0xe3c1,0x0747,0x8d84)]
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2)+'\n')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def decode(packet,op,sequence):
    if len(packet)!=168 or packet[:4]!=b'NCRP':return None
    if zlib.crc32(packet[:-4])!=struct.unpack_from('!I',packet,164)[0]:raise ValueError('Reply CRC mismatch')
    values=struct.unpack_from('!40I',packet,4);state=dict(zip(HEAD,values))
    if (state['version'],state['op'],state['sequence'])!=(1,op,sequence):return None
    if state['error']:raise RuntimeError('Replay command rejected: '+str(state['error']))
    state['results']=[dict(zip(RESULT,values[14+i*13:27+i*13])) for i in range(2)]
    state['packet_hex']=packet.hex();return state

class Client:
    def __init__(self):
        self.s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);self.s.bind(('192.168.1.100',0));self.seq=secrets.randbits(32)
    def close(self):self.s.close()
    def call(self,op=1,identity=0,iterations=0,retries=5):
        self.seq=(self.seq+1)&0xffffffff;request=struct.pack('!4s5I',b'NCRQ',1,op,self.seq,identity,iterations)
        for _ in range(retries):
            self.s.sendto(request,('192.168.1.50',5001));deadline=time.monotonic()+.2
            while time.monotonic()<deadline:
                self.s.settimeout(max(.001,deadline-time.monotonic()))
                try:packet,peer=self.s.recvfrom(2048)
                except socket.timeout:break
                if peer!=('192.168.1.50',5001):continue
                state=decode(packet,op,self.seq)
                if state is not None:
                    if identity and state['run_id']!=identity:raise ValueError('Different run ID')
                    return state
        raise TimeoutError('Replay service pending or unreachable')

def validate(state,build_id,iterations,short=False,boot=False):
    assert state['build_id']==int(build_id,16) and state['state']==2 and state['completed']==3,state
    assert state['cpu_hz']==100000000 and state['iterations']==iterations
    assert bool(state['boot_sample'])==boot
    if not boot:assert not(state['audit_errors'] or state['network_before'] or state['network_after'])
    for i,r in enumerate(state['results']):
        assert r['iterations']==iterations and r['size']==666 and r['errors']==0,r
        assert tuple(r[k] for k in ['seedcrc','crclist','crcmatrix','crcstate'])==CRC[i],r
        assert (r['seed1'],r['seed2'])==((0,0) if i==0 else (0x3415,0x3415)),r
        assert 0x82000000<=r['work_address']<0x8203fff0
        assert 0<r['ticks']<0xffffffff
        r['seconds']=r['ticks']/100000000
        r['coremark_per_mhz']=iterations*1000000/r['ticks']
        if not short:assert r['seconds']>=10,r
    state['status']='SHORT_DIAGNOSTIC_PASS' if short else 'VALID_LONG_RUN_PASS'
    state['official_reportable_duration']=not short
    state['not_eembc_certified']=True
    return state

def main():
    p=argparse.ArgumentParser();p.add_argument('action',choices=['install','measure','query'])
    p.add_argument('--iterations',type=int,default=11000);p.add_argument('--repeats',type=int,default=3)
    a=p.parse_args()
    metadata=HERE/'build/build.json'
    firmware=HERE/'build/canonical.ngb'
    if not metadata.exists():
        metadata=HERE/'images/canonical_56d1cdac.json'
        firmware=HERE/'images/canonical_56d1cdac.ngb'
    meta=json.loads(metadata.read_text())
    if a.action=='query':
        with closing(Client()) as c:print(json.dumps(c.call(),indent=2))
        return
    stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    out=HERE/'results'/((a.action+'_'+str(a.iterations)+'_')+stamp);out.mkdir(parents=True,exist_ok=False)
    report=dict(status='RUNNING',build_id=meta['build_id'],elf_sha256=meta['elf_sha256'],
                ngb_sha256=meta['ngb_sha256'],fpga_programmed=False,flash_written=False,measurements=[])
    save(out/'summary.json',report)
    try:
        if a.action=='install':
            from nigo_host.client import Host,Endpoint
            blob=firmware.read_bytes();assert hashlib.sha256(blob).hexdigest()==meta['ngb_sha256']
            host=Host(Endpoint());boot=host.boot_query();download=host.program(blob)
            save(out/'download.json',dict(boot=boot,download=download))
        with closing(Client()) as c:
            deadline=time.monotonic()+30
            while True:
                try:initial=c.call();break
                except TimeoutError:
                    if time.monotonic()>deadline:raise
            save(out/'initial.json',initial)
            assert initial['build_id']==int(meta['build_id'],16)
            if a.action=='install':
                result=validate(initial,meta['build_id'],100,short=True,boot=True)
                report['automatic_100']=result
                report['status']='AUTOMATIC_100_BOTH_SEEDS_PASS'
                print('AUTO100_PASS',json.dumps(result['results']),flush=True)
            else:
                assert 1<=a.iterations<=11000 and 1<=a.repeats<=5
                assert a.iterations==100 or a.iterations>=6000
                assert initial['state']==2
                for index in range(1,a.repeats+1):
                    run=secrets.randbits(32) or 1;prefix=out/('%02d'%index)
                    save(prefix.with_suffix('.request.json'),dict(run_id=run,iterations=a.iterations,build_id=meta['build_id']))
                    print('START',index,a.iterations,run,flush=True)
                    try:c.call(2,run,a.iterations)
                    except TimeoutError:pass
                    deadline=time.monotonic()+120
                    while time.monotonic()<deadline:
                        try:
                            state=c.call(1,run,retries=2)
                            if state['state']==2:break
                        except TimeoutError:pass
                        time.sleep(.3)
                    else:raise TimeoutError('Preserved pending run ID; do not automatically start another run')
                    save(prefix.with_suffix('.raw.json'),state)
                    result=validate(state,meta['build_id'],a.iterations,short=a.iterations==100)
                    save(prefix.with_suffix('.json'),result)
                    report['measurements'].append(result);save(out/'summary.json',report)
                    print('PASS',index,'CoreMark/MHz',result['results'][0]['coremark_per_mhz'],flush=True)
                scores=[s['results'][0]['coremark_per_mhz'] for s in report['measurements']]
                report.update(status='PASS',mean=statistics.mean(scores),median=statistics.median(scores),minimum=min(scores),maximum=max(scores))
    except Exception as error:
        report.update(status='FAIL_OR_PENDING',error=repr(error));raise
    finally:
        save(out/'summary.json',report);print('EVIDENCE',out/'summary.json',flush=True)
if __name__=='__main__':main()
