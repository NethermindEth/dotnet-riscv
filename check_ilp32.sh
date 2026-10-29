#!/bin/bash
# Gate: every ELF object of the riscv32 target must be RV32 (ELF32, RISC-V)
# for the ilp32 soft-float ABI without the C extension, as the RV32IM guest
# runs: the low nibble of e_flags must be 0 (bit 0: RVC, bits 1-2: the float
# ABI, bit 3: RVE). An object built for clang's default rv32 ABI (ilp32d) or
# with compressed code would not link with the rest, or would trap; an
# riscv64 object would not link at all. The riscv32 counterpart of
# check_lp64.sh.
#
# Reads the headers with llvm-readelf (READELF overrides it), which also
# reads each member of an archive, two members with one name included.
#
# usage: check_ilp32.sh <dir> [<dir>...]
set -euo pipefail

[ "$#" -gt 0 ] || { echo "usage: $0 <dir> [<dir>...]" >&2; exit 2; }

readelf="${READELF:-llvm-readelf}"
command -v "$readelf" > /dev/null || { echo "$0: no $readelf" >&2; exit 2; }

checked=0
bad=()

# Prints "<file> <class> <machine> <flags...>" for each ELF object of $1, a
# file or an archive.
headers()
{
    "$readelf" -h "$1" 2>/dev/null | awk -v top="$1" '
        /^File: / { name = substr($0, 7) }
        $1 == "Class:" { class = $2 }
        $1 == "Machine:" { machine = $2 }
        $1 == "Flags:" { flags = $0; sub(/^ *Flags: */, "", flags)
                         print (name != "" ? name : top), class, machine, flags; name = "" }'
}

while IFS= read -r -d '' f ; do
    case "$f" in
        *.a|*.o|*.obj) ;;
        *) [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' ')" = "7f454c46" ] || continue ;;
    esac
    while read -r name class machine flags ; do
        checked=$((checked + 1))
        if [ "$class" != "ELF32" ] || [ "$machine" != "RISC-V" ] ; then
            bad+=("$name: $class $machine")
        elif [ $(( ${flags%%,*} & 0xf )) -ne 0 ] ; then
            bad+=("$name: e_flags $flags")
        fi
    done < <(headers "$f")
done < <(find "$@" -type f -print0)

echo "riscv32 ELF objects checked: $checked"
if [ ${#bad[@]} -ne 0 ] ; then
    echo "not RV32 ilp32 without RVC (${#bad[@]}):" >&2
    printf '  %s\n' "${bad[@]}" >&2
    exit 1
fi
if [ "$checked" -eq 0 ] ; then
    echo "no ELF objects found: nothing was verified" >&2
    exit 1
fi
echo "all RV32 ilp32 without RVC"
