> Historical A3 report from fcff07b. The extern-struct C-interoperability claim below is withdrawn by book c8d2b48; its matching typed prototypes did not test a raw integer boundary. See [A3 ABI correction](a3-abi-correction.md) for the actual failing-before evidence, enum repair and remaining compiler blocker. The original timing/codegen artifacts remain historical evidence only.

# A3 numeric/domain foundations

A3 implements only scalar `int`, `id`, `units`, and `assert` contracts. Secret(T), spin Guarded(T), their extraction evidence and the original codegen artifacts are preserved. No cloak/adopter code, glint rules, handles, capability/scope system, checked references, borrow annotations or book edits belong to this batch.

Starting published main: b68e00a5ec4f33d53a85e46b81a92d676006b0ad. Its v0 merge run 37795255136 and fast run 37793601368 succeeded on that exact commit. Queried published dependency mains remained preflight 9af905ed85cab6dbb19d9431c65ee3f41fbaa74d (green 37711386950) and shakedown d5d19d39bc60cec59456aca947a3a7b484b87318 (green 37768627963), so existing pins remain current. Only published main commits are dependencies.

Analytic forecast: every scalar occupies precisely Repr size/alignment; compile-time tags/bounds/scales add no storage, allocator, registry or indirect dispatch. Checked operations cost their native overflow/range/zero/shift checks. ID equality is one comparison; counter next is one checked increment. Unit conversion costs exact scale arithmetic plus explicit rounding and sign/target bounds. Larger intermediates are needed only when neither native-width multiplication nor division safely represents the mathematical result. Invariants cost the required conditional fail-stop. Optional diagnostics and possibility counters have zero production release operations. The paired baseline retains identical safety and fallible contracts; “free” is zero abstraction overhead, not zero safety cost.

API refinements: arithmetic wrappers accept raw operands for direct `try Checked.init(count).mul(width)` ergonomics. Count/duration addition requires matching types; multiplication takes a scalar. Counter accepts only unsigned repr and imports last-issued state explicitly. Instant.correspond requires explicitly normalized matching scale/repr samples and checks offset/addition; sample correctness and epoch persistence remain caller policy. IDs use stable Wyhash of canonical little-endian repr with seed zero, not a cryptographic hash. Whole-byte encoding is explicit; arbitrary integer widths can perform arithmetic without pretending they are wire byte formats. No implicit checked-to-saturating promotion, clock cast or instant+instant is supplied.

Regression-first evidence: `a3-regression-first.txt` records missing A3 APIs on unchanged v0; no existing v0 bug was claimed. Contract suites exhaust u8/i8 arithmetic and shifts, include width-one and usize extremes, signed min/-1, div0, range construction/operation/encoding, negative/narrowing casts, zero/nonzero IDs, exhausted issuer persistence, byte rounding at max, signed floor/ceil/exact conversions, large-result downscaling, fake-clock suspension/real jumps, correspondence, std.Io clock mismatch and encoding. Shakedown property cases independently compare wider arithmetic and conversion results. Fifteen additional compile-negative fixtures reject domain/clock/unit/policy mixing, instant addition, incoherent bounds, floats, zero-width repr, signed issuers and partial-byte encoding. ReleaseSafe/ReleaseFast subprocesses prove pre/post/invariant failure, and portable profiles cover x86 32-bit, wasm32 and aarch64 freestanding.

Validation, codegen and timing results are recorded below. New future lint identities, examples, exceptions and honest analysis gaps are in `a3-enforcement.md`. No unbuilt rule is advertised as enforcement.

Book drift: repos/aegis.md and the aegis design describe a private/empty floor and unimplemented v0; v0 is public main and A3 is separately implemented here. The earlier original extraction-site admission restriction is superseded by the owner's general-purpose scope. A2 remains cloak adoption and is not an A3 prerequisite. Full catalogue, future glint admission and consumer workloads/adoption remain outstanding; this batch claims no release completion or cloak speedup.

Historical owner decision db30b0 used one-field extern structs for ABI scalars. That decision and the associated C interoperability claim were corrected by c8d2b48. The former 606-call test used the same aegis type on both prototypes and proved only compiler eligibility and layout; it did not prove raw-integer calling conventions. `a3-abi-before.txt` concerns the earlier auto-layout rejection, not the defect discovered on x86 32-bit. The new correction retains both kinds of evidence separately.

Shift correctness: Zig 0.17's optimized narrow shift check/reconstruction fails the original signed wider-loop consumer even for a wholly handwritten raw implementation. `a3-shift-repro.zig` and `a3-shift-lowering.txt` retain that compiler control, whose final plain-reference test intentionally fails; the first four corrected aegis cases pass. The shipped kernel computes an exact double-width shift, checks both repr bounds and narrows, retaining all count/overflow/underflow checks. The unchanged failing consumer shape remains in the passing A3 release suite. Required safety was never removed for a cost result.

## Local validation and cost evidence

Final local `zig build lint check` succeeded, with the targeted Debug A3 suite and both release suites passing. `a3-local-validation.txt` retains the gate output; `a3-debug-validation.txt` records 14/14 focused Debug tests and benchmark/example smoke checks. Both release suites pass 14/14. The source closure is std only; consumer isolation, layer checks, fifteen new rejection fixtures, six release fail-stop subprocesses, portable profiles and eight typed-prototype objects compiled (historical; not raw-integer interoperability proof). The workflow matrices were regenerated by published preflight's `zig build plan` for fast/merge/release and matched the existing workflow; no package-owned planner was introduced. Existing targeted native TSan remains in merge.

`codegen-a3-{x86_64,aarch64}-linux-gnu-{ReleaseSafe,ReleaseFast}.md` retains object symbol sizes, normalized assembly and optimized IR for all 30 pairs: eleven unchanged owners plus nineteen A3 caller workloads. Every pair has equal code size and instructions with the same checks. Layout is Repr size/alignment; all scalar tags/bounds/scales occupy zero runtime bytes. Release erasure/order gates remain active for the original owners. Representative aarch64 ReleaseFast sizes are add 24/24 bytes, shift 72/72, ranged 76/76, bits rounding 28/28, duration 40/40 and invariant 36/36. No allocator or retained capacity exists in these scalar operations; zero allocation is established by the std-only scalar implementations/consumer code, not a fabricated runtime allocator counter.

Timing host: Apple M3 Max, aarch64 macOS 26.2 (25C56), Zig 0.17.0, LLVM, native CPU, ReleaseFast, stripped executable. Command:

```sh
zig build-exe -OReleaseFast -fllvm -fstrip -mcpu=native --dep numeric -Mroot=bench/numeric.zig --dep aegis -Mnumeric=ci/numeric.zig -Maegis=src/root.zig -femit-bin=.zig-cache/numeric-bench
.zig-cache/numeric-bench
```

`a3-timing-final.txt` retains all raw half-samples and pairs. Each of 32 samples per operation alternates ABBA/BAAB, averaging two 10-million-iteration halves per side, after warmup. Callbacks have equal 64-byte alignment and share one noinline timing loop. Independent synthetic checked baselines observe both success and failure inputs; invariant uses a valid bounded caller path. Checksums prevent dead elimination. The report uses the conventional even-sample median and 10,000 paired-bootstrap draws (seed 0xa361). Both allocation and retained-capacity columns are zero because these operations have no allocating path. Timing is reported, never a CI timing hard gate.

| Caller | Median baseline/wrapper ns/op | Best baseline/wrapper ns/op | Paired median ratio 95% interval |
|---|---:|---:|---:|
| add | 1.185/1.185 | 1.165/1.164 | [0.9994,1.0012] |
| sub | 1.166/1.166 | 1.163/1.163 | [0.9992,1.0014] |
| mul | 1.145/1.145 | 1.142/1.142 | [0.9991,1.0011] |
| div | 1.199/1.199 | 1.177/1.177 | [0.9987,1.0011] |
| rem | 1.206/1.206 | 1.204/1.204 | [0.9994,1.0013] |
| shift | 1.271/1.270 | 1.267/1.266 | [0.9975,1.0005] |
| saturating | 1.183/1.184 | 1.179/1.178 | [0.9994,1.0015] |
| ranged | 1.212/1.211 | 1.190/1.190 | [0.9994,1.0008] |
| cast | 1.165/1.165 | 1.162/1.162 | [0.9994,1.0018] |
| identity | 1.167/1.166 | 1.163/1.164 | [0.9998,1.0012] |
| counter | 1.167/1.167 | 1.164/1.163 | [0.9988,1.0009] |
| count | 1.168/1.168 | 1.142/1.147 | [0.9978,1.0011] |
| bits | 1.184/1.182 | 1.170/1.169 | [0.9977,1.0027] |
| duration | 1.185/1.184 | 1.168/1.181 | [0.9989,1.0006] |
| rounding | 1.321/1.324 | 1.296/1.293 | [0.9988,1.0035] |
| instant | 1.184/1.181 | 1.164/1.164 | [0.9995,1.0008] |
| invariant | 0.817/0.819 | 0.814/0.813 | [0.9981,1.0008] |
| diagnostics | 1.142/1.142 | 1.122/1.122 | [0.9995,1.0008] |
| encoding | 1.125/1.124 | 1.122/1.121 | [0.9989,1.0007] |

All nineteen final intervals include 1.00; no resolved slowdown remains. p95/p99 and full spread are retained per row in the raw artifact. This primitive/synthetic caller result does not claim a consumer adoption speedup or eliminate safety cost.

Diagnosis history is retained, not discarded: `a3-timing-1.txt` and `-2.txt` used unaligned 2-million-iteration samples and upper-middle medians; `-3.txt` used aligned 20-million samples with the same median issue; `-4.txt` corrected that estimator; `-5.txt` also matched stripped assembly-gate flags. Initial positive intervals included addition [1.0002,1.0007], remainder [1.0003,1.0029] and eventually invariant [1.0006,1.0021]. Addition's actual native callers have byte-identical instructions (`a3-native-caller.txt`); invariant's baseline/wrapper even share the identical entry address. These controls exposed placement and temporal measurement effects rather than removable checks or library instructions. The final balanced-block harness fixes the drift-sensitive measurement, retains every half, and meets the gate. Older data also retain host outliers up to 22 ns/op; those are not hidden or credited as wrapper wins.

Remaining work: actual cloak/family adoption and workload A/B, later catalogue batches and glint admission remain separate authorized tasks. No owner-only A3 decision remains outstanding. Hosted fast and exact-final-head merge success are required before the FF main push; run links identify the landed commit in GitHub Actions.
