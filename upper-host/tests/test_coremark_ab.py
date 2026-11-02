import unittest
from nigo_host.coremark_audit import FIELDS,audit_log

def audit_fixture(quiet=True):
    a=dict.fromkeys(FIELDS,0)
    a.update(ai_status=8,rx_status=4 if quiet else 0x44,tx_job_status=0 if quiet else 16,
             eth_control=int(not quiet),eth_status=8 if quiet else 0x19,rx_id=0x52584431)
    initial=dict(a,eth_control=1,eth_status=0x19,rx_status=0x44,tx_job_status=16)
    lines=['AUDIT_VERSION=1',f'AUDIT_QUIET={int(quiet)}']
    for name,snapshot in [('INITIAL',initial),('BEFORE',a),('AFTER',a)]:
        lines.append('AUDIT_'+name+'='+','.join(f'{snapshot[k]:08x}' for k in FIELDS))
    lines.extend(['AUDIT_ERRORS=00000000','AUDIT_RESTORED_CONTROL=00000001'])
    return '\n'.join(lines)+'\n'

class CoreMarkABTests(unittest.TestCase):
    def test_both_modes(self):
        for quiet in [False,True]:self.assertEqual(audit_log(audit_fixture(quiet),quiet)['errors'],0)

    def test_failed_restore_rejected(self):
        with self.assertRaises(ValueError):audit_log(audit_fixture().replace('AUDIT_RESTORED_CONTROL=00000001','AUDIT_RESTORED_CONTROL=00000000'),True)

    def test_activity_rejected_even_if_firmware_error_flag_is_clear(self):
        raw=audit_fixture();line=next(x for x in raw.splitlines() if x.startswith('AUDIT_AFTER='))
        words=line.split('=')[1].split(',');words[2]='00000001'
        with self.assertRaisesRegex(ValueError,'counter changed'):audit_log(raw.replace(line,'AUDIT_AFTER='+','.join(words)),True)

    def test_wrong_mode_and_duplicate_snapshot_rejected(self):
        with self.assertRaises(ValueError):audit_log(audit_fixture(),False)
        raw=audit_fixture();line=next(x for x in raw.splitlines() if x.startswith('AUDIT_BEFORE='))
        with self.assertRaises(ValueError):audit_log(raw+line+'\n',True)

if __name__=='__main__':unittest.main()
