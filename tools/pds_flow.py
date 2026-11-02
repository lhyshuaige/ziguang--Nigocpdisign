"""Prepare a portable PDS source project, or replay STA on the signed routed DB.

Preparation does not run synthesis, P&R, STA, programming or Flash writes.
STA/bitstream commands execute only with --run; hardware downloading is separate.
"""
import argparse,hashlib,json,os,re,shutil,subprocess,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];TOP='pg2l100h_soc_p3_top'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def quote(p):return '{'+Path(p).as_posix()+'}'
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('action',choices=['prepare','sta','bitstream'])
    ap.add_argument('--pds-bin',default=os.environ.get('PDS_BIN',''))
    ap.add_argument('--work',type=Path)
    ap.add_argument('--use-reference-placement',action='store_true')
    ap.add_argument('--run',action='store_true')
    a=ap.parse_args();manifest=json.loads((ROOT/'pds/sources.json').read_text())
    for rel in manifest['rtl']+manifest['constraints']+[manifest['physical']]:
        if not (ROOT/rel).is_file():raise SystemExit('Missing project input: '+rel)
    work=(a.work or ROOT/'build'/('p3_source' if a.action=='prepare' else 'p3_reference_'+a.action)).resolve()
    work.mkdir(parents=True,exist_ok=True)
    if a.action=='prepare':
        text=(ROOT/'pds/source_template.pds').read_text(encoding='utf-8').replace('@REPO@',ROOT.as_posix()).replace('@WORK@',work.as_posix())
        # PDS may change its working directory. Localize only the ROM filename.
        top=(ROOT/'rtl/pg2l100h_soc_rx_top.v').read_text(encoding='utf-8')
        old='firmware/bootloader/boot64.hex';assert top.count(old)==1
        local=work/'source/pg2l100h_soc_rx_top.v';local.parent.mkdir(exist_ok=True)
        local.write_text(top.replace(old,(ROOT/old).as_posix()),encoding='utf-8')
        text=text.replace((ROOT/'rtl/pg2l100h_soc_rx_top.v').as_posix(),local.as_posix())
        if a.use_reference_placement:
            needle='        (_widget wgt_edit_placement_cons\n            (_attribute _click_to_run (_switch ON))\n        )'
            body='        (_widget wgt_edit_placement_cons\n            (_attribute _click_to_run (_switch ON))\n            (_input (_file "'+(ROOT/manifest['physical']).as_posix()+'" (_format pcf)))\n        )'
            assert needle in text;text=text.replace(needle,body)
        text=text.replace('(_command cmd_pnr\n            (_gci_state (_integer 4))','(_command cmd_pnr\n            (_gci_state (_integer 4))\n            (_option optimize_multi_corner_timing (_switch ON))\n            (_option fix_hold_violation (_switch ON))\n            (_option fix_hold_violation_threshold_for_clock_path_cross_srb (_integer 50))\n            (_option max_hold_violated_paths_num (_integer 50000))')
        output=work/'Nigo_P3.pds';output.write_text(text,encoding='utf-8')
        for name in re.findall(r'\(_file "([^"]+)"',text):assert Path(name).is_file(),name
        print('SOURCE_PROJECT_PREPARED',output)
        print('Open this PDS project to perform a NEW implementation. Its timing must be measured independently.')
        return
    reference=ROOT/'reference/p3_setup25';meta=json.loads((reference/'database.json').read_text())
    archive=reference/'routed_db.zip';assert sha(archive)==meta['archive_sha256']
    db=work/meta['member']
    if not db.exists():
        with zipfile.ZipFile(archive) as z:
            assert z.namelist()==[meta['member']] and Path(meta['member']).name==meta['member']
            with z.open(meta['member']) as src,db.open('wb') as dst:shutil.copyfileobj(src,dst)
    assert sha(db)==meta['sha256'],'Routed database hash mismatch'
    lines=['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
    if a.action=='sta':
        for mode,label in [('max','setup'),('min','hold')]:
            lines += ['report_timing -force_to_run -input_db_file '+quote(db)+' -delay_type '+mode+' -max_path 3000 -report_io_datasheet -report_max_skew -report_exception TRUE',
                'file copy -force '+quote(work/'report_timing'/f'{TOP}.rtr')+' '+quote(work/(label+'.rtr')),
                'file copy -force '+quote(work/'report_timing'/f'{TOP}_exception.rtr')+' '+quote(work/(label+'_exception.rtr'))]
    else:
        lines += ['gen_bit_stream -force_to_run -input_db_file '+quote(db)+' -create_bit_file TRUE -create_bin_file -write_drm_data TRUE -scbv {High Voltage}']
    lines+=['puts {NIGO_REFERENCE_'+a.action.upper()+'_DONE}','exit']
    script=work/(a.action+'.tcl');script.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('REFERENCE_DB_VERIFIED',meta['sha256']);print('TCL_PREPARED',script)
    if not a.run:
        print('Prepared only. Add --run --pds-bin <PDS bin directory> to execute.');return
    executable=Path(a.pds_bin)/'pds_shell.exe'
    if not executable.is_file():raise SystemExit('Set --pds-bin or PDS_BIN to the installed PDS bin directory')
    log=work/(a.action+'.log')
    if log.exists():raise SystemExit('Existing run log: choose a new --work directory to preserve evidence')
    with script.open('rb') as inp,log.open('wb') as output:
        result=subprocess.run([str(executable)],stdin=inp,stdout=output,stderr=subprocess.STDOUT,cwd=work)
    text=log.read_bytes().decode('gb18030',errors='replace')
    if result.returncode or re.search(r'(?mi)^E:|^error |^couldn.t |Program Error Out',text):raise SystemExit('PDS error; inspect '+str(log))
    assert 'NIGO_REFERENCE_'+a.action.upper()+'_DONE' in text
    if a.action=='sta':
        subprocess.run([os.sys.executable,str(ROOT/'tools/check_timing.py'),str(work)],check=True)
    print('PDS_COMPLETED',log)
if __name__=='__main__':main()
