"""Check every archived or freshly generated PDS timing summary against P3."""
import argparse,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def header(path):
    lines=[]
    with path.open(encoding='utf-8-sig',errors='replace') as f:
        for line in f:
            if line.startswith('Startpoint  : '):break
            lines.append(line)
    return ''.join(lines)
def checks(text):
    result={};section=None
    for line in text.splitlines():
        match=re.match(r'(Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((Slow|Fast) Corner\):',line)
        if match:section=match[1]+' '+match[2];result.setdefault(section,[]);continue
        if not section:continue
        parts=line.split()
        if len(parts) not in (5,6):continue
        try:w,t=float(parts[-4]),float(parts[-3]);f,n=int(parts[-2]),int(parts[-1])
        except ValueError:continue
        result[section].append(dict(clocks=' -> '.join(parts[:-4]),worst_ns=w,total_negative_ns=t,failing_endpoints=f,total_endpoints=n))
    return {k:v for k,v in result.items() if v}
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('directory',nargs='?',type=Path,default=ROOT/'reference/p3_setup25');a=ap.parse_args()
    actual={}
    for name in ['setup','hold']:
        path=a.directory/(name+'.rtr')
        if not path.exists():path=a.directory/(name+'_summary.txt')
        actual.update(checks(header(path)))
    expected=json.loads((ROOT/'reference/p3_setup25/timing_result.json').read_text())['additional_timing_summaries']
    assert actual.keys()==expected.keys(),('Missing timing check',actual.keys(),expected.keys())
    assert all(row['failing_endpoints']==0 and row['worst_ns']>=0 for rows in actual.values() for row in rows),'Timing violation'
    assert actual==expected,'Full timing summaries differ from the frozen reference'
    for section,rows in actual.items():print(section, 'worst_ns=',min(x['worst_ns'] for x in rows),'failing_endpoints=',sum(x['failing_endpoints'] for x in rows))
    print('P3_FULL_SUMMARY_MATCH_PASS')
if __name__=='__main__':main()
