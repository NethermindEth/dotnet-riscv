# Strict alignment fast path (perf-76, perf-80)

Run with a RISC-V bflat toolchain built from this patch series and Docker:

```sh
bash tools/tests/StrictAlignment/FastPath/run.sh
```

`BFLAT` overrides the bflat executable and `SP1_RUNNER_IMAGE` the SP1 runner image.

The program loads and stores 2-, 4- and 8-byte values through a byref parameter at every
misalignment, with offsets that are multiples of the access size (the base+offset address mode
perf-76 keeps for the alignment test), offsets that are not, and negative ones, and sums words
through stackalloc'd space. Every value is compared with the one assembled from single bytes.
It then makes several accesses through one base, whose alignment test perf-80 shares: plain
words, mixed sizes (the narrow ones first), offsets that change the alignment and keep their own
test, the base reassigned between two runs, a base bumped by an odd step in a loop, a pointer, and
a span field, also reassigned, plus stores. SP1 rejects any misaligned access, so the run also
proves that an aligned path is only taken on an aligned address. Success exits with code 0; a
wrong value exits with the number of the failed check and the runner reports it.
