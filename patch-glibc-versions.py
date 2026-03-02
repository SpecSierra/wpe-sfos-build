#!/usr/bin/env python3
"""
Patch GLIBC version requirements in ELF binaries so they run on SFOS (glibc 2.30).

GCC 13 on Ubuntu 24.04 (glibc 2.39) tags pthread/sem/math symbols as GLIBC_2.34
or GLIBC_2.38 because those functions moved from libpthread/libm into libc in that
release. On SFOS they exist in libpthread.so.0 / libm.so.6 under GLIBC_2.17.

Since the version strings are the same byte-length (10 chars + NUL = 11 bytes)
we can replace them in-place without touching offsets anywhere else in the ELF.
We also fix the vna_hash field in VERNEED entries to match the new name.
Then we add libpthread.so.0 to DT_NEEDED so the loader can find the symbols.
"""
import sys, struct, subprocess
from pathlib import Path

REPLACEMENTS = [
    (b'GLIBC_2.38\x00', b'GLIBC_2.17\x00'),
    (b'GLIBC_2.36\x00', b'GLIBC_2.17\x00'),
    (b'GLIBC_2.35\x00', b'GLIBC_2.17\x00'),
    (b'GLIBC_2.34\x00', b'GLIBC_2.17\x00'),
    (b'GLIBC_2.33\x00', b'GLIBC_2.17\x00'),
    (b'GLIBC_2.32\x00', b'GLIBC_2.17\x00'),
]

def elf_hash(name: str) -> int:
    h = 0
    for c in name:
        h = ((h << 4) + ord(c)) & 0xffffffff
        g = h & 0xf0000000
        if g:
            h ^= g >> 24
        h &= ~g & 0xffffffff
    return h

def fix_verneed_hashes(data: bytearray) -> bool:
    """Walk the .gnu.version_r section and fix vna_hash for any renamed entries."""
    # Only handle 64-bit little-endian ELF (aarch64)
    if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1:
        return False

    e_shoff = struct.unpack_from('<Q', data, 0x28)[0]
    e_shentsize = struct.unpack_from('<H', data, 0x3A)[0]
    e_shnum = struct.unpack_from('<H', data, 0x3C)[0]
    e_shstrndx = struct.unpack_from('<H', data, 0x3E)[0]

    shstrtab_sh_off = e_shoff + e_shstrndx * e_shentsize
    shstrtab_data_off = struct.unpack_from('<Q', data, shstrtab_sh_off + 0x18)[0]

    def get_name(base, off):
        idx = base + off
        s = b''
        while data[idx]:
            s += bytes([data[idx]])
            idx += 1
        return s

    changed = False
    for i in range(e_shnum):
        sh_off = e_shoff + i * e_shentsize
        sh_name_idx = struct.unpack_from('<I', data, sh_off)[0]
        sh_type = struct.unpack_from('<I', data, sh_off + 4)[0]
        sh_offset = struct.unpack_from('<Q', data, sh_off + 0x18)[0]
        sh_size = struct.unpack_from('<Q', data, sh_off + 0x20)[0]
        sh_link = struct.unpack_from('<I', data, sh_off + 0x28)[0]
        sec_name = get_name(shstrtab_data_off, sh_name_idx)

        if sec_name != b'.gnu.version_r':
            continue

        dynstr_sh_off = e_shoff + sh_link * e_shentsize
        dynstr_off = struct.unpack_from('<Q', data, dynstr_sh_off + 0x18)[0]

        off = sh_offset
        while off < sh_offset + sh_size:
            vn_cnt = struct.unpack_from('<H', data, off + 2)[0]
            vn_aux = struct.unpack_from('<I', data, off + 8)[0]
            vn_next = struct.unpack_from('<I', data, off + 12)[0]

            aux_off = off + vn_aux
            while True:
                vna_hash = struct.unpack_from('<I', data, aux_off)[0]
                vna_name_idx = struct.unpack_from('<I', data, aux_off + 8)[0]
                vna_next = struct.unpack_from('<I', data, aux_off + 12)[0]

                ver_name = get_name(dynstr_off, vna_name_idx).decode('ascii', errors='replace')
                correct_hash = elf_hash(ver_name)
                if vna_hash != correct_hash:
                    struct.pack_into('<I', data, aux_off, correct_hash)
                    changed = True

                if not vna_next:
                    break
                aux_off += vna_next

            if not vn_next:
                break
            off += vn_next

    return changed

def patch(path: Path):
    data = bytearray(path.read_bytes())
    changed = False
    for old, new in REPLACEMENTS:
        assert len(old) == len(new)
        if bytes(old) in data:
            idx = 0
            while True:
                pos = data.find(old, idx)
                if pos == -1:
                    break
                data[pos:pos + len(old)] = new
                changed = True
                idx = pos + len(new)

    if changed:
        print(f"  patched version strings: {path}")

    # Fix vna_hash fields that don't match their (possibly renamed) version strings
    if fix_verneed_hashes(data):
        changed = True
        print(f"  fixed verneed hashes:    {path}")

    if changed:
        path.write_bytes(bytes(data))

    # Always try to add libpthread.so.0 (patchelf is idempotent for --add-needed)
    r = subprocess.run(
        ['patchelf', '--add-needed', 'libpthread.so.0', str(path)],
        capture_output=True
    )
    if r.returncode == 0:
        print(f"  added libpthread.so.0:   {path}")

def patch_no_pthread(path: Path):
    """Patch without adding libpthread.so.0 (for external libs like libstdc++)."""
    data = bytearray(path.read_bytes())
    changed = False
    for old, new in REPLACEMENTS:
        assert len(old) == len(new)
        if bytes(old) in data:
            idx = 0
            while True:
                pos = data.find(old, idx)
                if pos == -1:
                    break
                data[pos:pos + len(old)] = new
                changed = True
                idx = pos + len(new)

    if changed:
        print(f"  patched version strings: {path}")

    if fix_verneed_hashes(data):
        changed = True
        print(f"  fixed verneed hashes:    {path}")

    if changed:
        path.write_bytes(bytes(data))

# If explicit paths are given on the command line, patch only those files.
if len(sys.argv) > 1:
    for arg in sys.argv[1:]:
        p = Path(arg)
        if not p.exists():
            print(f"warning: {p} does not exist, skipping", file=sys.stderr)
            continue
        if p.is_symlink():
            print(f"warning: {p} is a symlink, skipping", file=sys.stderr)
            continue
        # Use patch_no_pthread for libstdc++/libgcc_s/libEGL, patch for everything else
        if any(p.name.startswith(n) for n in ('libstdc++', 'libgcc_s', 'libcxx-compat', 'libEGL')):
            patch_no_pthread(p)
        else:
            patch(p)
    print("Done.")
    sys.exit(0)

# --- Legacy mode: no arguments — patch the hardcoded workspace build tree ---
# Set BUILD_ROOT and ARTIFACTS_ROOT to match your environment if they differ.
BUILD_ROOT     = Path('/workspace/wpewebkit-2.50.5/WebKitBuild/Release')
ARTIFACTS_ROOT = Path('/workspace/wpe-sfos-artifacts')

build = BUILD_ROOT
targets = list((build / 'bin').glob('WPE*')) + \
          [build / 'bin' / 'MiniBrowser', build / 'bin' / 'jsc'] + \
          list((build / 'lib').glob('libWPEWebKit*.so*')) + \
          list((build / 'lib').glob('libWPEInjectedBundle*.so*'))

for t in sorted(set(targets)):
    if t.exists() and not t.is_symlink():
        patch(t)

# Also patch any existing artifact bins/libs (may be stale copies)
arts = ARTIFACTS_ROOT
art_targets = list((arts / 'bin').glob('WPE*')) + \
              [arts / 'bin' / 'MiniBrowser'] + \
              list((arts / 'lib').glob('libWPEWebKit*.so*')) + \
              list((arts / 'lib').glob('libWPEInjectedBundle*.so*')) + \
              list((arts / 'lib').glob('libwpe*.so*')) + \
              list((arts / 'lib').glob('libWPEBackend*.so*'))

for t in sorted(set(art_targets)):
    if t.exists() and not t.is_symlink():
        patch(t)

# Patch qtwpe plugin, wpe-browser POC app, and crash handler
qtwpe_targets = [
    arts / 'bin' / 'wpe-browser',
    arts / 'lib' / 'qt5' / 'qml' / 'org' / 'wpewebkit' / 'qtwpe' / 'libqtwpe.so',
    arts / 'lib' / 'libcrash_handler.so',
]
for t in qtwpe_targets:
    if t.exists() and not t.is_symlink():
        patch(t)

# Also patch libstdc++ and libgcc_s that we ship in artifacts
artifact_lib = ARTIFACTS_ROOT / 'lib'
for name in ['libstdc++.so.6.0.33', 'libgcc_s.so.1', 'libcxx-compat.so', 'libEGL.so.1']:
    p = artifact_lib / name
    if p.exists() and not p.is_symlink():
        patch_no_pthread(p)

print("Done.")
