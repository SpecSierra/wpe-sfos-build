#!/usr/bin/env python3
"""Rename __isoc23_* symbols to their plain equivalents in an ELF binary."""
import sys, re

RENAMES = {
    b'__isoc23_strtoul': b'strtoul',
    b'__isoc23_strtoull': b'strtoull',
    b'__isoc23_strtol': b'strtol',
    b'__isoc23_strtoll': b'strtoll',
    b'__isoc23_sscanf': b'sscanf',
    b'__isoc23_fscanf': b'fscanf',
    b'__isoc23_scanf': b'scanf',
    b'__isoc23_vsscanf': b'vsscanf',
    b'__isoc23_vfscanf': b'vfscanf',
    b'__isoc23_vscanf': b'vscanf',
}

path = sys.argv[1]
data = bytearray(open(path, 'rb').read())
changed = 0
for old, new in RENAMES.items():
    # old pattern: old + null byte; replace with new + null + padding
    pattern = old + b'\x00'
    replacement = new + b'\x00' + b'\x00' * (len(old) - len(new))
    idx = 0
    while True:
        pos = data.find(pattern, idx)
        if pos == -1:
            break
        data[pos:pos+len(pattern)] = replacement
        print(f"  renamed {old.decode()} -> {new.decode()} at offset {pos:#x}")
        changed += 1
        idx = pos + 1

if changed:
    open(path, 'wb').write(data)
    print(f"Done. {changed} symbol(s) renamed.")
else:
    print("No isoc23 symbols found.")
