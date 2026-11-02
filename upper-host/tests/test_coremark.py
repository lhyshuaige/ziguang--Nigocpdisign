import unittest
import zlib
from nigo_host.coremark import decode_reply,parse_result,REPLY,REQUEST,CoreMarkClient
from nigo_host.client import Endpoint
from test_protocols import Server


def fixture(seconds=12):
    parts=[]
    for name,crcs in [('PERFORMANCE',['e9f5','e714','1fd7','8e3a']),('VALIDATION',['18f2','e3c1','0747','8d84'])]:
        part=f'=== {name} ===\nCoreMark Size    : 666\nIterations       : 6000\nTotal ticks      : {seconds*1000000}\n'
        for label,crc in zip(['seedcrc','[0]crclist','[0]crcmatrix','[0]crcstate'],crcs):part+=f'{label} : 0x{crc}\n'
        part+='Correct operation validated.\n';parts.append(part)
    raw=''.join(parts).encode()
    state=dict(state=2,flags=0,log_length=len(raw),log_crc=zlib.crc32(raw),run_id=42,build_id=7,
               performance_ticks=seconds*100000000,validation_ticks=seconds*100000000,
               timer_hz=100000000,cpu_hz=100000000)
    return state,raw


class CoreMarkTests(unittest.TestCase):
    def test_score_requires_both_valid_runs(self):
        result=parse_result(*fixture())
        self.assertTrue(result['valid']);self.assertEqual(result['coremark'],500)
        self.assertEqual(result['coremark_per_mhz'],5)

    def test_short_run_is_never_a_score(self):
        result=parse_result(*fixture(9))
        self.assertFalse(result['valid']);self.assertIsNone(result['coremark'])

    def test_bad_algorithm_crc_is_never_a_score(self):
        state,raw=fixture();raw=raw.replace(b'e714',b'0000');state['log_crc']=zlib.crc32(raw)
        self.assertFalse(parse_result(state,raw)['valid'])

    def test_corrupt_transfer_rejected(self):
        state,raw=fixture()
        with self.assertRaisesRegex(ValueError,'CRC'):parse_result(state,raw[:-1]+b'x')

    def test_timer_mismatch_rejected(self):
        state,raw=fixture();state['performance_ticks']+=100
        with self.assertRaisesRegex(ValueError,'timer'):parse_result(state,raw)

    def test_audit_zero_error_mask_does_not_hide_real_errors(self):
        for suffix,valid in [(b'AUDIT_ERRORS=00000000\n',True),
                             (b'AUDIT_ERRORS=00000020\n',False),
                             (b'AUDIT_ERRORS=00000000\nERROR! Peripheral audit failed\n',False)]:
            state,raw=fixture();raw+=suffix
            state.update(log_length=len(raw),log_crc=zlib.crc32(raw))
            self.assertEqual(parse_result(state,raw)['valid'],valid)

    def test_missing_validation_rejected(self):
        state,raw=fixture();raw=raw.split(b'=== VALIDATION ===')[0]
        state.update(log_length=len(raw),log_crc=zlib.crc32(raw))
        with self.assertRaises(ValueError):parse_result(state,raw)

    def test_reply_sequence_and_bounds(self):
        data=REPLY.pack(b'NCS1',1,1,7,0,42,2,200,0,0,0,100000000,100000000,0,1200000000,0,1200000000,0,0,7)
        self.assertIsNone(decode_reply(data,1,8))
        self.assertEqual(decode_reply(data,1,7)['performance_ticks'],1200000000)
        with self.assertRaises(ValueError):decode_reply(data+b'extra',1,7)

    def test_lost_start_ack_and_chunked_result(self):
        state,raw=fixture();state['state']=0;state['run_id']=0;starts=[]
        def handle(sock,data,peer,_):
            _,version,op,seq,identity,arg=REQUEST.unpack(data)
            self.assertEqual(version,1)
            if op==2:
                if identity!=state['run_id']:
                    starts.append(identity);state.update(state=2,run_id=identity)
                return  # All START ACKs lost; polling must recover the same run.
            body=raw[arg:arg+176] if op==3 else b''
            reply=REPLY.pack(b'NCS1',1,op,seq,0,state['run_id'],state['state'],len(raw),
                arg if op==3 else 0,len(body),0,100000000,100000000,0,1200000000,
                0,1200000000,state['log_crc'],0,7)+body
            sock.sendto(reply,peer)
        with Server(handle) as server:
            client=CoreMarkClient(Endpoint('127.0.0.1','127.0.0.1'),server.port(),timeout=.01)
            try:
                result=client.run(timeout=2)
                self.assertTrue(result['valid']);self.assertEqual(result['raw_log'],raw.decode())
                self.assertEqual(len(starts),1)
            finally:client.close()


if __name__=='__main__':unittest.main()
