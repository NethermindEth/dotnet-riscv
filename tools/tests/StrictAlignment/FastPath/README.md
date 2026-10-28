# Strict alignment fast path (perf-76, perf-80, perf-81, perf-82, perf-84)

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
a span field, also reassigned, plus stores. Last come accesses spread over several blocks, whose
test perf-81 shares: a chain of reads with an early return after each, narrow reads before wide
ones, a diamond, a loop whose body jumps back to its first block, a base reassigned between the
blocks, a second base moved between them, a compare of two `in` structs that returns at every
limb, and a chain of stores. Then come regions that take in loops and returns (perf-82): loops over an
`in` struct and over a span field, read before, in and after the loop, a loop that jumps back to the
block after the first read, a second base moved in the loop, whose reads keep their tests, and returns
that each read a value of their own. Last come span locals, which the JIT promotes (perf-84): a span
at an aligned constant offset of an array, at an odd one and at a parameter offset, a span stored
twice, a span a call returns, a struct of two spans copied as a whole, and spans sliced in a loop by a
parameter step and by an odd constant. SP1 rejects any misaligned access, so the run also proves that an
aligned path is only taken on an aligned address. Success exits with code 0; a wrong value exits
with the number of the failed check (modulo 255: SP1 keeps 8 bits of the exit code) and the
runner reports it.
