#!/bin/bash
# Rewrites the JIT/EE interface GUID in a patched runtime tree.
#
# The fixup patches add JIT helpers and a JIT flag, which changes the JIT/EE
# contract, so the GUID has to differ from the one upstream shipped. Doing that
# in a patch does not work: a patch has to name the old value, and upstream
# rolls the GUID constantly, so it stops applying on the next VMR bump. This
# rewrites whatever value is there, by shape rather than by content.
#
# The value is fixed rather than random so that a JIT and a VM built from two
# separate runs of this pipeline still accept each other.
set -euo pipefail

runtime_dir="${1:-dotnet/src/runtime}"
guid_file="${runtime_dir}/src/coreclr/inc/jiteeversionguid.h"

[ -f "$guid_file" ] || { echo "jiteeversionguid.h not found under ${runtime_dir}" >&2; exit 1; }

# nethermind riscv64 soft-float series
new="d7f4b1a0-6c92-4e58-9b3d-0a17c5e2f846"
IFS='-' read -r p1 p2 p3 p4 p5 <<< "$new"
b="{0x${p4:0:2}, 0x${p4:2:2}, 0x${p5:0:2}, 0x${p5:2:2}, 0x${p5:4:2}, 0x${p5:6:2}, 0x${p5:8:2}, 0x${p5:10:2}}"

python3 - "$guid_file" "$new" "$p1" "$p2" "$p3" "$b" <<'PY'
import re, sys
path, guid, p1, p2, p3, braces = sys.argv[1:7]
s = open(path).read()
pat = re.compile(
    r'(constexpr GUID JITEEVersionIdentifier = \{ /\* )[0-9a-fA-F-]+( \*/\s*\n)'
    r'\s*0x[0-9a-fA-F]+,\s*\n\s*0x[0-9a-fA-F]+,\s*\n\s*0x[0-9a-fA-F]+,\s*\n'
    r'\s*\{[^}]*\}\s*\n')
new = (r'\g<1>' + guid + r'\g<2>'
       + f'    0x{p1},\n    0x{p2},\n    0x{p3},\n    {braces}\n')
s2, n = pat.subn(new, s)
if n != 1:
    print(f"jiteeversionguid.h: expected 1 GUID definition, rewrote {n}", file=sys.stderr)
    sys.exit(1)
open(path, 'w').write(s2)
print(f"JIT/EE GUID set to {guid}")
PY
