"""Reject corrupt, incomplete or too-short reports before claiming a board score."""
import copy,struct,unittest,zlib
import board

def packet(iterations=11000,ticks=2100000000):
    values=[1,1,17,0,0x56d1cdac,2,99,iterations,3,100000000,0,0,0,0]
    for i in range(2):
        values += [iterations,ticks,666,*board.CRC[i],0x988c,0,
                   0x3415 if i else 0,0x3415 if i else 0,0x8203f700,0x8203ff00]
    raw=struct.pack('!4s40I',b'NCRP',*values)
    return raw+struct.pack('!I',zlib.crc32(raw))

class ReplyChecks(unittest.TestCase):
    def state(self):return board.decode(packet(),1,17)
    def test_valid_long(self):
        r=board.validate(self.state(),'56d1cdac',11000)
        self.assertEqual(r['status'],'VALID_LONG_RUN_PASS')
    def test_crc_rejected(self):
        bad=bytearray(packet());bad[90]^=1
        with self.assertRaises(ValueError):board.decode(bytes(bad),1,17)
    def test_incomplete_and_wrong_algorithm_rejected(self):
        for key,value in [('completed',1),('build_id',0),('audit_errors',4),('network_before',1)]:
            r=self.state();r[key]=value
            with self.assertRaises(AssertionError):board.validate(r,'56d1cdac',11000)
        r=self.state();r['results'][1]['crcmatrix']^=1
        with self.assertRaises(AssertionError):board.validate(r,'56d1cdac',11000)
    def test_short_is_diagnostic_only(self):
        r=board.decode(packet(100,19190862),1,17)
        with self.assertRaises(AssertionError):board.validate(copy.deepcopy(r),'56d1cdac',100)
        r=board.validate(r,'56d1cdac',100,short=True)
        self.assertFalse(r['official_reportable_duration'])
        self.assertEqual(r['status'],'SHORT_DIAGNOSTIC_PASS')
    def test_late_response_ignored(self):
        self.assertIsNone(board.decode(packet(),1,18))

if __name__=='__main__':unittest.main()
