"""Freeze the old measured RTL, changing only memory address mapping and boot stub."""
import argparse,hashlib,json,shutil
from pathlib import Path
HERE=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('reference_root',type=Path);a=p.parse_args()
 recorded=json.loads((a.reference_root/'inputs.json').read_text())
 dst=HERE/'reference/simulator';dst.mkdir(parents=True,exist_ok=True)
 files=[];provenance={}
 for name in recorded['compile_sources']:
  source=Path(name);assert sha(source)==recorded['sources'][str(source)],str(source)
  rel=source.relative_to(a.reference_root/'snapshot');target=dst/rel;target.parent.mkdir(parents=True,exist_ok=True)
  shutil.copy2(source,target);files.append(target);provenance[str(rel)]=sha(source)
 sim=HERE/'sim';sim.mkdir(exist_ok=True)
 text=(dst/'tb/pgl50h_soc_coremark_tb.v').read_text()
 replacements={
  'localparam integer RAM_WORDS = 65536; // 256 KiB / 32-bit word':'localparam integer RAM_WORDS = 524288; // 2 MiB at 0x82000000; benchmark still uses 256 KiB',
  'read_base = axi_araddr * 2;':'read_base = axi_araddr * 2 - 32\'h00800000;',
  'if ((read_base + read_index) < RAM_WORDS)':'if ((read_base + read_index) >= 0 && (read_base + read_index) < RAM_WORDS)',
  "else\n            axi_rdata[read_index*32 +: 32] <= 32'h0000_0000;":
  "else if (axi_araddr * 2 + read_index == 0)\n            axi_rdata[read_index*32 +: 32] <= 32'h02080297; // AUIPC t0, +0x02080000\n          else if (axi_araddr * 2 + read_index == 1)\n            axi_rdata[read_index*32 +: 32] <= 32'h00028067; // JALR x0,t0,0\n          else\n            axi_rdata[read_index*32 +: 32] <= 32'h00000013;",
  'write_base = axi_awaddr * 2;':"write_base = axi_awaddr * 2 - 32'h00800000;",
  'if (axi_wstrb[byte_index] && (write_index < RAM_WORDS))':'if (axi_wstrb[byte_index] && write_index >= 0 && (write_index < RAM_WORDS))'}
 for before,after in replacements.items():assert text.count(before)==1,before;text=text.replace(before,after)
 tb=sim/'pgl50h_soc_coremark_tb.v';tb.write_text(text)
 files=[tb if f.name=='pgl50h_soc_coremark_tb.v' else f for f in files]
 info=dict(scope='Original measured CPU/cache/HMIC RTL and one-cycle backing memory; remapped to 0x82000000; not a P3 DDR timing model',
           frozen_sources=provenance,compile_sources=[f.relative_to(HERE).as_posix() for f in files],tb_sha256=sha(tb))
 (sim/'sources.json').write_text(json.dumps(info,indent=2)+'\n');print('FROZEN_SIM_PREPARED',len(files))
if __name__=='__main__':main()
