"""Download to the candidate recovery loader and persist the validated app to A/B Flash."""
import argparse,sys
from pathlib import Path
C=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(C/'upper'))
from nigo_host.program import ProgramClient,validate_image
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--board',required=True);p.add_argument('--program',type=Path,required=True)
 p.add_argument('--bind',default='192.168.1.100')
 p.add_argument('--execute',action='store_true');p.add_argument('--save-timeout',type=int,default=3600,
   help='Whole-save retry budget in seconds; Flash writes use up to 256-byte page programs')
 a=p.parse_args()
 blob=a.program.read_bytes();entry,crc=validate_image(blob);client=ProgramClient(a.board,bind=a.bind)
 try:
  client.upload(blob)
  # CPU is synchronously programming Flash. Keep the same session and UDP source port.
  # A duplicate save ticket is answered from the firmware cache after completion.
  client.timeout=1;client.retries=a.save_timeout
  client.control(3,entry,crc)
  print('Application saved and readback-verified. FPGA configuration Flash was not changed.')
  if a.execute:client.control(2,entry,crc)
 finally:client.close()
if __name__=='__main__':main()
