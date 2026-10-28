#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -n "${RISCV_TOOLCHAIN_BIN:-}" ]; then export PATH="$RISCV_TOOLCHAIN_BIN:$PATH"; fi
cd "$task_root"
mkdir -p firmware/build
riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medany -O2 -g \
 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -Wall -Wextra \
 -Ifirmware/freestanding -Ifirmware -Iassets -Ifirmware/ethernet \
 firmware/start.S firmware/main.c firmware/nigo_ai.c firmware/ngu_upload.c \
 firmware/ultraface_runtime.c firmware/ultraface_decode.c firmware/face_events.c firmware/memory.c \
 firmware/ethernet/ethernet.c firmware/ethernet/ethernet_soc.c \
 -nostdlib -Wl,-T,firmware/link.ld,--gc-sections,-Map,firmware/build/application.map \
 -lgcc -o firmware/build/application.elf
riscv64-unknown-elf-objcopy -O binary firmware/build/application.elf firmware/build/application.bin
riscv64-unknown-elf-size firmware/build/application.elf
riscv64-unknown-elf-objdump -d firmware/build/application.elf > firmware/build/application.dis
python3 - <<'PY'
from pathlib import Path
import hashlib,json
p=Path('firmware/build');blob=(p/'application.bin').read_bytes()
assert len(blob)<=32768, 'application exceeds the 32 KiB boot ROM'
padded=blob+bytes(32768-len(blob))
rom=''.join(f'{int.from_bytes(padded[i:i+8],"little"):016x}\n' for i in range(0,32768,8))
(p/'boot64.hex').write_text(rom)
(p/'boot_manifest.json').write_text(json.dumps({'bytes':len(blob),'ROM_bytes':32768,
 'application_sha256':hashlib.sha256(blob).hexdigest(),
 'hex_sha256':hashlib.sha256(rom.encode()).hexdigest()},indent=2)+'\n')
PY
