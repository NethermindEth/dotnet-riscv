#!/bin/bash
# Makes the JIT's RISC-V code serve both riscv64 and riscv32.
#
# The JIT's RISC-V code is written against TARGET_RISCV64, but almost all of it is
# about the ISA rather than about XLEN. This renames TARGET_RISCV64 to a family macro,
# TARGET_RISCV, throughout src/coreclr/jit, and has jit.h define TARGET_RISCV for either
# width, the way it defines TARGET_ARMARCH for arm and arm64. Code that depends on the
# register width then says so with TARGET_64BIT, which the riscv32 patches add.
#
# It is a script rather than a patch for the reason bump_jitee_guid.sh is: a patch
# carrying the rename would have to name every line it touches, so it would stop
# applying whenever a perf patch adds or moves a TARGET_RISCV64 line. The rename works
# by pattern and does not care. It runs after the other fixups and before the riscv32
# patches, which are written against the renamed tree.
set -euo pipefail

runtime_dir="${1:-dotnet/src/runtime}"
jit_dir="${runtime_dir}/src/coreclr/jit"
jit_h="${jit_dir}/jit.h"

[ -f "$jit_h" ] || { echo "jit.h not found under ${runtime_dir}" >&2; exit 1; }

if grep -q "^#define TARGET_RISCV 1$" "$jit_h" ; then
    echo "TARGET_RISCV family already present"
    exit 0
fi

# Word-bounded, so TARGET_RISCV64_FOO-style names (none today) would not be touched.
grep -rlZ --include='*.h' --include='*.hpp' --include='*.cpp' -w 'TARGET_RISCV64' "$jit_dir" \
    | xargs -0 -r sed -i 's/\bTARGET_RISCV64\b/TARGET_RISCV/g'

# jit.h has the architecture checks, but jitpch.h includes jitconfig.h first, and the
# RISC-V block of jitconfigvalues.h has to see the family too, so both define it.
python3 - "$jit_h" "${jit_dir}/jitconfig.h" <<'PY'
import sys
family = (
    "\n"
    "// TARGET_RISCV is the RISC-V family; the target defines say the width.\n"
    "#if (defined(TARGET_RISCV64) || defined(TARGET_RISCV32)) && !defined(TARGET_RISCV)\n"
    "#if defined(TARGET_RISCV64) && defined(TARGET_RISCV32)\n"
    "#error Cannot define both TARGET_RISCV64 and TARGET_RISCV32\n"
    "#endif\n"
    "#define TARGET_RISCV 1\n"
    "#endif\n"
)
anchors = {
    sys.argv[1]: "#error Unsupported or unset host architecture\n#endif\n",
    sys.argv[2]: "#define _JITCONFIG_H_\n",
}
for path, anchor in anchors.items():
    s = open(path).read()
    if s.count(anchor) != 1:
        print(f"{path}: anchor not found exactly once", file=sys.stderr)
        sys.exit(1)
    open(path, "w").write(s.replace(anchor, anchor + family))
PY

left="$(grep -rlw --include='*.h' --include='*.hpp' --include='*.cpp' 'TARGET_RISCV64' "$jit_dir" | grep -v -E '/(jit|jitconfig)\.h$' || true)"
if [ -n "$left" ] ; then
    echo "TARGET_RISCV64 still used outside jit.h and jitconfig.h:" >&2
    echo "$left" >&2
    exit 1
fi
echo "JIT RISC-V code now keyed on TARGET_RISCV"
