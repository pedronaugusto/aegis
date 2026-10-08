> Historical full-width audit at 7b62798: the 606/202 counts and red result below are unchanged historical evidence. Owner db221e5 subsequently narrowed the C ABI guarantee to 8–64-bit and usize/isize; 128-bit reprs remain Zig types only. The current profile and continuation are recorded in [A4 status](a4-status.md). No compiler change is needed for that approved profile.

# A3 ABI repair candidate — blocked on one compiler profile

Owner correction: tychobook commit c8d2b481d27df0a73d0e89971cc0577b037babdf, aegis design §3.4. Starting published aegis main is fcff07ba18628efc639f527c579d4138fc9cebda. This candidate implements the representation correction before any A4 code. Secret(T), Guarded(T), A1 behavior and original evidence are unchanged. SecretBytes has not started. No consumer repository or book was edited.

Id, NonZero, Count, Bytes, Bits, Duration, Instant, Ranged and Counter now use non-exhaustive enum(Repr). Factory APIs, named errors, arithmetic, domain identities, import checks and endian formats are preserved. Private struct fields disappear; unchecked enum construction/reflection remains a caller bypass. Scalar size/alignment stays Repr. Counter keeps its checked last-issued state without a second field. Checked/Saturating remain unchanged.

## Regression and raw-integer interoperability evidence

The old matching typed prototypes did not prove C interoperability. Layout equality was insufficient. [Failing-before lowering](a3-abi-correction-before.txt) retains x86-linux-gnu LLVM code from unchanged production A3: the aegis declaration calls `raw_exchange_u32` with hidden sret and byval struct parameters, while the raw integer caller calls the same symbol with two i32 arguments and an i32 return. A separately compiled raw export has the latter prototype. [Regression log](a3-abi-correction-regression.txt) records the actual failing gate before the production change. `a3-abi-before.txt` is older auto-layout rejection evidence and does not expose this calling-convention defect.

`ci/abi_raw.zig` is a separate translation unit exporting only raw integer C prototypes. `ci/abi.zig` calls those symbols through aegis-typed extern declarations and through raw-integer extern declarations; the calls are analyzed and emitted. Both argument positions carry distinct runtime inputs, and the return is consumed. Each fixture also constructs an extern record with leading/trailing fields, checks size/alignment/offsets against its raw record, and calls a raw-record accessor through the typed declaration. There is no matching aegis-typed implementation on the other side.

`ci/abi_check.zig` compiles both units for every configured target (including musl), plus x86 32-bit and wasm32. Each target emits 606 argument/return and 606 record-field pairs covering every factory, signed/unsigned 8/16/32/64/128 and usize/isize, every duration scale and every std.Io clock tag. LLVM aliases must refer to the same analyzed function for the typed and raw callers. This is deterministic cross codegen proof, not foreign-target execution. Native execution separately links the raw object, without LTO, and tests minimum, maximum and one through all 606 scalar/record fixtures.

[Complete audit](a3-abi-correction-audit.txt): eight of nine target profiles pass all pairs after the enum correction. Native aarch64 macOS execution passes. No native Linux, Windows, x86 32-bit or wasm execution is claimed here.

**Unresolved: x86_64-windows-gnu, signed and unsigned 128-bit enum returns.** All 202 affected scalar/record pairs differ. Zig 0.17 LLVM returns raw i128/u128 in a `<2 x i64>` result but lowers the enum result through an extra hidden return pointer. That also shifts the actual argument locations. The [standalone compiler control](../ci/abi_128_repro.zig), with no aegis imports and even a named enum tag, retains this defect; [emitted IR](a3-abi-128-windows.txt) records both caller bodies and the separately compiled raw export signature. This is an actual calling-convention mismatch, not harmless alias spelling or a sizeof failure.

The required ABI gate stays red. `--audit` continues to collect all targets and native evidence but exits with failure if any pair differs. Normal `check-contracts` stops at the first mismatch. No width/target exemption, shim, matching typed prototype, compiler patch or suppressed gate was introduced. Landing and A4 implementation remain blocked. A change to the supported profile is an owner decision; this candidate makes no such change.

## API, release checks and cost

[Targeted validation](a3-abi-correction-behavior.txt): 15 A3 tests pass in each of Debug, ReleaseSafe and ReleaseFast (45/45), with negative domain/clock/unit/policy fixtures and test compilation passing. The added regression exercises every affected factory and every supported signed/unsigned representation, enum identity/layout, min/max/one, independent endian byte oracles, zero NonZero imports, ranged import bounds, negative-to-unsigned conversion and Counter exhaustion without mutation. Existing independent exhaustive arithmetic/conversion properties remain active. Targeted runs used `-Dci-lint=false` to run behavior independently of the known failed ABI extra-check; the default CI contract is unchanged.

[Default contract result](a3-abi-correction-contracts.txt): ReleaseSafe/Fast required pre/post/invariant failure and portable scalar compilation complete before the raw ABI gate rejects Windows 128-bit returns. Source quality, lint, layers, cast reasons, documentation, test-import and package-path stages pass; overall `zig build lint` remains red because it also invokes the required ABI extra-check. This is not a green full local gate.

`zig build check-parity` passes all 30 paired enclosing consumers on x86_64 and aarch64 Linux baseline CPUs, LLVM, stripped objects, in ReleaseSafe and ReleaseFast. Updated `codegen-a3-*-*.md` records equal symbol sizes and identical instructions for all pairs, including the original eleven owner pairs and affected scalar kernels. There is no allocation, indirect dispatch, stored tag or extra runtime field in these scalars. Required arithmetic/conversion checks remain in the identical handwritten baselines.

Forecast remains O(1) scalar operations, O(repr byte width) encoding; enum tags/bounds/scales occupy no storage. [Paired timing](a3-abi-correction-timing.txt) reruns the unchanged equivalent checked baseline harness: Apple M3 Max, macOS 26.2 (25C56), Zig 0.17.0 LLVM, native CPU, ReleaseFast, stripped. Thirty-two interleaved ABBA/BAAB samples after warmup, 20 million operations per pair, seven-sample minimum exceeded; best/median/p95/p99/spread and 10,000-draw paired 95% bootstrap median-ratio intervals are retained. Host load/noise is visible, not discarded. All nineteen intervals include 1.00, so none resolves a slowdown; statistical overlap alone is not proof of parity. Deterministic instructions are the separate parity evidence. This is synthetic consumer cost, not a cloak adoption speedup.

| Affected caller | Baseline/wrapper median ns/op | Paired median ratio 95% interval |
|---|---:|---:|
| ranged | 1.389/1.353 | [0.9814, 1.0214] |
| identity | 1.193/1.197 | [0.9972, 1.0051] |
| counter | 1.212/1.207 | [0.9985, 1.0049] |
| count | 1.305/1.302 | [0.9877, 1.0063] |
| bits | 1.268/1.275 | [0.9973, 1.0050] |
| duration | 1.312/1.324 | [0.9933, 1.0118] |
| rounding | 1.385/1.399 | [0.9988, 1.0138] |
| instant | 1.201/1.201 | [0.9998, 1.0003] |
| encoding | 1.147/1.147 | [0.9989, 1.0009] |

## Pins, workflow and remaining work

Verified published green mains: preflight b28046cc22055fcd32640117fc0e6965283a8ae5, merge run 37823307574 success; shakedown 9357a9ab398ac25fa8a408a71e77a124bc51d311, run 37820085077 success. Immutable Git URLs use the canonical fetched contents (archive-root fetching produced a local hash mismatch). No dependency source is patched. The required compiler must lead PATH as well as invoke the parent build, so subprocesses do not select the host's Zig 0.16.

New preflight owns the canonical `zig build plan -- --workflow .github/workflows/ci.yml`; the predecessor duplicate planner was removed. Workflow matrices were regenerated and the existing targeted merge TSan job retained with the new preflight pin. CI still compiles own benches and does not gate timing. `docs/a3-enforcement.md` recognizes enum backing imports instead of nonexistent private numeric fields. Those specs remain future admission contracts, not implemented glint enforcement.

Book drift: repos/aegis.md retains the old floor SHA and unbuilt catalogue; actual GitHub visibility is public. The design's floor/implementation/evidence tables predate landed A1/A3. c8d2b48's intended scalar ABI guarantee additionally needs the now-reproduced Windows 128-bit compiler boundary addressed. safety-for-zig's A3 extern-struct historical log is correctly labeled as requiring this repair. No book edits were made.

No hosted FAST/MERGE was dispatched for a candidate whose deterministic ABI gate is known red. Published main stays fcff07b. Resolve the owner/compiler-profile decision first, complete and commit the accepted A3 repair, then implement A4 SecretBytes in this same owned clone. Final FAST/MERGE must certify the combined exact head before a normal fast-forward landing. No A5 work is authorized or started.
