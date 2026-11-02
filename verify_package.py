"""Offline integrity and dependency checks. Never accesses or programs a board."""
import ast,hashlib,json,re,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
    return h.hexdigest()
def files():
    for p in ROOT.rglob('*'):
        if not p.is_file():continue
        parts=p.relative_to(ROOT).parts
        if any(x in parts for x in ['.git','build','obj','__pycache__','.venv','logs']):continue
        yield p
def main():
    checks=json.loads((ROOT/'CHECKSUMS.json').read_text(encoding='utf-8'))
    for rel,h in checks.items():
        assert (ROOT/rel).is_file(),'Missing packaged file: '+rel
        assert sha(ROOT/rel)==h,'Changed packaged file: '+rel
    manifest=json.loads((ROOT/'pds/sources.json').read_text())
    for rel in manifest['rtl']+manifest['constraints']+[manifest['physical']]:assert (ROOT/rel).is_file(),rel
    assert len(manifest['rtl'])==len(set(manifest['rtl']))
    for name in ['runtime','arcade']:
        recipe=json.loads((ROOT/'firmware/recipes'/f'{name}.json').read_text())
        for rel,h in recipe['input_sha256'].items():assert sha(ROOT/rel)==h,rel
        assert sha(ROOT/'upper/assets/firmware'/f'{name}.ngb')==recipe['ngb_sha256']
    meta=json.loads((ROOT/'upper/assets/firmware/runtime.json').read_text())
    assert meta['build_id']=='9700ce2a'
    for rel,h in json.loads((ROOT/'upper/assets/SHA256SUMS.json').read_text()).items():assert sha(ROOT/'upper'/rel)==h,rel
    ref=ROOT/'reference/p3_setup25';meta=json.loads((ref/'database.json').read_text());archive=ref/'routed_db.zip'
    assert sha(archive)==meta['archive_sha256']
    with zipfile.ZipFile(archive) as z:
        assert z.namelist()==[meta['member']]
        h=hashlib.sha256()
        with z.open(meta['member']) as stream:
            for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
        assert h.hexdigest()==meta['sha256']
    for p in files():
        rel=p.relative_to(ROOT).as_posix()
        assert not any(x in p.relative_to(ROOT).parts for x in ['mysample','.env']),rel
        assert p.stat().st_size<50*1024*1024,('Oversized Git file',rel)
        if p.suffix=='.py':ast.parse(p.read_text(encoding='utf-8-sig'),filename=rel)
        if p.suffix=='.json':json.loads(p.read_text(encoding='utf-8-sig'))
    for p in [ROOT/'README.md',ROOT/'upper/README.md',*list((ROOT/'docs').glob('*.md'))]:
        for link in re.findall(r'\]\(([^)]+)\)',p.read_text(encoding='utf-8')):
            if '://' in link or link.startswith('#'):continue
            target=(p.parent/link.split('#')[0]).resolve();assert target.exists(),(p.name,link)
    print('PACKAGE_PASS files=%d HDL=%d FDC=%d runtime=9700ce2a reference_DB_SHA256=%s'%(len(checks),len(manifest['rtl']),len(manifest['constraints']),meta['sha256']))
if __name__=='__main__':main()
