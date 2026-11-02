"""Pure parser for saved CoreMark peripheral audit logs."""
import re

FIELDS=['ai_status','ai_completions',
        'ai_reads_lo','ai_reads_hi','ai_compute_lo','ai_compute_hi','ai_busy_lo','ai_busy_hi',
        'ai_axi_wait_lo','ai_axi_wait_hi','ai_macs_lo','ai_macs_hi','ai_overlap_lo','ai_overlap_hi',
        'ai_scalar_stall','dma_status','rx_status','rx_slots','rx_frames_ok','rx_frames_bad',
        'rx_packets_ok','rx_packets_bad','tx_job_status','eth_control','eth_status','mstatus','mie','rx_id']

def audit_log(text,quiet):
    def line(key):
        values=re.findall('^AUDIT_'+key+r'=(.+)$',text,re.M)
        if len(values)!=1:raise ValueError('Missing/duplicate audit '+key)
        return values[0]
    if line('VERSION')!='1' or int(line('QUIET'))!=int(quiet):raise ValueError('Audit mode mismatch')
    result={}
    for key in ['INITIAL','BEFORE','AFTER']:
        values=[int(v,16) for v in line(key).split(',')]
        if len(values)!=len(FIELDS):raise ValueError('Audit snapshot length mismatch')
        result[key.lower()]=dict(zip(FIELDS,values))
    result['errors']=int(line('ERRORS'),16)
    result['restored_control']=int(line('RESTORED_CONTROL'),16)
    if result['errors'] or result['restored_control']!=1:raise ValueError('Peripheral audit/restore failed: '+str(result))
    a,b=result['before'],result['after']
    for s in [result['initial'],a,b]:
        if s['ai_status']&1 or s['dma_status']&1 or s['rx_status']&0xb3 or s['rx_slots']&15 or s['tx_job_status']&9:
            raise ValueError('Peripheral not idle')
        if s['mstatus']&8 or s['mie'] or s['rx_id']!=0x52584431:raise ValueError('Interrupt/register map mismatch')
    for key in FIELDS[1:15]+FIELDS[18:22]:
        if a[key]!=b[key]:raise ValueError('Activity counter changed: '+key)
    for s in [a,b]:
        if s['eth_control']!=int(not quiet) or bool(s['eth_status']&16)!=bool(not quiet):
            raise ValueError('Network enable/flush readback mismatch')
    return result
