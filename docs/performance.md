# Same-operation performance gate

Napkin envelope: Secret holds exactly its inline representation and erases O(sizeof(T)) bytes; Guarded has the direct lock/data layout and its guard is one pointer. Neither primitive allocates. Required erasure, CAS/spin and release stores are real work in every mode. No crypto, scheduler, reference-counting or allocator policy is included.

## Deterministic evidence

`zig build check-parity` compiles paired exports with Zig 0.17.0, LLVM, baseline CPU, stripped ELF objects, x86_64-linux-gnu/aarch64-linux-gnu × ReleaseFast/ReleaseSafe. Every one of the eleven pairs shares the same emitted function in all four objects. Exact machine-code byte counts match; the checker also accepts distinct symbols only if normalized instructions match exactly. Only symbol/local-label/comment/directive noise is normalized, never stack reservations, opcodes, operands or operation counts. Layout/alignment equality and pointer-only guard assertions compile.

Fixtures are in [cases.zig](../ci/cases.zig) and [parity.zig](../ci/parity.zig); [codegen.zig](../ci/codegen.zig) owns the enforced checks. Material is the actual C1 declaration extraction checked against immutable cloak source as [provenance](extraction.md) describes. Equal by-value initialization is essential: the direct Material cleanup owner uses the same init(value) → single-field-owner operation as Secret.init, rather than comparing against an unrelated literal-initialization path. No erasure or lock is omitted.

The optimized dead-final-storage callers cover 48-byte and Material cleanup on public normal/error return paths. Their common cleanup remains after the return-value decision. LLVM retains volatile stores or memset intrinsics with the volatile flag true. Large Material erasure lowers to a retained libc memset call on these backends in BOTH variants; that is backend lowering of a volatile intrinsic, not an unmarked source memset or an eliminated wipe. The guarantee is the retained full-region operation, not volatile hardware instructions or universal removal of copies/spills. Caller/parser/crypto copies outside the owned region remain outside this proof.

Machine-code bytes below are the common baseline/wrapper size, including matched checks and test-observation constraints:

| Pair | x86 Fast | x86 Safe | arm64 Fast | arm64 Safe |
|---|---:|---:|---:|---:|
| secret_s32 | 34 | 42 | 64 | 64 |
| transfer_s32 | 100 | 100 | 120 | 120 |
| secret_s48 | 38 | 46 | 68 | 68 |
| transfer_s48 | 116 | 116 | 136 | 136 |
| secret_material | 52 | 71 | 68 | 88 |
| transfer_material | 146 | 165 | 164 | 180 |
| cleanup | 58 | 66 | 64 | 64 |
| cleanup_material | 130 | 130 | 240 | 236 |
| budget | 228 | 228 | 340 | 340 |
| job | 149 | 149 | 228 | 228 |
| increment | 37 | 37 | 88 | 88 |

Full IR/instruction records: [codegen-x86_64-linux-gnu-ReleaseFast.md](codegen-x86_64-linux-gnu-ReleaseFast.md), [codegen-x86_64-linux-gnu-ReleaseSafe.md](codegen-x86_64-linux-gnu-ReleaseSafe.md), [codegen-aarch64-linux-gnu-ReleaseFast.md](codegen-aarch64-linux-gnu-ReleaseFast.md), [codegen-aarch64-linux-gnu-ReleaseSafe.md](codegen-aarch64-linux-gnu-ReleaseSafe.md). Reproduce with `zig build check-parity -- --record`.

Allocations: 0 for both v0 primitives and their direct operations, established by their source/call graphs and identical optimized objects. The construction fault fixture retains two caller allocations (48-byte destination and 32-byte scratch), checks every allocation failure through NoResize, observes erased bytes before raw free, and asserts each successful allocation is freed exactly once. A late error after ownership publication is covered too. No release registry or extra retained allocation is introduced. Thread/Io setup and native platform allocator internals are caller resources, not claimed to allocate zero.

## Manual timing

Host: Apple M3 Max, arm64 Darwin 25.2.0. Zig 0.17.0, native target, LLVM ReleaseFast. Host compiler executable SHA-256 `1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523`. `zig build bench` runs [owners.zig](../bench/owners.zig). Each final replicate uses 32 paired samples after warmup, balanced alternating AB/BA order, 5,000,000 iterations for scalar rows and 100,000 increments per worker for contention. Clock.awake measures elapsed wall time; contention includes matching Group submission/join. No core pinning. Bootstrap resamples paired ratios 10,000 times with seed 0xae615; the interval is the central 95% for the median wrapper/baseline ratio. Median ns/op, reciprocal throughput and observed min/max spread are reported. These are throughput timings, not per-operation latency distributions or a constant-time test.

Timing loops are noinline to remove caller-specific inlining/layout. Both A/B labels for each row call the identical emitted body, documented in [benchmark-codegen.md](benchmark-codegen.md). Compiler-observation barriers are identical on both sides and emit no added CPU instruction; they retain payload reads, full representation copies, writes and wipes that a dead destination would otherwise let the optimizer discard. Budget reserves and releases in separate sections, as cloak does; Job publishes/takes in separate sections. The compiler inspection confirms the 1,056-byte memcpy, both volatile Material wipes, and acquisition/release loops remain.

Two preselected final replicates, all rows retained:

| Row | Run 1 baseline/wrapper ns/op | Run 1 ratio95 | Run 2 baseline/wrapper ns/op | Run 2 ratio95 |
|---|---:|---|---:|---|
| secret32 | 1.291/1.290 | [0.9965,1.0021] | 1.292/1.293 | [0.9982,1.0056] |
| transfer32 | 2.425/2.426 | [0.9981,1.0042] | 2.424/2.423 | [0.9974,1.0041] |
| secret48 | 1.645/1.645 | [0.9989,1.0012] | 1.643/1.642 | [0.9989,1.0025] |
| transfer48 | 3.107/3.103 | [0.9978,1.0015] | 3.105/3.104 | [0.9988,1.0010] |
| material | 24.242/24.257 | [0.9993,1.0023] | 24.202/24.204 | [0.9995,1.0008] |
| transferMaterial | 46.910/46.911 | [0.9995,1.0020] | 46.460/46.472 | [0.9990,1.0005] |
| budget | 3.850/3.866 | [0.9972,1.0067] | 3.795/3.801 | [0.9955,1.0079] |
| job | 4.168/4.168 | [0.9983,1.0006] | 4.049/4.049 | [0.9981,1.0029] |
| contention2 | 5.084/5.165 | [0.9556,1.0670] | 3.410/3.193 | [0.9366,1.0752] |
| contention8 | 90.248/86.244 | [0.8974,0.9921] | 54.579/52.377 | [0.9289,1.0111] |

[Run 1 raw pairs/throughput/spread](timing-final-1.txt) and [run 2](timing-final-2.txt). The best measured replicate medians are visible in the table; no individual sample was dropped. Neither final replicate has an interval entirely above 1.00. One contention interval is below 1 despite identical code: it reflects scheduling, not a claimed wrapper speedup. Noise alone is not proof of zero overhead; that conclusion for these fixtures rests on deterministic layout/instruction identity and retained-work inspection.

## Investigation history and limits

All exploratory rows remain: [attempt 1](timing-attempt-1.txt), [attempt 2](timing-attempt-2.txt), [attempt 3](timing-attempt-3.txt), [attempt 4](timing-attempt-4.txt), [attempt 5](timing-attempt-5.txt). Attempt 1 used short samples alongside compilation and reported Material transfer ratio95 [1.0001,1.0138]. Attempts 2/3 used longer isolated samples; attempt 3 reported Material [1.0004,1.0038] and Job [1.0035,1.0342]. Those results triggered investigation, not acceptance. Isolating timing loops produced attempts 4/5 with shared bodies and no resolved increases, but further IR inspection found discarded transfer work in the original harness. All five are superseded as acceptance measurements; their rates must not be presented as the complete transfer operation. The final observation barriers and separate Budget sections repair that measurement flaw; final runs and IR above retain the required work. The library code did not change to omit a wipe, check or lock.

These results cover aegis operations on one host plus deterministic two-CPU/two-mode codegen. They do not close cloak private-kernel erasure/timing, sustained parser campaigns, hostile/default-cap resource limits, native OS policy or independent review, and do not authorize cloak adoption. Shared CI checks deterministic correctness/parity and only benchmark smoke; it never applies timing thresholds. Hosted/Linux TSan execution status is in [validation.md](validation.md). No rival comparison was made or named.
