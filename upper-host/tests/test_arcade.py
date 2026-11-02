import socket,struct,threading,time,unittest,zlib
from nigo_host.arcade import ArcadeStream,FrameAssembler,FRAME,REPLY,REQUEST,decode_rle,decode_status,WIDTH,HEIGHT
from nigo_host.client import Endpoint
def encoded():
    n=WIDTH*HEIGHT;return bytes([255,5])*(n//255)+bytes([n%255,5])
def packets(frame=7,session=19):
    body=encoded();return [FRAME.pack(b'NGGF',1,session,frame,len(body),i,zlib.crc32(body),WIDTH<<16|HEIGHT)+body[i:i+224] for i in range(0,len(body),224)]
class ArcadeTests(unittest.TestCase):
    def test_reordered_duplicate_packets(self):
        p=packets();p=p[::-1]+[p[-1]];a=FrameAssembler(19);answers=[a.push(x) for x in p];answers=[v for v in answers if v]
        self.assertEqual(len(answers),1);self.assertEqual(answers[0],(7,bytes([5])*WIDTH*HEIGHT))
    def test_missing_frame_is_discarded(self):
        a=FrameAssembler(19);self.assertIsNone(a.push(packets(1)[0]));result=None
        for p in packets(2):result=a.push(p)
        self.assertIsNotNone(result);self.assertEqual(a.dropped,1);self.assertIsNone(a.push(packets(1)[-1]))
    def test_wrong_session_ignored(self):
        a=FrameAssembler(21);self.assertTrue(all(a.push(p) is None for p in packets()))
    def test_crc_rejects_corruption(self):
        a=FrameAssembler(19);p=packets();p[-1]=p[-1][:-1]+b'\x04'
        with self.assertRaisesRegex(ValueError,'CRC'):
            for b in p:a.push(b)
    def test_bounds_and_rle(self):
        for b in [b'',b'\x01',b'\x00\x05',b'\xff\xff',b'\x01\x05',bytes([255,5])*302]:
            with self.assertRaises(ValueError):decode_rle(b)
        p=bytearray(packets()[0]);struct.pack_into('!I',p,16,0xffffffff)
        with self.assertRaises(ValueError):FrameAssembler(19).push(p)
    def test_conflicting_duplicate(self):
        a=FrameAssembler(19);p=packets()[0];a.push(p)
        with self.assertRaises(ValueError):a.push(p[:-1]+b'\x04')
    def test_sequence_wrap(self):
        a=FrameAssembler(19)
        for identity in [0xffffffff,0]:
            for p in packets(identity):result=a.push(p)
            self.assertEqual(result[0],identity)
    def test_status(self):
        p=REPLY.pack(b'NGGS',1,1,12,19,0,2,1,4,100,20,320,240,60,30,0x41524331)
        self.assertEqual(decode_status(p,19)['mode'],2);self.assertIsNone(decode_status(p,20))
    def test_udp_stream_receives_frame_filters_wrong_port_and_stops(self):
        control=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);control.bind(('127.0.0.1',0));control.settimeout(.1)
        data=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);data.bind(('127.0.0.1',0))
        foreign=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);foreign.bind(('127.0.0.1',0))
        done=threading.Event();stopped=threading.Event();errors=[]
        def server():
            try:
                while not done.is_set():
                    try:q,peer=control.recvfrom(128)
                    except socket.timeout:continue
                    magic,version,op,seq,session,reserved=REQUEST.unpack(q)
                    if op==2:stopped.set();return
                    # A newer frame from an unrelated source port must not suppress the real frame.
                    for p in packets(999,session):foreign.sendto(p,peer)
                    control.sendto(REPLY.pack(b'NGGS',1,1,seq,session,0,2,1,0,10,7,320,240,60,30,0x41524331),peer)
                    for p in packets(7,session)[::-1]:data.sendto(p,peer)
            except Exception as error:errors.append(error)
        worker=threading.Thread(target=server);worker.start()
        stream=ArcadeStream(Endpoint('127.0.0.1','127.0.0.1'),port=0,control_port=control.getsockname()[1],frame_source_port=data.getsockname()[1])
        try:
            stream.start();deadline=time.monotonic()+3
            while stream.latest is None and stream.error is None and time.monotonic()<deadline:time.sleep(.01)
            self.assertIsNone(stream.error);self.assertIsNotNone(stream.latest)
            self.assertEqual(stream.latest[:2],(7,bytes([5])*WIDTH*HEIGHT));self.assertEqual(stream.status['mode'],2)
            stream.stop();self.assertTrue(stopped.wait(1));self.assertFalse(stream.thread.is_alive());self.assertFalse(errors)
        finally:
            stream.stop();done.set();worker.join(timeout=1);control.close();data.close();foreign.close()
if __name__=='__main__':unittest.main()
