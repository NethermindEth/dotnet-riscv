#!/usr/bin/env python3
"""Fail if any archive member or object carries a compressed (C) or atomic (A)
instruction. objdump is unreliable here: when the ELF header does not advertise
C/A it renders them as <unknown>, so decode .text raw — a 16-bit parcel is any
halfword whose low two bits are not 0b11 — and grep an objdump disassembly for
the AMO/LR/SC mnemonics separately."""
import sys, struct, subprocess, re, glob, os

def members(path):
    data = open(path, "rb").read()
    if data[:8] != b"!<arch>\n":
        # plain object, not an archive
        if data[:4] == b"\x7fELF":
            yield os.path.basename(path), data
        return
    off, longnames = 8, b""
    while off + 60 <= len(data):
        hdr = data[off:off+60]
        name = hdr[0:16].decode("latin1").rstrip()
        size = int(hdr[48:58].decode().strip())
        body = data[off+60:off+60+size]
        off += 60 + size + (size & 1)
        if name == "//":
            longnames = body; continue
        if name in ("/", "/SYM64/", "__.SYMDEF"):
            continue
        if name.startswith("/") and name[1:].isdigit():
            idx = int(name[1:]); end = longnames.find(b"\n", idx)
            name = longnames[idx:end].decode("latin1").rstrip("/")
        else:
            name = name.rstrip("/")
        if body[:4] == b"\x7fELF":
            yield name, body

def compressed_count(b):
    e_shoff = struct.unpack_from("<Q", b, 0x28)[0]
    e_shentsize = struct.unpack_from("<H", b, 0x3a)[0]
    e_shnum = struct.unpack_from("<H", b, 0x3c)[0]
    e_shstrndx = struct.unpack_from("<H", b, 0x3e)[0]
    sh = [struct.unpack_from("<IIQQQQIIQQ", b, e_shoff + i*e_shentsize) for i in range(e_shnum)]
    stroff = sh[e_shstrndx][4]
    def nm(o):
        end = b.find(b"\x00", stroff+o); return b[stroff+o:end].decode("latin1")
    comp = 0
    for s in sh:
        name, stype, soff, ssize = nm(s[0]), s[1], s[4], s[5]
        if stype != 1 or not name.startswith(".text"):
            continue
        code = b[soff:soff+ssize]
        i = 0
        while i + 2 <= len(code):
            half = code[i] | (code[i+1] << 8)
            if (half & 3) != 3:
                comp += 1; i += 2
            else:
                i += 4
    return comp

def atomic_count(path, objdump):
    out = subprocess.run([objdump, "-d", path], capture_output=True, text=True).stdout
    return len(re.findall(r"\b(amo[a-z0-9.]+|lr\.[wd][a-z.]*|sc\.[wd][a-z.]*)\b", out))

def main():
    objdump = os.environ.get("OBJDUMP", "riscv64-linux-gnu-objdump")
    bad = 0
    for path in sys.argv[1:]:
        comp = sum(compressed_count(body) for _, body in members(path))
        atom = atomic_count(path, objdump)
        status = "OK" if (comp == 0 and atom == 0) else "FAIL"
        print(f"[{status}] {path}: compressed={comp} atomic={atom}")
        if comp or atom:
            bad += 1
    if bad:
        print(f"ISA scan FAILED: {bad} file(s) carry compressed/atomic instructions", file=sys.stderr)
        sys.exit(1)
    print("ISA scan OK: no compressed/atomic instructions")

if __name__ == "__main__":
    main()
