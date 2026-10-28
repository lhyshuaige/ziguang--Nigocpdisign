"""Verify this exported A30 source package without external dependencies."""
import hashlib,json
from pathlib import Path
R=Path(__file__).resolve().parent
checks=json.loads((R/'CHECKSUMS.json').read_text(encoding='utf-8'))
actual={p.relative_to(R).as_posix() for p in R.rglob('*') if p.is_file()
        and p.relative_to(R).parts[0] not in ('out','.git') and p.name!='CHECKSUMS.json'
        and '__pycache__' not in p.parts}
assert actual==set(checks['files']),('unlisted or missing files',sorted(actual-set(checks['files'])),sorted(set(checks['files'])-actual))
for name, expected in checks['files'].items():
    path=R/name
    assert path.is_file(), name
    assert hashlib.sha256(path.read_bytes()).hexdigest()==expected, name
print('A30_PACKAGE_PASS',len(checks['files']),'files')
