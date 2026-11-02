import hashlib,json,struct,time,unittest
from pathlib import Path
from unittest.mock import patch
from nigo_host.client import Endpoint
from nigo_host.modes import ModeClient,ModeRejected,REQUEST,REPLY,decode,activate
from nigo_host import program
from test_protocols import Server,ngu_ack

class Resident:
    def __init__(self,drop=False,drain=0):
        self.active=self.target=self.generation=0;self.sets=0;self.last=None;self.drop=drop;self.drain=drain;self.queries=0;self.commands=[]
    def handle(self,sock,p,peer,index):
        self.commands.append(p)
        if len(p)!=32 or p[:4]!=b'NMQ1':return
        magic,version,op,session,seq,target,generation,reserved=REQUEST.unpack(p);error=0
        if op==2:
            if self.last==p:pass
            elif generation!=self.generation:error=3
            else:self.sets+=1;self.last=p;self.target=target;self.queries=0
        elif self.active!=self.target:
            self.queries+=1
            if self.queries>self.drain:self.active=self.target;self.generation+=1
        response=REPLY.pack(b'NMR1',1,op,session,seq,error,self.active,self.target,self.generation,1 if self.active!=self.target else 0,0,0x12345678,63,0)
        if self.drop and op==2:self.drop=False;return
        sock.sendto(response,peer)

class ModeTests(unittest.TestCase):
    def test_lost_ack_is_idempotent_and_waits_for_drain(self):
        model=Resident(drop=True,drain=2)
        with Server(model.handle) as s:
            c=ModeClient(Endpoint('127.0.0.1','127.0.0.1'),s.port(),timeout=.03)
            try:r=c.select(4,timeout=2)
            finally:c.close()
        self.assertEqual((r['active'],r['target'],r['generation']),(4,4,1));self.assertEqual(model.sets,1)
        sets=[p for p in model.commands if REQUEST.unpack(p)[2]==2];self.assertGreaterEqual(len(sets),2);self.assertEqual(sets[0],sets[1])
    def test_same_mode_does_not_restart(self):
        model=Resident();model.active=model.target=4
        with Server(model.handle) as s:
            c=ModeClient(Endpoint('127.0.0.1','127.0.0.1'),s.port(),timeout=.03)
            try:self.assertEqual(c.select(4)['active'],4)
            finally:c.close()
        self.assertEqual(model.sets,0)
    def test_stale_generation_rejected(self):
        model=Resident();model.generation=5
        with Server(model.handle) as s:
            c=ModeClient(Endpoint('127.0.0.1','127.0.0.1'),s.port(),timeout=.03)
            try:
                with self.assertRaises(ModeRejected):c.call(2,4,0)
            finally:c.close()
        self.assertEqual(model.sets,0)
    def test_busy_transition_does_not_replace_target(self):
        model=Resident(drain=100);model.target=2
        with Server(model.handle) as s:
            c=ModeClient(Endpoint('127.0.0.1','127.0.0.1'),s.port(),timeout=.03)
            try:
                with self.assertRaisesRegex(RuntimeError,'已有模式'):c.select(4)
            finally:c.close()
        self.assertEqual(model.target,2);self.assertEqual(model.sets,0)
    def test_drain_timeout_does_not_reset(self):
        model=Resident(drain=999)
        with Server(model.handle) as s:
            c=ModeClient(Endpoint('127.0.0.1','127.0.0.1'),s.port(),timeout=.02)
            try:
                with self.assertRaisesRegex(TimeoutError,'未强制复位'):c.select(2,timeout=.08)
            finally:c.close()
        self.assertTrue(all(p[:4]==b'NMQ1' for p in model.commands))
    def test_decode_filters_and_validates(self):
        p=REPLY.pack(b'NMR1',1,1,19,2,0,0,0,0,0,0,1,63,0)
        self.assertIsNone(decode(p,1,20,2));self.assertIsNone(decode(p,1,19,3))
        bad=bytearray(p);struct.pack_into('!I',bad,24,99)
        with self.assertRaises(ValueError):decode(bad,1,19,2)
    def test_runtime_image_and_original_assets(self):
        root=Path(__file__).resolve().parents[1];path=root/'assets/firmware/runtime.ngb';meta=json.loads(path.with_suffix('.json').read_text())
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),meta['ngb_sha256']);program.validate_image(path.read_bytes())
        old=json.loads((root/'assets/SHA256SUMS.json').read_text())
        self.assertTrue(all(hashlib.sha256((root/p).read_bytes()).hexdigest()==h for p,h in old.items()))
    def test_activate_existing_runtime_never_downloads(self):
        model=Resident()
        with Server(model.handle) as s,patch('nigo_host.modes.ProgramClient') as boot:
            result=activate(Endpoint('127.0.0.1','127.0.0.1'),3,port=s.port())
            boot.assert_not_called()
        self.assertFalse(result['installed']);self.assertEqual(result['active'],3)
    def test_bootloader_install_once_then_switch_without_upload(self):
        root=Path(__file__).resolve().parents[1];meta=json.loads((root/'assets/firmware/runtime.json').read_text())
        resident=Resident();running=False;buffer=bytearray();execs=0;entry=crc=0
        def handle(sock,p,peer,index):
            nonlocal running,execs,entry,crc
            if running:
                if p[:4]==b'NMQ1':
                    # Use the build identity that the actual booted image must report.
                    class Send:
                        def sendto(self,data,address):
                            b=bytearray(data);struct.pack_into('!I',b,44,int(meta['build_id'],16));sock.sendto(b,address)
                    resident.handle(Send(),p,peer,index)
                return
            if p[:4]==b'NGBX':
                magic,version,op,session,seq,reserved=program.CONTROL.unpack(p)
                sock.sendto(program.REPLY.pack(b'NGBR',1,op,0,session,seq,entry,crc),peer)
                if op==2:running=True;execs+=1
            elif p[:4]==b'NGU1':
                fields=program.UPLOAD.unpack_from(p);op=fields[2];offset=fields[7]
                if op==1:buffer.clear()
                elif op==2:
                    self.assertEqual(offset,len(buffer));buffer.extend(p[32:])
                elif op==3:entry,crc=program.validate_image(bytes(buffer))
                sock.sendto(ngu_ack(p),peer)
        with Server(handle) as s:
            result=activate(Endpoint('127.0.0.1','127.0.0.1'),4,port=s.port())
            second=activate(Endpoint('127.0.0.1','127.0.0.1'),2,port=s.port())
        self.assertTrue(result['installed']);self.assertFalse(second['installed']);self.assertEqual(execs,1)
        self.assertEqual(bytes(buffer),(root/'assets/firmware/runtime.ngb').read_bytes())
    def test_unknown_legacy_app_is_not_overwritten(self):
        with patch('nigo_host.modes.ModeClient') as mode,patch('nigo_host.modes.ProgramClient') as boot:
            mode.return_value.call.side_effect=TimeoutError();boot.return_value.control.side_effect=TimeoutError()
            with self.assertRaisesRegex(RuntimeError,'首次从旧独立程序'):activate(Endpoint(),4)
            boot.return_value.download.assert_not_called()

if __name__=='__main__':unittest.main()
