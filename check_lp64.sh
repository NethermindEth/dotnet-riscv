#!/bin/sh
# Gate: every riscv64 ELF produced by the build must claim the lp64 (soft-float)
# ABI. The float ABI lives in bits 1-2 of e_flags, at offset 0x30 of the ELF64
# header; lp64 is 0, and anything else (single 2, double 4, quad 6) is a
# regression — lld would then refuse to mix it with the rest of the image, and a
# double-float claim that does link would misdescribe the calling convention.
#
# Reads the header directly instead of using readelf, which the build container
# does not necessarily carry. Archives are unpacked and their members checked,
# since libRuntime.*.a is where client-bound objects live.
#
# usage: check_lp64.sh <dir> [<dir>...]
set -eu

[ "$#" -gt 0 ] || { echo "usage: $0 <dir> [<dir>...]" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

checked=0
bad=0

# Prints the float-ABI nibble of a riscv64 ELF64, or nothing if not one.
abi_of() {
    [ -f "$1" ] || return 0
    [ "$(od -An -tx1 -N5 "$1" 2>/dev/null | tr -d ' ')" = "7f454c4602" ] || return 0
    [ "$(od -An -tx1 -j18 -N2 "$1" 2>/dev/null | tr -d ' ')" = "f300" ] || return 0
    b=$(od -An -tu1 -j48 -N1 "$1" 2>/dev/null | tr -d ' ')
    echo $((b & 6))
}

report() {
    case $2 in
    2) name="lp64f (single)" ;;
    4) name="lp64d (double)" ;;
    6) name="lp64q (quad)" ;;
    *) name="unknown ($2)" ;;
    esac
    echo "  $1: $name"
}

for root in "$@"; do
    [ -d "$root" ] || continue
    # Absolute, so that "ar x" still resolves the archive after cd'ing into the
    # scratch directory.
    root=$(cd "$root" && pwd)
    find "$root" -type f | while read -r f; do
        case $f in
        *.a)
            m="$work/ar"; rm -rf "$m"; mkdir -p "$m"
            (cd "$m" && ar x "$f" 2>/dev/null) || continue
            find "$m" -type f | while read -r o; do
                a=$(abi_of "$o") || true
                [ -n "${a:-}" ] || continue
                echo "CHECKED"
                [ "$a" = 0 ] || { echo "BAD $(basename "$f")($(basename "$o")) $a"; }
            done
            ;;
        *)
            a=$(abi_of "$f") || true
            [ -n "${a:-}" ] || continue
            echo "CHECKED"
            [ "$a" = 0 ] || { echo "BAD $f $a"; }
            ;;
        esac
    done
done > "$work/log"

checked=$(grep -c '^CHECKED$' "$work/log" || true)
bad=$(grep -c '^BAD ' "$work/log" || true)

echo "riscv64 ELF objects checked: $checked"
if [ "$bad" != 0 ]; then
    echo "not lp64 after the linker ($bad):" >&2
    grep '^BAD ' "$work/log" | while read -r _ what a; do report "$what" "$a"; done >&2
    exit 1
fi
if [ "$checked" = 0 ]; then
    echo "no riscv64 ELF objects found — nothing was verified" >&2
    exit 1
fi
echo "all lp64"
