# Choice kernels

`aegis.secret` supplies a copyable one-bit `Choice`. The representation occupies
one byte and contains one decision bit. `and`, `or`, `xor`, and `not` produce
choices. `fromBit(u8)` imports a **public** bit and rejects values above one in
every build mode. Internal kernels establish the 0/1 invariant without a
secret-dependent validity branch.

`equal(N, a, b)` compares fixed byte arrays. `equalBytes(a, b)` returns
`CompareError.LengthMismatch` for unequal **public** lengths, including empty
against nonempty. It reads every byte of the public common length. Length is
not concealed. `compareUnsigned(N, endian, a, b)` returns `OrderChoices` with
exactly one of `lt`, `eq`, `gt` set; endian is public and both endian orders are
supported. Zero-byte integers compare equal.

A zero choice selects `a`; one selects `b`. `selectInt(T, a, b)` accepts signed
and unsigned 8/16/32/64-bit integers. Other integer widths, floating point,
aggregates, and secret indexing are unsupported. `selectBytes(N, out, a, b)`
accepts disjoint output or output exactly equal to either source. Partial
output/source overlap returns `SelectError.PartialOverlap` before mutation.
Sources may overlap each other. Both source bytes load before each result
store, including exact aliases. All source bytes must be initialized and live.
Addresses, extents and lengths are public. Bounds and extent validation stay
enabled in every mode.

`declassify(comptime reason)` explicitly releases a bool. Its trimmed reason
must be nonempty. A completed verdict may then control a branch. Formatting
with `{f}` is a compile error. Explicit casts, field access and generic
representation inspection can bypass these conventions in Zig; the type is
not a compiler information-flow proof. Neither select input may perform
secret-dependent work before entering the kernel.

## Compiler boundary

This batch stages one dispatch: Zig **0.17.0 LLVM**, `-mcpu=baseline`, ordinary
unmodified baseline feature sets. No target-specific hardware dispatch is
performed. The enabled profiles are:

| Target | CPU |
|---|---|
| x86_64-linux-gnu / x86_64-linux-musl | baseline x86_64 |
| aarch64-linux-gnu | generic |
| x86_64-windows-gnu / aarch64-windows-gnu | baseline x86_64 / generic |
| x86_64-macos / aarch64-macos | baseline x86_64 / apple_m1 |

Debug, ReleaseSafe, ReleaseFast and ReleaseSmall are checked. Root
`std_options.side_channels_mitigations` may be `basic`, `medium` (default), or
`full`; `none` is rejected. Other compiler versions/backends, custom CPU models
or features, 32-bit, wasm, freestanding, and unlisted OS/ABI profiles fail when
a kernel is instantiated. Other aegis modules remain usable on their own
supported profiles. Importing this lazy module alone does not enable a kernel.
Consumers must retain their own caller audit after composition, root-option,
compiler, flag or CPU changes.

## Kernels and evidence

Equality uses volatile byte loads and a full-length XOR reduction. Order
accumulates masked first-difference decisions without early exit. Select uses
opaque full-register masks and complements; both inputs participate. A tied
volatile empty inline assembly register blocks LLVM's mask reasoning. This is
a compiler barrier, not a hardware timing instruction or a universal
constant-time guarantee. The equivalent handwritten baseline retains the same
barriers, volatile loads, checks and decision representation.

`zig build check-choices` inspects enclosing optimized callers across every
listed profile and root mitigation option. Release modes require identical
normalized emitted instructions to the equivalent baseline. Debug retains
runtime safety and runs a stack-aware SSA regression detector. The detector
checks secret-derived branches, select conditions and address indices; two
deliberately unsafe compiled controls must be caught in each profile. It is a
regression check for these fixtures, not a sound whole-program analyzer.
`zig build check-choices-negative` verifies unsupported profiles/types and
explicit disclosure/format contracts. Native correctness tests live beside
the package's tests; `zig build bench` owns the manual paired measurements.
CI compiles benchmarks and does not gate on timing.

Fixtures preserve the c1 Montgomery limb count, fixed-window table scan and
completed offline padding-verdict shapes. They prove aegis composition at
those seams, not the entire curve, modular arithmetic or CBC cipher. The MAC/
Finished fixture describes a future caller shape. No cloak source is changed
and no consumer adoption is claimed. Choice does not own or erase its inputs;
secret owners retain their cleanup obligations. It cannot guarantee erasure
of historical copies, registers or caller-owned temporaries.

Manual timing uses aarch64/apple_m1 baseline code on a physical M3 Max macOS
host, with synthetic randomized
secret classes and paired ABBA/BAAB blocks. Raw compiler/timing evidence is
kept privately in trials. A separate native CPU Counters capture exports process-level cycle/bottleneck
metrics, without per-class cache-miss attribution. Native x86-64 timing,
class-resolved cache misses, power, EM, cross-thread leakage, and arbitrary
whole-program behavior are outside this evidence. Failure to resolve a timing difference is not proof of constant
time. A5 remains work in progress pending ordered integration and final gates.
